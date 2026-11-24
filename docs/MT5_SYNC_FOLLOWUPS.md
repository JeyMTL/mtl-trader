# MT5 sync and push — outstanding follow-ups

Last updated: 2026-11-24.

Everything here is unfinished work, in the order it should be done. Nothing in
this file is a wish: each line is a job that was identified but not carried out.

## 1. Push notifications — works end to end (2026-11-24)

Proven on the device: the phone was sent a real notification while the app sat
in the background, and the notification shade showed `MT5 sync stopped` from
`pkg=com.mtltrader.app` on `fcm_fallback_notification_channel`. The send side
returned `POST /api/push/send` → `{"sent":1,"failed":0,"skipped":false}`.

- [x] **Create the Firebase project.** Done as `mtl-ledger`.
- [x] **Add the Android app.** Done, package `com.mtltrader.app`. The five
      values are in `mobile_flutter/dart_defines.json`:
      `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`,
      `FIREBASE_PROJECT_ID`, `FIREBASE_STORAGE_BUCKET`.
      No `google-services.json` is needed — the app initialises Firebase from
      these values, which is why builds stay green with them empty.
- [x] **Create the service account**, set as `FIREBASE_SERVICE_ACCOUNT` in
      `.env.local` (one line; the literal `\n` in the key is handled by
      `push.ts`). A token mint against `oauth2.googleapis.com` succeeded, so the
      key and the `firebase.messaging` scope are valid.
- [x] **Vercel production has `FIREBASE_SERVICE_ACCOUNT`** (Secret, Production)
      and was redeployed. `POST https://mtlledger.com/api/push/send` answers
      `{"sent":1,"failed":0,"skipped":false}` and the device showed the
      notification body that was sent. Nothing about push is outstanding.
- [x] **Apply the migration** `supabase/migrations/20261130_push_tokens.sql`.
      Done: `push_tokens` exists in the project (`token` primary key, `user_id`
      indexed, RLS on with no policies) and holds 0 rows, which is correct — no
      build carrying Firebase values has been installed yet. A probe of
      `/api/push/register` is no longer blocked by a missing table.
- [x] **Rebuilt and installed:**
      `flutter build apk --release --dart-define-from-file=dart_defines.json`
      then `adb install -r build/app/outputs/flutter-apk/app-release.apk`.
- [x] **Proved it end to end.** `push_tokens` holds the device, and it
      re-registers on every launch and sign-in.

### Trial ending and prop-breach pushes (added 2026-11-24)

- [ ] **Apply `supabase/migrations/20261131_push_events.sql`.** This is the
      dedupe table; until it exists the new triggers send nothing and log
      `push_events.missing_table` (deliberately: without a record of what was
      already said, a sweep is a duplicate generator).
- [ ] **Deploy.** `vercel.json` gained a second cron,
      `/api/cron/notify` at `0 9 * * *`, which only runs once deployed.
- Trial ending: users with `subscription_status = 'trial'` whose
  `trial_ends_at` falls inside the next 24 h get one push, keyed on the end
  date, so re-running the cron sends nothing.
- Prop breach: `/api/sync` calls `notifyPropBreach` after trades land (the
  trader with a terminal attached has no app open), reading `prop_status` — the
  same RPC the compliance card uses, so the push and the card cannot disagree.
  Keyed `<status>:<day>`, so one push per rule per day, and a fresh breach
  tomorrow is still news. The daily cron sweeps the same check as a backstop for
  trades typed in by hand.

Three silent bugs had to be fixed on the device first. None of them would have
surfaced in a unit test — each was only visible in `adb logcat`:

1. **`invalid_icon` from `Alerts.init`.** `ic_stat_ledger` sat in
   `res/drawable/` but was missing from the built APK: the release resource
   shrinker drops drawables that no layout, style or manifest references, and the
   plugin resolves this one by name at runtime. Fixed with
   `android/app/src/main/res/raw/keep.xml` (`tools:keep`). This was breaking
   *every* local notification as well — the journal reminder and the daily stop.
2. **`API disabled` from `messaging.register()`.** `firebase_messaging` 17 gets
   its token through the Installations API, which stays off until
   `<meta-data android:name="firebase_messaging_installation_id_enabled" android:value="true"/>`
   is in the manifest. Without it no token is ever issued.
3. **`FirebaseApp name [DEFAULT] already exists!`** `PushService.start()` runs
   from both `initState` and the auth stream; the two raced inside
   `initializeApp` and the loser marked push failed for the whole session. Fixed
   by holding the setup future (`_setup`) so concurrent callers share one
   initialisation, and by treating a duplicate app as success.

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
- Server-side push covers three things: "sync stopped" (supervisor), "trial
  ending" (daily cron) and prop-rule breaches (checked on every sync ingest, with
  a daily sweep as backstop). A failed payment still does not notify — the
  Paddle/PayPal webhooks already own that lifecycle, and a second sender there
  would need the same once-only record the other three now use.
- A lapsed subscription and a broken connection are told apart by the
  supervisor: the first gets "MTL Ledger sync paused" (plan ended), the second
  "MT5 sync stopped" (reconnect). The lapse notice is sent once and re-arms
  only after a sync succeeds, so a 10-minute retry loop cannot spam a customer
  whose plan stayed ended.
- `mobile_flutter/lib/screens/trade_form_screen.dart` still refuses
  broker-suffixed symbols such as `EURUSDM` when pinning from a chart.
- 4 vCPU / 8 GB covers roughly 6–8 accounts that stay logged in; 20–30
  simultaneous needs a ~32 GB host or a second shard. Do not buy either before
  a paying user exists.
- `.server-offset.json` and `.terminal-cache.json` are per-host state and are
  gitignored; do not copy them between hosts — they recalibrate automatically.

## Verified on 2026-11-24 (so it does not need re-checking)

- **Push pipeline, whole path.** `POST /api/push/send` with the supervisor
  token answers `200 {"sent":1,"failed":0,"skipped":false}` on the dev server,
  and the device posts the notification with the app in the background. The
  degraded path is also verified: with `FIREBASE_SERVICE_ACCOUNT` unset the same
  call answers `{"sent":0,"failed":0,"skipped":true}` instead of throwing, so a
  deployment without the key behaves exactly as it did before push existed.

- Supervisor against the live FundedNext account: login in 3.6 s, a full year of
  history read, 3 previously missing trades backfilled with correct UTC times,
  connection row moved from `failed` to `connected`.
- `python -m unittest test_supervisor` → 25 passed.
- `flutter analyze lib` → clean; `flutter test` → 336 passed.
- `npx tsc --noEmit` → clean.
- Debug and release APKs build with the Firebase values empty.
