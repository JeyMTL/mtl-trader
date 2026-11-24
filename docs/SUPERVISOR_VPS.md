# Running the sync supervisor on a small VPS

The supervisor drives a real MetaTrader 5 terminal through the `MetaTrader5`
Python package. That package ships Windows wheels only (`win_amd64`) and talks to
`terminal64.exe` over Windows IPC, so **the host must be Windows**. A Linux box
cannot run it without Wine, and Wine is untested here — do not buy a Linux VPS
for this.

This runbook is sized for **2 vCPU / 2 GB RAM**, which is enough for the
sequential mode only: one terminal, accounts taking turns. Fleet mode (a terminal
per account) starts at 4 GB.

| Host | Mode | What it carries |
| --- | --- | --- |
| 2 vCPU / 2 GB | sequential (`FLEET_SIZE=0`) | one watched account at ~2s latency, the rest on a 3-minute rotation |
| 2 vCPU / 4 GB | sequential | same, with room for Windows Update and a second terminal |
| 4 vCPU / 8 GB | fleet (`FLEET_SIZE` up to ~30) | most accounts journaled within seconds |

Measured cost per chartless fleet slot is ~140 MB working set and ~2.5% of one
core, so the 2 GB machine has no room for a second slot once Windows Server
(~1.2 GB idle) and the Python process are in.

Files this uses:

* `supervisor/setup_vps.ps1` — installs Python 3.12, MT5, the dependencies and writes `.env`.
* `supervisor/deploy/small-vps.env` — the tuned settings for this host.
* `supervisor/deploy/run-supervisor.ps1` — log file plus restart loop.
* `supervisor/deploy/register-task.ps1` — starts it at logon and restarts it.

## 1. Instance

* **OS:** Windows Server 2022 (or 2025) Base, 64-bit.
* **Size:** `t3.small` (2 vCPU / 2 GB) is the minimum. `t3.medium` (4 GB) is the
  sane choice if you expect more than a handful of accounts or want Windows
  Update to run without swapping.
* **Disk:** 30 GB gp3. MT5 plus a broker's history is a few GB; the 8 GB default
  is not enough.
* **Security group:** no inbound ports beyond RDP (3389) restricted to your own
  IP. The supervisor makes outbound HTTPS calls to Supabase and to
  `https://mtlledger.com`; it never listens on a port.
* **Static IP / Elastic IP:** not required, nothing dials in.

## 2. Copy the supervisor folder

From your machine, copy the repo's `supervisor` folder to `C:\MTL\supervisor` on
the server (RDP clipboard, SCP, or `aws s3 cp`). Include `mt5-brokers.json`; the
supervisor uses it to correct broker server spellings.

## 3. Run the installer

Elevated PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MTL\supervisor\setup_vps.ps1
```

It prompts for `SUPABASE_SERVICE_ROLE_KEY`, `SYNC_CREDENTIAL_KEY` and
`SYNC_SUPERVISOR_TOKEN` — the same three values Vercel holds, and the two sync
secrets must match the web app byte for byte. It writes `C:\MTLSync\.env` and a
dry run at the end.

## 4. Make the terminal portable

The installer points `MT5_PATH` at `C:\Program Files\MetaTrader 5`. On a
dedicated host that works, but the portable copy is what the daily-stop lock
needs: the supervisor writes `[Experts] AllowLiveTrading=1` into a **portable**
terminal's `common.ini` so MT5 accepts orders without a click.

```powershell
Stop-Process -Name terminal64 -ErrorAction SilentlyContinue
Copy-Item 'C:\Program Files\MetaTrader 5' 'C:\MT5-Sync' -Recurse
```

Then edit `C:\MTLSync\.env` to say:

```
MT5_PATH=C:\MT5-Sync\terminal64.exe
MT5_PORTABLE=1
```

Do not copy a terminal that is running, and never point this at the terminal you
trade on: the supervisor logs in and out of customer accounts, which replaces
whatever session is open.

## 5. Apply the small-host settings

Copy `supervisor/deploy/small-vps.env` over `C:\MTLSync\.env` and fill in the
four secrets from the `.env` the installer wrote:

```powershell
Copy-Item C:\MTL\supervisor\deploy\small-vps.env C:\MTLSync\.env
notepad C:\MTLSync\.env
```

What the 2 GB tuning does, and why:

| Setting | Value | Reason |
| --- | --- | --- |
| `FLEET_SIZE` | `0` | no RAM for extra terminals; sequential mode shares one session |
| `CYCLE_SECONDS` | `30` | new sign-ins are claimed every 30s instead of 15s; one constant query either way |
| `REFRESH_SECONDS` | `180` | this is the cost that grows with customers; 3 minutes keeps a small host inside its budget |
| `WATCH_SECONDS` | `2` | the one connected account is still journaled ~2s after the close |
| `MAX_ACCOUNTS` | `6` | a single cycle cannot run for minutes; least recently synced accounts go first |
| `APP_URL` | `https://mtlledger.com` | the VPS does not run Next.js |
| `FAILED_RETRY_SECONDS` | `900` | a rejected password does not hold the only session hostage |

## 6. Survive a reboot

The scheduled task triggers at logon, because MT5 in session 0 (a service) is
where the IPC calls get flaky. Turn on auto-logon so a reboot restores the
desktop session by itself:

```powershell
# Sysinternals Autologon is the least error-prone way:
#   https://learn.microsoft.com/sysinternals/downloads/autologon
# Or set it by hand under:
#   HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon
#   AutoAdminLogon=1, DefaultUserName=..., DefaultPassword=...
```

A server whose task runs at logon without auto-logon silently stops syncing
after the first reboot. That is the failure mode to avoid.

## 7. Start it and verify

```powershell
powershell -ExecutionPolicy Bypass -File C:\MTL\supervisor\deploy\run-supervisor.ps1 -Once
```

A healthy `--once` prints one line per connection it worked, or nothing when
there is no pending connection. Then register the task:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MTL\supervisor\deploy\register-task.ps1
Get-ScheduledTask -TaskName 'MTL Ledger Sync Supervisor' | Select TaskName, State
Get-Content C:\MTLSync\logs\supervisor.log -Tail 20
Get-Process terminal64, python -ErrorAction SilentlyContinue |
    Select ProcessName, Id, @{n='MB';e={[int]($_.WorkingSet64/1MB)}}
```

Checklist:

1. Task state is `Running`.
2. The log shows `starting C:\MTLSync\mt5_supervisor.py` and no repeated
   `[fatal]` line. A `fatal` line means a missing env value — it names it.
3. `terminal64` is present only while a session is being worked, or held open
   while watching one account.
4. Combined working set stays under ~1.6 GB. If it climbs, raise
   `REFRESH_SECONDS` and lower `MAX_ACCOUNTS`.
5. Connect a test account from the phone: the row should leave `pending`, go
   `connecting`, then `connected`, and closed trades should appear.

## 8. Known limits on this host

* **One account at a time gets near-live journaling.** Others rotate every
  `REFRESH_SECONDS`. That is a property of one terminal, not of the server.
* **Investor passwords cannot cancel orders.** MT5 answers `10017 Trade
  disabled` when the account was saved with its investor (read-only) password,
  so the daily-stop lock's resting-order deletion needs a master password. The
  log says so once instead of failing silently.
* **A hard lock's EA still needs a chart.** The supervisor covers the
  cancel-after-stop half; the guard EA is what blocks the initial click.
* **Windows Update reboots** take the terminal down for a few minutes; the log
  will show it reconnecting.

## Scaling later

* **Second host, same project:** set `SUPERVISOR_SHARDS=2` on both and
  `SUPERVISOR_SHARD=0` / `1` respectively, changed on both at the same time.
  Ownership is `crc32(user_id) % SUPERVISOR_SHARDS`, so no schema change is
  needed.
* **Real fleet mode:** move to 4 vCPU / 8 GB and prepare slots with
  `setup_fleet.ps1 -Count N` (`N` ≤ ~30), then set `FLEET_SIZE=N` and
  `MT5_FLEET_DIRS` from what it prints.
