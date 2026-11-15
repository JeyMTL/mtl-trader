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

### Immediate journaling

With **exactly one** connected account, the supervisor stays logged in and polls
the terminal's deal history every `WATCH_SECONDS` (2). A close is journaled in
about 2–5 seconds, no EA required.

One MT5 terminal has one session, so two accounts cannot both be watched. With
two or more connections the supervisor falls back to the rotation above
(`REFRESH_SECONDS`), which is the honest limit of one terminal. Set
`WATCH_SECONDS=0` to disable the watch and always use the rotation.

While it is watching, that terminal stays logged into the connected account.
Use the portable copy if you want your own trading terminal left alone.

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
| `login rejected - check the investor password and server name` | Use the investor password (not the master), and the exact server name from MT5. |
| `ingest rejected (HTTP 401)` | `SYNC_SUPERVISOR_TOKEN` does not match the web app. |
| `ingest rejected (HTTP 403)` | The account's plan has no sync feature, or its email is unverified. |
| Connection stays `pending` | The supervisor is not running, or `APP_URL`/Supabase credentials are wrong. |
| `decrypt failed` | `SYNC_CREDENTIAL_KEY` differs from the one the phone encrypted with. |
