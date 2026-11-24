# MT5 sync and push — outstanding follow-ups

Last updated: 2026-11-24.

Everything here is unfinished work, in the order it should be done. Nothing in
this file is a wish: each line is a job that was identified but not carried out.

## 1. Push notifications (do this first — it is the only blocker)

The code is finished and tested, but no Firebase project exists yet, so no
notification can actually be delivered.

- [ ] **Create the Firebase project.** `console.firebase.google.com` → Add
      project → name it `MTL Ledger` → skip Analytics (not needed).
- [ ] **Add the Android app.** Project settings → Add app → Android, package
      `com.mtltrader.app`. Copy the five values into
      `mobile_flutter/dart_defines.json`:
      `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`,
      `FIREBASE_PROJECT_ID`, `FIREBASE_STORAGE_BUCKET`.
      No `google-services.json` is needed — the app initialises Firebase from
      these values, which is why builds stay green with them empty.
- [ ] **Create the service account.** Project settings → Service accounts →
      Generate new private key. Paste the whole JSON as **one line** into
      `FIREBASE_SERVICE_ACCOUNT`:
      - in Vercel (production, so `/api/push/send` can sign FCM requests),
      - in `supervisor/.env` only if the supervisor runs somewhere that reads it.
- [ ] **Apply the migration** `supabase/migrations/20261130_push_tokens.sql`.
      Until it exists, `/api/push/register` answers 500 and no device is stored.
- [ ] **Rebuild and install:**
      `flutter build apk --release --dart-define-from-file=dart_defines.json`
      then `adb install -r build/app/outputs/flutter-apk/app-release.apk`.
- [ ] **Prove it end to end:** open the app once (permission prompt → Allow),
      then stop the supervisor host (or rename `MT5_PATH` so logins fail) and
      wait one cycle. The phone should show "MT5 sync stopped" with the app
      closed.

## 2. Ship what is already written

Nothing from this session is committed yet.

- [ ] **Commit:** supervisor fixes (first-sync history wait, broker-clock
      offset, retired-install skip, visible `mark()` failures, failure push),
      `supervisor/test_supervisor.py`, reconnect clearing `last_sync_at` in
      `src/app/api/broker/connection/route.ts`, the push client
      (`lib/services/push.dart`, `lib/core/config.dart`,
      `lib/services/journal_api.dart`, `lib/screens/app_shell.dart`, `pubspec`),
      the push server (`src/lib/push.ts`, `api/push/register`,
      `api/push/send`), the migration, `.env.example`, `.gitignore`.
- [ ] **Deploy the web app.** `MT5_SYNC_ENABLED` is already `true`, so
      `/dashboard/sync` should appear in the sidebar; if it 404s, the deployment
      predates commit `3b67d85`.
- [ ] **Verify on the web:** open `https://mtlledger.com/dashboard/sync` while
      signed in. It should show the desktop EA token section.
- [ ] **Level picker fix needs the same deploy:** "Pin levels on chart" sent
      `interval=M15`, which `/api/market/candles` rejects as an unknown interval,
      so the picker showed an empty chart and blamed the symbol. It now sends
      `15m`/`1h`/`4h`/`5m`. Confirm on the live site that the picker draws
      candles for EURUSD before closing this.

## 3. A host for the supervisor (blocked on money)

The supervisor works; there is nowhere to leave it running. Until this is done,
phone sync only works while your own PC is on.

- [ ] **Buy the Windows VPS when funds allow:** OVHcloud VPS-2 (2027 range),
      4 vCPU / 8 GB RAM / 75 GB NVMe with **Windows Server 2025 Standard**,
      ~$10/mo ex VAT month-to-month ($8.50 on a 12-month term). Check the cart
      for a separate licence line before paying, and add the automated backup.
- [ ] **Or let credits pay for it:** Microsoft for Startups ($200 immediately,
      +$4,800 after business verification) on Azure is the best fit because
      Azure sells Windows Server VMs; AWS Activate Founders ($1,000) covers the
      existing instance; the Google for Startups Start tier (~$2,000) is only
      useful for Linux-side hosting, not the Windows VM.
- [ ] **Set the host up** (`supervisor/setup_vps.ps1` expects
      `C:\Program Files\Python312` and
      `C:\Program Files\MetaTrader 5\terminal64.exe`):
      - copy `mt5_supervisor.py`, `mt5-brokers.json`, `.env` into `C:\MT5-Sync`;
      - register the supervisor as a **Scheduled Task** running as SYSTEM with
        "run whether user is logged on or not", so a closed RDP session does not
        stall the terminal;
      - log into MT5 once by hand, then close it, so the terminal has a saved
        account for the first cold start.
- [ ] **Then flip `MT5_HOSTED_SYNC_ENABLED` to `true`** in
      `src/lib/features.ts` so the web offers the same phone connect the app
      now shows.

## 4. Data repair

- [ ] **Trades synced before today carry the broker's clock, not UTC** (stored
      2–3 hours early: everything from the supervisor before 2026-11-24). New
      trades are correct. Decide whether to leave the old rows or rewrite them
      once; the affected rows are `trades` with a `position_id` whose
      `created_at` is before 2026-11-24 for supervisor-synced accounts.
- [ ] **Missing-history recovery** now works only *after* the reconnect change
      is deployed: pressing Reconnect clears `last_sync_at`, so the next sync
      re-reads a full year.

## 5. Known limits, decided deliberately

- Foreground pushes are not drawn as in-app banners; Android shows them when the
  app is backgrounded or closed.
- iOS needs an Apple APNs key uploaded in Firebase before push works there.
- Server-side push is wired only for "sync stopped". Trial ending, payment
  failure and prop-rule breaches do not notify yet.
- `mobile_flutter/lib/screens/trade_form_screen.dart` still refuses
  broker-suffixed symbols such as `EURUSDM` when pinning from a chart.
- 4 vCPU / 8 GB covers roughly 6–8 accounts that stay logged in; 20–30
  simultaneous needs a ~32 GB host or a second shard. Do not buy either before
  a paying user exists.
- `.server-offset.json` and `.terminal-cache.json` are per-host state and are
  gitignored; do not copy them between hosts — they recalibrate automatically.

## Verified on 2026-11-24 (so it does not need re-checking)

- Supervisor against the live FundedNext account: login in 3.6 s, a full year of
  history read, 3 previously missing trades backfilled with correct UTC times,
  connection row moved from `failed` to `connected`.
- `python -m unittest test_supervisor` → 25 passed.
- `flutter analyze lib` → clean; `flutter test` → 336 passed.
- `npx tsc --noEmit` → clean.
- Debug and release APKs build with the Firebase values empty.
