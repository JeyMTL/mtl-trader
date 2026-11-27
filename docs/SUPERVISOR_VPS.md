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
| 4 vCPU / 8 GB | fleet, capped by free RAM (about 18 slots at 240 MB each) | accounts beyond the cap rotate, so they wait longer |

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

### Fleet slots never need a hand login

A slot copied from a plain install ships with the installer's MetaQuotes demo as
its saved account. When that demo stops authorising, MT5 opens its **modal Login
window** at startup, and that window owns the slot's IPC pipe: every
`initialize()` then answers `-10005 IPC timeout` and the account is unreachable,
no matter how many times it is retried. That is a terminal waiting for a person,
not a broken account.

The supervisor closes such a terminal and starts it again with the account on the
command line — `terminal64.exe /portable /login:… /password:… /server:…` — which
works in a folder that has never authenticated. So a slot that times out is
reopened with its own login instead of being reported as failed, and nobody has
to log in by hand on the host.

When even that start is refused, the folder is the one thing that cannot be
fixed from inside the process, and the supervisor stops spending accounts on it:
the slot is taken out of the rotation (`… cannot log in …; that folder stays out
of the rotation until it has been logged in once by hand`) and the account is
handed to the next healthy slot in the same cycle (`moving to slot N: the folder,
not the account, refused the login`), so its closes keep arriving. The folder is
tried again after 30 minutes. One that keeps refusing needs the single login MT5
will not accept from a program — `terminal64.exe /portable` in that slot's
directory, log in, close it — and a host whose copies were all made from a
terminal that never authenticated will need that once per slot.

### The slot's saved account is never trusted

A portable terminal boots from `config\accounts.dat`, which remembers the account
*and password* of whichever login was saved there last. A slot that a person
signed into once — the setup hand login, usually with the **master** password —
therefore comes up already authenticated, and `account_info()` reports the very
account the row asks for. Same number, same deals, so matching on the login alone
reported `connected` while the investor password in the app was never presented:
a session that can also trade, behind a read-only promise.

So a matching account is not a matching credential. The supervisor re-authenticates
in place with the password stored in the row (one auth round trip), and if the
terminal refuses it reopens the slot with `/login:`/`/password:` on the command
line. Only a session opened with that password is reported as connected; when
neither works the account is marked failed with the reason, rather than left on a
session nothing in the app can vouch for. A restart of the supervisor costs one
re-authentication per account and no terminal restart.

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
| `WATCH_SECONDS` | `1` | a close is journaled about a second after it happens; MT5 has no deal push |
| `RECONCILE_SECONDS` | `300` | a held session re-reads its cursor every 5 minutes, so a close the poll missed still lands without a reconnect |
| `LOCK_POLL_SECONDS` | `10` | a close is checked for the lock immediately; this only catches a rule edited in the app |
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
  log says so once instead of failing silently, and says the opposite once too:
  `[info] account … is signed in with a login that can trade`, which is what a
  master password, or a hand login the slot still remembers, looks like.
* **A trade deleted in the app stays deleted.** `/api/sync` records deleted
  position ids and refuses them on every later sync, so re-importing an account
  whose journal was cleared does not bring the old rows back. The slot log says
  `N of M position(s) were deleted from the journal earlier` when this bites.
* **A hard lock's EA still needs a chart.** The supervisor covers nothing of
  the lock; only the guard EA acts on it, and it cannot block the initial click —
  it deletes resting orders and closes the fill. Only the broker can refuse it.
* **Windows Update reboots** take the terminal down for a few minutes; the log
  will show it reconnecting.

## Scaling later

* **Second host, same project:** set `SUPERVISOR_SHARDS=2` on both and
  `SUPERVISOR_SHARD=0` / `1` respectively, changed on both at the same time.
  Ownership is `crc32(user_id) % SUPERVISOR_SHARDS`, so no schema change is
  needed.
* **Real fleet mode:** prepare slots with `setup_fleet.ps1 -Count N`, then set
  `FLEET_SIZE=N` and `MT5_FLEET_DIRS` from what it prints.

  The fleet is capped by **memory, not by the number you ask for**. Each slot is
  a logged-in terminal plus its worker process, so a slot costs roughly
  `SLOT_MEMORY_MB` (default 240). The supervisor measures free physical memory
  at startup and starts only what fits after `MEMORY_RESERVE_MB` (default 900)
  is kept back, logging `[capacity] … starting N` when that is fewer than
  `FLEET_SIZE`.

  | Host RAM | Slots that fit (240 MB each, 900 MB reserved) |
  | --- | --- |
  | 8 GB | ~14 |
  | 16 GB | ~30 |
  | 32 GB | ~55 |

  That cap exists because running past it is not a slow host, it is a dead one:
  the next allocation fails inside OpenBLAS, the supervisor exits, and the
  wrapper restarts it into the same wall — every account offline until someone
  intervenes. Measured on the 8 GB host, 30 requested slots produced exactly
  that crash loop.

  So **30 accounts need a 16 GB host, or two 8 GB hosts** with
  `SUPERVISOR_SHARDS=2` and `SUPERVISOR_SHARD=0`/`1`. Set `FLEET_SIZE=30`
  either way: the accounts that do not fit a slot still sync in rotation
  (`FLEET_MIN_HOLD_SECONDS`), so a close lands in a minute or two instead of a
  couple of seconds — late, never lost.

  Measure your own host before trusting the default:

  ```powershell
  (Get-Process terminal64 | Measure-Object WorkingSet64 -Sum).Sum/1MB
  (Get-Process python | Measure-Object WorkingSet64 -Sum).Sum/1MB
  ```

  If a warm terminal is larger than the default, set `SLOT_MEMORY_MB` to its
  working set plus ~40 MB for the worker.

## Wipe the host and keep every account's history

The host holds no trades. The journal is `public.trades` in Supabase, and every
account's deals live on the broker's server, which a fresh terminal downloads
again on request. Deleting `C:\MTLSync` and every terminal directory cannot lose
a journaled trade — but it does throw away the only copy of four things:

| Keep | Why |
| --- | --- |
| `C:\MTLSync\.env` | `SYNC_CREDENTIAL_KEY` decrypts every saved account password. Lose it and all 30 customers must type their password again. `SUPABASE_SERVICE_ROLE_KEY` and `SYNC_SUPERVISOR_TOKEN` are the other two. |
| `C:\MTLSync\mt5-brokers.json` | comes in the update zip; the supervisor needs it to spell broker servers correctly |
| the update zip's `servers.dat` | MetaQuotes' server list, so a bare terminal can resolve a broker without a download |
| `.backfill` markers | only progress, not data. Deleting them restarts the read, which is what a wipe wants anyway. |

### 1. Back up the env file first

```powershell
Stop-ScheduledTask -TaskName 'MTL Ledger Sync Supervisor' -ErrorAction SilentlyContinue
Copy-Item C:\MTLSync\.env C:\Users\Administrator\Desktop\mtlsync.env.bak
Get-FileHash C:\Users\Administrator\Desktop\mtlsync.env.bak -Algorithm SHA256
```

Copy that file off the host before the next step. Without it the credentials in
Supabase are unreadable and every account has to be reconnected by hand.

### One package, one command

`dist/mtlsync-vps.zip` holds the whole host: `supervisor\` (supervisor, installer,
fleet setup, rebuild, audit) and `shared\mt5-brokers.json`. Expand it into `C:\`
so you get `C:\MTL\supervisor` and `C:\MTL\shared`, then:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MTL\supervisor\deploy\install-host.ps1 -FleetSize 18
```

`install-host.ps1` asks only for the secrets `.env` is missing, with
`Read-Host -AsSecureString`, so the values are never echoed into the console
buffer or a screenshot. It then writes `.env` itself (including
`MT5_FLEET_DIRS`, computed from `-FleetSize`, which is why nothing has to be
pasted by hand), installs Python and MT5 if absent, prepares the slots, points
`MT5_PATH` at the copy, and hands over to `reset-host.ps1`. Flags: `-DryRun`,
`-RotateSecrets`, `-BackfillDays`, `-DeepHistoryDays`, `-SkipRebuild`.

`-DryRun` prints the plan and every setting with the three secrets replaced by
`(set, hidden)`, which is the safe way to check a box before it is wiped.

`-RotateSecrets` asks again for the supervisor token and the credential key only,
which is what a value that appeared in a log needs. `-RotateServiceKey` adds
`SUPABASE_SERVICE_ROLE_KEY` to that list; it is separate because replacing it
also means creating a key in the Supabase dashboard and revoking the old one.

### Or let the script do the whole thing

`supervisor/deploy/reset-host.ps1` performs every step below and refuses to edit
`.env`: it stages the file and the code outside the host folder, hashes it,
stops the task, deletes the host folder, the terminal copies and the fleet
slots, puts the files back with `.env` byte-identical, re-copies the terminal,
prepares the slots and re-registers the task.

```powershell
# The script installs the code it sits in, so copy the current repo `supervisor`
# folder to C:\MTL\supervisor first (or pass -Source).
# Then set BACKFILL_DAYS=3650 in C:\MTLSync\.env by hand, and run:
powershell -ExecutionPolicy Bypass -File C:\MTL\supervisor\deploy\reset-host.ps1 -DeepHistoryDays 3650
```

`-DeepHistoryDays` also re-arms every live connection in Supabase, which is the
step SQL does by hand below. `-Verify` runs one `--once` pass before starting the
task. `-Yes` skips the `WIPE` prompt. If Python or the MT5 package is missing the
script stops before registering the task and tells you to run `setup_vps.ps1`.

`-DryRun` prints every path it would delete with its size and item count, each
top-level file in the host folder marked kept or gone, and every process it would
stop — then exits without touching anything. It works without elevation, so it is
the way to check the plan before committing to it:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MTL\supervisor\deploy\reset-host.ps1 -DryRun
```

After the task is back the script also registers `MTL Ledger History Repair`, a
one-shot task that runs five minutes later (move it with
`-PostAuditDelayMinutes`, skip it with `-NoPostAudit`). That run waits for the
fleet to settle — no `.backfill` marker left and every live connection synced
within the last 15 minutes — then stops the supervisor, audits the journal
against each broker, re-arms the backfill for the accounts with missing trades
and no others, starts the supervisor again, and unregisters itself. If the audit
queued anything, it waits for those re-reads to drain (up to four hours), audits
once more, and reports the second result too — one recheck, not a loop, so a gap
the backfill cannot close is named and left alone. Its console
output lands in `C:\MTLSync\logs\repair-<stamp>.log` (and
`repair-<stamp>-recheck.log` for the second pass) and the list it queued in
`C:\MTLSync\repair-history.json`. A connection stuck on a bad password never
settles; the wait is capped at ten hours, after which the audit runs anyway and
reports that account as an error rather than a gap.

The manual steps below are the same work, and the fallback if the script fails
partway.

### 2. Delete the host

```powershell
Unregister-ScheduledTask -TaskName 'MTL Ledger Sync Supervisor' -Confirm:$false -ErrorAction SilentlyContinue
Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item C:\MTLSync -Recurse -Force
Remove-Item C:\MT5-Sync -Recurse -Force
Remove-Item C:\MT5-Fleet -Recurse -Force        # fleet slots, if this host had them
```

### 3. Rebuild it

Run the installer, then put the backed-up secrets back and set the read depth:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MTL\supervisor\setup_vps.ps1
Copy-Item C:\Users\Administrator\Desktop\mtlsync.env.bak C:\MTLSync\.env -Force
notepad C:\MTLSync\.env     # set BACKFILL_DAYS=3650 for ten years, MT5_PATH as before
Copy-Item 'C:\Program Files\MetaTrader 5' 'C:\MT5-Sync' -Recurse
```

`BACKFILL_DAYS=3650` is what makes the first sync read past the default year.
Each month is a separate terminal read with a wait of its own, so ten years is
roughly 20 minutes per pass, three passes per account — about an hour of filling
per account, and a fleet of 30 shares 18 slots, so run this overnight. The
account is being watched less closely while it fills; set `BACKFILL_DAYS=365`
again once the import is done.

### 4. Re-arm the read in Supabase

A connection that already has `last_sync_at` would only read from its cursor.
Clear it so the supervisor treats each account as a first sync:

```sql
update public.broker_connections
   set status = 'pending', last_sync_at = null, last_error = null
 where status <> 'disconnected';
```

If you also deleted journal rows to rebuild them, clear the tombstones that would
block the re-import. Every deleted trade wrote one, and `/api/sync` skips a
suppressed position on purpose:

```sql
-- only when the journal rows were deleted too
 delete from public.sync_suppressions where user_id = '<user-id>';
```

Do not clear suppressions for an account whose trades are still in the journal:
they are there because the customer deleted those trades themselves.

### 5. Confirm the history landed

```powershell
cd C:\MTLSync
python mt5_supervisor.py --once
Get-Content C:\MTLSync\logs\supervisor.log -Tail 40
```

The `--once` pass prints `N position(s)` for each account it worked. `history is
still downloading, so this read will be repeated` means the broker was slower
than the wait — the marker keeps the account in the backfill queue, so it
finishes on the next session. Then check the oldest row and the count:

```sql
select count(*), min(close_time), max(close_time)
  from public.trades where user_id = '<user-id>';
```

When the counts stop moving, restore the normal depth and start the task again:

```powershell
notepad C:\MTLSync\.env      # BACKFILL_DAYS=365
powershell -ExecutionPolicy Bypass -File C:\MTL\supervisor\deploy\register-task.ps1
```

### 6. Audit it, manually

`reset-host.ps1` schedules this already. To repeat it at any time — and to re-run
it after restoring `BACKFILL_DAYS=365` — run the same script by hand. It stops the
supervisor, audits, re-arms only the accounts whose brokers hold a trade the
journal lacks, and starts the supervisor again even if the audit crashes.

```powershell
powershell -ExecutionPolicy Bypass -File C:\MTLSync\repair-history.ps1 -Now -Days 3650
```

Without `-Now` it waits up to ten hours for the fleet to settle first, which is
what the scheduled run does. If the audit queues repairs, the script then waits
for those re-reads (up to `-RepairWaitMinutes`, default 240), audits again, and
reports the recheck; `-NoRecheck` stops after the first pass. Output is in
`C:\MTLSync\logs\repair-<stamp>.log`; the queued accounts are in
`C:\MTLSync\repair-history.json`, and the recheck's in
`repair-history-recheck.json`. The exit code is 0 for a clean audit, for one that
queued repairs and for a recheck that still found gaps; 1 only if the verifier
itself failed.
