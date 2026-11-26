# Hosted sync supervisor

This is what makes "connect from the phone" work: the phone stores the broker's
**investor (read-only)** password, encrypted with `SYNC_CREDENTIAL_KEY`; this
script runs on a Windows PC with MT5, logs in, reads closed positions and posts
them to `/api/sync`.

It never receives the master password, so it cannot place, close or modify a
trade.

## 1. Next app environment

In the web app's `.env.local`:

```
SYNC_CREDENTIAL_KEY=<32 random bytes, base64>
SYNC_SUPERVISOR_TOKEN=<random shared secret>
```

Generate them with:

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

`SYNC_CREDENTIAL_KEY` must stay stable: rotating it makes every stored
credential undecryptable and every customer has to reconnect.

## 2. Run it on a separate terminal

The supervisor logs in and out of customer accounts on whichever MT5 terminal it
drives. Do not point it at the terminal you trade on: those logins would keep
replacing your own session.

Copy the installation once (PowerShell):

```powershell
Copy-Item "C:\Program Files\MetaTrader 5" "C:\MT5-Sync" -Recurse
```

Set `MT5_PATH` to the copy and `MT5_PORTABLE=1`. Portable mode keeps that
terminal's accounts, history and config inside `C:\MT5-Sync` instead of sharing
`%APPDATA%` with your trading terminal. The supervisor starts it itself; you do
not need to open it first.

Do not copy a terminal that is running, and do not point both the supervisor and
`MT5_PATH` at your normal install.

### Any broker, not one broker

The terminal is chosen per account. For each login the supervisor tries, in
order: the terminal that last worked for that broker and server (remembered in
`supervisor/.terminal-cache.json`), `MT5_PATH`, then every `MT5_PATHS` entry,
then every `terminal64.exe` it finds under `Program Files`, `Program Files (x86)`
and `%LOCALAPPDATA%\Programs`. A terminal-side failure (`IPC timeout`, `Process
create failed`) is retried once on the same terminal before the next one is
tried; a rejected password or an unknown server is not retried, because it would
answer the same way twice.

That is what makes a prop-firm account work on a host whose plain MetaQuotes
terminal cannot resolve the firm's server: install the terminal the firm gave
you, and it is discovered automatically, or list it in `MT5_PATHS`. After one
successful login the supervisor remembers which terminal worked, so later cycles
go straight to it.

A terminal that comes up logged into a **different** account is rejected and the
next candidate is tried. Without that check, a terminal left on another
customer's session would stream their trades into the wrong journal.

Keep `supervisor/mt5-brokers.json` beside `mt5_supervisor.py` on the host. It is
the same directory the app uses, and lets the supervisor correct a known server
spelling on rows saved before that directory existed (`FundedNext-Server3` →
`FundedNext-Server 3`). Without it the supervisor still runs, but uses the
server exactly as stored.

## 3. Supervisor environment

Copy the template and fill it in:

```powershell
Copy-Item supervisor/.env.example supervisor/.env
notepad supervisor/.env
```

The fields:

| Variable | Value |
| --- | --- |
| `SUPABASE_URL` | Project URL, the same value as `NEXT_PUBLIC_SUPABASE_URL`. |
| `SUPABASE_SERVICE_ROLE_KEY` | Service-role key, server-side only. |
| `SYNC_CREDENTIAL_KEY` | Same value as the web app's `.env.local`. |
| `SYNC_SUPERVISOR_TOKEN` | Same value as the web app's `.env.local`. |
| `APP_URL` | `http://127.0.0.1:3000` on this PC (IPv4; `localhost` can resolve to IPv6 only). |
| `MT5_PATH` | `C:\MT5-Sync\terminal64.exe` for the copy. |
| `MT5_PORTABLE` | `1` for the copy. |
| `MT5_PATHS` | Optional. More terminals, separated by commas or semicolons, tried when the first cannot log the account in. |
| `SUPERVISOR_SHARDS` | Optional. How many supervisor hosts share this project's accounts. Default `1`. |
| `SUPERVISOR_SHARD` | Optional. Which share this host serves, `0`-based. Default `0`. Must be below `SUPERVISOR_SHARDS`. |
| `MAX_ACCOUNTS` | Optional. Most accounts this host works on per cycle. Default `0`, no cap. |
| `FLEET_SIZE` | Optional. Terminals held open at once, one account each. Default `0`, the sequential mode. |
| `MT5_FLEET_DIRS` | Needed when `FLEET_SIZE > 0`. One directory or `terminal64.exe` per slot, comma or semicolon separated. |
| `FLEET_MIN_HOLD_SECONDS` | Optional. How long a slot keeps an account before it can hand it back to a waiting sign-in. Default `60`. |

`load_dotenv` reads `supervisor/.env`; real environment variables still win, so
a service manager can override any value.

Install and test once:

```powershell
python -m pip install -r supervisor/requirements.txt
python supervisor/mt5_supervisor.py --once
```

Then leave it running:

```powershell
python supervisor/mt5_supervisor.py
```

`--once` prints how many positions each connection produced and exits. The
continuous run claims work every `CYCLE_SECONDS` (15) and re-reads connected
accounts every `REFRESH_SECONDS` (60). The claim query is one constant request,
so 15 seconds does not cost more as customers are added; the re-read cost does
scale per connected account, so raise `REFRESH_SECONDS` if the host is small.

The first sync waits up to 10 seconds for the terminal to download history,
because an empty read at that moment would advance the cursor past real trades.

### More than one host

The claim is a plain `GET`, so two supervisors on the same project both read
every pending account and both sync it. Split the accounts instead of relying on
the database to hand out exclusive work:

| Host | `SUPERVISOR_SHARDS` | `SUPERVISOR_SHARD` |
| --- | --- | --- |
| first | `2` | `0` |
| second | `2` | `1` |

Ownership is `crc32(user_id) % SUPERVISOR_SHARDS`, so every host agrees without a
schema change or an assignment table. Change both numbers on every host at once:
mismatched values mean the same account is owned by two hosts and is synced
twice. `MAX_ACCOUNTS` caps how many accounts one host works on per cycle, which
keeps a small host inside its refresh budget; when it is hit the least recently
synced accounts are served first, so the backlog rotates rather than starving.

### Immediate journaling

With **exactly one** connected account, the supervisor stays logged in and polls
the terminal's deal history every `WATCH_SECONDS` (1). A close is journaled in
about a second, no EA required. MT5's Python API has no push notification for
deals, so this poll is the floor; 1 s per held terminal is cheap because the
read is a short window, not the year.

One MT5 terminal has one session, so two accounts cannot both be watched. With
two or more connections the supervisor falls back to the rotation above
(`REFRESH_SECONDS`), which is the honest limit of one terminal — unless fleet
mode below is on. Set `WATCH_SECONDS=0` to disable the watch and always use the
rotation.

While it is watching, that terminal stays logged into the connected account.
Use the portable copy if you want your own trading terminal left alone.

### The daily stop, in the same second

Every close that reaches the journal is followed immediately by a lock check, so
a loss that breaches the day cancels resting orders in that same tick — no
waiting for a poll. `LOCK_POLL_SECONDS` (10) is only the fallback for a rule
edited in the app, or the trading day rolling over while a session is held.

The supervisor authenticates this check with `SYNC_SUPERVISOR_TOKEN`, so the
server buckets it per account rather than per host IP. That matters because a
fleet shares one IP: an IP bucket sized for a single EA ran out after about ten
minutes and every later check read as "unlocked". The supervisor token also
covers phone-only accounts, which have no `agent_token` of their own.

Enforcement is still limited to cancelling resting orders. It never closes an
open position, and an account saved with its investor password answers 10017 on
the first order, which is reported once in the log.

### Many accounts at once (fleet mode)

`FLEET_SIZE` lifts the single-session limit: each slot owns a terminal directory
and a worker process, and stays logged into its account for as long as that
account is connected. Every account in the fleet is then journaled within
`WATCH_SECONDS` of its close, instead of one at a time.

```powershell
powershell -ExecutionPolicy Bypass -File supervisor/setup_fleet.ps1 -Count 30
```

The script copies a clean terminal into each slot under `C:\MT5-Fleet`, deletes
the account, server list, history and profiles a used install would carry, and
writes a `SyncOnly` profile with no chart and `MaxBars=5000`. Paste the printed
`MT5_FLEET_DIRS` into `supervisor/.env` next to the matching `FLEET_SIZE`.

Measured per slot on a chartless, logged-in terminal:

| | Per slot | 30 slots |
| --- | --- | --- |
| Working set | ~140 MB | ~4.2 GB |
| Private commit | ~45–60 MB | ~1.8 GB |
| CPU, steady | ~2.5% of one core | ~0.75 of a core |
| Disk | ~390 MB | ~12 GB |

RAM is the limit: a 4 vCPU / 8 GB host carries about **30** terminals, and CPU
and disk are nowhere near theirs. A slot holds its account while it watches, so
when every slot is taken the newest sign-in has no terminal to go to; once a slot
has watched for `FLEET_MIN_HOLD_SECONDS` and another account is waiting, it hands
its account back to the rotation instead of parking the new one indefinitely.
Three rules keep the sizing numbers true:

* **Never open a chart** in a fleet instance. A charting profile measured 131 MB
  and had downloaded 2.3 GB of history across eight brokers; a chartless one
  writes no market data at all.
* **One directory per slot, and portable.** Two copies cannot run from the same
directory, and a non-portable copy shares `%APPDATA%` with every other slot and
  with the trader's own terminal.
* **A slot is not a shard.** `SUPERVISOR_SHARDS` splits accounts between hosts;
  `FLEET_SIZE` runs several accounts on one host. Use one shard per host and set
  `FLEET_SIZE` to what that host's RAM can hold.

`--once` still runs a single sequential pass; it is a diagnostic, not a fleet
run.

## 4. Phone pointing at this PC

The app must be reachable from the phone, not just localhost:

```bash
npm run dev -- -H 0.0.0.0
```

Allow Node through Windows Firewall on port 3000, find the PC's LAN address
(`ipconfig`), and build the phone app against it:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key> \
  --dart-define=API_BASE_URL=http://192.168.1.50:3000
```

Debug builds allow cleartext HTTP (`android/app/src/debug/AndroidManifest.xml`).
A release build needs HTTPS, so use a tunnel or a real domain for that.

On the phone: **MT5 Sync → Connect account**, enter broker, server, account
number and the **investor** password. The row appears as `pending`; the
supervisor claims it on the next cycle and it becomes `connected`.

## What it syncs

Only fully closed positions. A partial close is skipped until the position is
flat, because `/api/sync` ignores a duplicate `position_id` — pushing a scale-out
would freeze a partial P&L permanently.

The cursor is the last successful sync time. Closing deals in that window are
used to find position ids, then each full position is re-read by id, so a trade
that was open for hours (longer than the overlap) is still picked up.

## Troubleshooting

| Log | Meaning |
| --- | --- |
| `[fatal] missing environment: ...` | One of the four variables is not set in this shell. |
| `SYNC_CREDENTIAL_KEY must decode to 32 bytes` | Wrong key, or the base64 value was truncated. |
| `MT5 initialise failed: (-6, 'Terminal: Authorization failed')` | Open MT5 once, log in to any account, close it; or set `MT5_PATH`. Run the supervisor in a normal logged-in Windows session, not a service session. |
| `no terminal could log in to <server> as <login> (… -> (-10005, 'IPC timeout'))` | Every installed terminal refused that account. The message names each one and its error. An `IPC timeout` / `Process create failed` means the terminal did not come up — a previous supervisor killed mid-session leaves `terminal64.exe` running and the next start cannot attach; close it and retry. `Authorization failed` means the server or investor password is wrong, or the terminal cannot resolve that broker's server: install the broker's own terminal, or add it to `MT5_PATHS`. |
| `login rejected - check the investor password and server name` | Use the investor password (not the master), and the exact server name from MT5. |
| `ingest rejected (HTTP 401)` | `SYNC_SUPERVISOR_TOKEN` does not match the web app. |
| `ingest rejected (HTTP 403)` | The account's plan has no sync feature, or its email is unverified. |
| Connection stays `pending` | The supervisor is not running, or `APP_URL`/Supabase credentials are wrong. |
| `decrypt failed` | `SYNC_CREDENTIAL_KEY` differs from the one the phone encrypted with. |
| `terminal lost its session; logging back in` | The broker dropped the login while the account was being watched — weekends, a broker restart or a terminal update all do this. It logs back in with the stored investor password; if that fails it releases the terminal so the next cycle logs in cleanly. No action from the customer. |
| `[fatal] FLEET_SIZE=n needs n terminals in MT5_FLEET_DIRS` | The fleet is larger than the slots that exist. Run `setup_fleet.ps1 -Count n` and update `MT5_FLEET_DIRS`. |
