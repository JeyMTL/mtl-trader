# MTL Trader - Project Notes

## What is this?
A SaaS trading journal web app for tracking and analyzing MT5 trades. Built with Next.js 16, React 19, TypeScript, Tailwind CSS 4, Supabase, Recharts, and PayPal.

## Completed Features
- **Landing page** - Hero, features, pricing, footer
- **Auth** - Login/signup with Supabase Auth
- **Dashboard** - Command-center layout: account balance, net P&L, win rate, profit factor, drawdown/best/worst/expectancy strip, equity/daily P&L toggle, current-month heatmap, time edge, latest journal entries, recent fills, quick actions
- **Trade History** - Search, filter (all/wins/losses), delete, edit trades
- **CSV Import** - Upload MT5 CSV trade history; also reads .xlsx files and Excel-saved-as-CSV (auto-detects the real format via magic bytes + delimiter sniffing, and maps columns from headers for both MT5 and broker layouts)
- **Analytics** - Equity curve, P&L by day chart, monthly P&L chart, performance by symbol table, stats (win rate, profit factor, expectancy, max drawdown)
- **Manual Trade Entry** - Form at `/dashboard/trades/new` with symbol, buy/sell, entry/exit, lot size, SL, TP, commission, swap, strategy, dates, notes, live P&L preview
- **Trade Editing** - Edit form at `/dashboard/trades/[id]/edit` - same fields as manual entry
- **Journal Media** - Photos (camera/gallery) and voice notes (MediaRecorder, or an uploaded audio file) attach to a trade. Stored in the private `journal-media` Supabase Storage bucket at `<user_id>/<trade_id|draft>/...`; metadata in `trade_attachments`; UI uses one-hour signed URLs. Create-mode files upload immediately and are linked after the trade row exists, with retry-safe attach
- **Entry/Exit Time Window** - `open_time`/`close_time` are surfaced as a dedicated section with pickers, duration, and an exit-before-entry check; the trade log shows the clock window and time in market
- **Time Edge Report** - `time_stats()` buckets trades by entry hour in the user's timezone and by session (Asian / London / overlap / New York / late). Analytics and the dashboard show most-profitable/most-losing hours and sessions, a 24-hour P&L chart, session win rates and median hold time. Pure helpers live in `src/lib/edge-window.ts` (unit tested)
- **Flutter Mobile App** - `mobile_flutter/` is a native Flutter client with the same Supabase project: flat design, desk KPIs + equity chart, paged journal, photo/voice-note capture, entry/exit time window, time edge report and account/plan screen. It replaces the Capacitor shell for phones; platform folders are generated with `flutter create`
- **Light & Dark Themes** - The Flutter app has two palettes (`AppPalette.dark` / `AppPalette.light`) and a "follow the device" mode, switchable in Account → Appearance and remembered via `shared_preferences` (`app.theme.v1`). `AppColors` forwards to the active palette so every screen follows; switching rebuilds the subtree (keyed by mode) because widgets read colours through getters, not an inherited context
- **Google Sign-In** - Web login/signup and the Flutter login screen offer Google OAuth through Supabase (`signInWithOAuth`). `/auth/callback` exchanges the PKCE code, creates the profile through `/api/auth/signup`, then routes to the dashboard. Email/password stays available; only Google accounts skip the verification email, because Google has already verified the address
- **Interactive Chart Canvas** - The level-pinning chart has a fullscreen mode (immersive system UI, back exits it) and a chart-style sheet: four presets (Ink/Slate/Paper/Mono), per-side candle colours from a palette, and grid/crosshair/watermark toggles. `ChartStyle` in `mobile_flutter/lib/core/chart_theme.dart` (unit tested) owns the canvas palette, so a light or monochrome chart never repaints the journal around it; level lines keep the app palette because they match the level rows. The choice is restored at startup from `shared_preferences` (key `chart.style.v1`)
- **Market Replay** - The chart can replay history bar by bar: it starts two thirds into the loaded series, steps forward/back, auto-plays, and hides every candle after the cursor so pinning entry/stop/target behaves as it would live (entry/exit timestamps come from the replayed bar). `ReplayCursor` in `mobile_flutter/lib/core/chart_replay.dart` (unit tested) owns the stepping rules; live refresh pauses while replaying and resumes on exit. The strip also cycles replay speed (1×/2×/4×/8×), jumps to a chosen date, and at the first loaded bar turns the back button into "load earlier candles". Both use `from`/`to` on `/api/market/candles` (epoch ms or ISO, 62-day cap, validated server-side, translated to OANDA's `from`/`to` bounds) and historical windows are cached for 30 minutes because they never change
- **Export Trades** - Download filtered trades as CSV from trade history page
- **Dark/Light Mode** - Toggle in Settings > Appearance, saved to localStorage. Light mode uses soft muted tones for eye comfort
- **Settings** - Profile, Balance (deposits/withdrawals), Appearance, Subscription, Notifications, Security
- **Deposit/Withdrawal System** - Add deposits, view history, total balance. `deposits` table in Supabase with RLS policies
- **PayPal Integration** - Checkout API at `/api/checkout` creates a PayPal order; `/api/paypal/capture` verifies the payer and amount, then applies the plan
- **PayPal Webhook** - `/api/webhooks/paypal` verifies the signature and applies the plan server-side, so a closed tab no longer loses a payment
- **Payment Reconciliation** - `/api/admin/reconcile` replays recent completed captures through the same idempotent `applyPaidOrder` path (admin-triggered or a daily Vercel cron). It records each event once in `payment_events` and never downgrades an active plan
- **Bank Transfer Payments** - `/dashboard/payment` creates a server-validated request with a unique user/plan reference; admins approve/reject via `/dashboard/admin` (protected by `is_admin` flag, not subscription tier)
- **Email Verification** - Supabase-confirmed email is required for dashboard and bearer-authenticated API access
- **Monthly Trade Quota** - Postgres trigger (`enforce_trade_quota`) blocks inserts beyond the plan's monthly limit; historical imports don't count against it
- **Import Reliability** - Trades are stamped with `import_id` so deleting an import removes exactly those trades; MT5 tickets are captured for sync/import dedupe
- **Email Summaries** - `/api/cron/notifications` sends daily/weekly (Monday)/monthly (1st) performance summaries via Resend to users whose notification preferences are on. No-ops when `RESEND_API_KEY` is unset; skips empty windows. Window math and due-checks live in `src/lib/notification-schedule.ts` (unit tested)
- **Journal Reminders** - The same cron emails opted-in users a weekday nudge when nothing has been journaled yet that day. Summary windows and working days are computed in each user's `timezone` (short labels like `PST` map to DST-aware IANA zones; junk falls back to UTC). The `notifications_monthly_overview` toggle only controls the dashboard card; the monthly email has its own `notifications_monthly_email` preference
- **Manual Notification Check** - `node --env-file=.env.local scripts/check-notifications.mjs` audits config; `--send <to>` sends a Resend test email and `--run` calls the deployed cron and prints its result
- **Manual Payment Check** - `scripts/check-payments.mjs` audits payment env vars (folds in the old `check-paypal.mjs`); `--verify` validates the PayPal credentials against the API and `--reconcile` calls the reconcile cron and prints its result
- **AI Journal Review** - `/api/ai/review` returns a structured, grounded review: deterministic edge stats (`src/lib/ai/edge-stats.ts`) are narrated by the model, over the trader's own notes via TF-IDF retrieval. Reviews persist to `ai_reviews`, cache for 24h, guard against tiny samples, and support OpenAI/Anthropic/OpenAI-compatible providers, chart images, and token streaming. `/api/ai/autotag` suggests tags with no model call. Inert without an AI key (returns 503). See `docs/AI.md`; fine-tuning is intentionally not implemented
- **Bank Details API** - `/api/bank-details` serves bank transfer details from `BANK_*` env vars so they are no longer hardcoded in the client
- **Market Chart Feed** - The Flutter level-pinning chart reads candles from `/api/market/candles` (Supabase-authenticated, rate-limited, shared server cache). The route proxies a vendor feed for forex, metals, indices and crypto — the market a broker actually quotes, instead of Yahoo's composite spot feed — and refuses symbols the vendor does not quote. **OANDA v20** is the only candle vendor — there is no fallback feed. The route answers 503 when `OANDA_API_TOKEN` is unset and 502 for a symbol OANDA cannot quote, so the chart never shows prices from an unnamed source. The app sends an explicit candle size (1m, 5m, 15m, 30m, 1h, 4h, 1d) plus an optional `from`/`to` window; the route refuses a window that would need more than OANDA's 5,000-candle cap. Live candles are cached 20s per symbol+interval and historical windows 30 minutes. Mapping and normalisation in `src/lib/market-candles.ts` are unit tested; the token stays server-side
- **Chart Studies** - The level-pinning chart draws candles, a close line or a filled area, with SMA 20/50/200 and EMA 21 overlays toggled from the style sheet. The maths lives in `mobile_flutter/lib/core/indicators.dart` (unit tested); the price axis widens to include a visible average, the OHLC readout shows each enabled value, and chart type plus enabled studies persist with the style in `ChartStyle`. RSI period (7/14/21) and the MACD fast/slow/signal lengths are editable, the price axis can be switched to logarithmic (mapping shared with tap handling in `core/chart_scale.dart`), and trend lines/horizontal rays are stored per instrument by candle time in `SharedPreferences` so they survive a new window, candle size or session

## Database Tables (Supabase)
- `users` - User profiles with subscription info, `agent_token`, `is_admin`
- `trades` - All trade data (symbol, type, entry/exit, lot, pnl, `ticket`, `import_id`, etc.)
- `deposits` - Deposit/withdrawal history (user_id, amount, type, description)
- `payment_requests` - Bank transfer payment requests awaiting admin approval
- `payment_events` - One row per processed payment event (`provider` + `provider_event_id` unique), for idempotent application and reconciliation
- `trade_attachments` - One row per journal photo or voice note (`kind`, `storage_path`, `mime_type`, `size_bytes`, `duration_seconds`), cascading with the trade; RLS own rows only
- Storage bucket `journal-media` - Private; policies require the first path segment to equal `auth.uid()`

Schema + RLS + quota trigger live in `supabase/migrations/20260908_full_schema_rls_quota.sql` (idempotent).
Grant admin with: `UPDATE users SET is_admin = true WHERE email = 'you@example.com';`

## Running the App
```bash
cd D:\mtl-trader
npm run dev
```
Runs on http://localhost:3000 (or 3001 if port is taken)

## Tests
```bash
npm test
```
Vitest covers the import parser, P&L/point-value math, the plan/trial/quota rules, payment idempotency, summary rendering, the auth/bank guards, and the market-data mapping/normalisation.

## PayPal Setup
To enable payments:
1. Create a PayPal developer account at https://developer.paypal.com
2. Create a REST app to get Client ID + Secret
3. Add to `.env.local`:
```
PAYPAL_CLIENT_ID=xxx
PAYPAL_CLIENT_SECRET=xxx
NEXT_PUBLIC_APP_URL=http://localhost:3000
```
4. The app uses the production PayPal endpoint (`api-m.paypal.com`); set `PAYPAL_API_BASE=https://api-m.sandbox.paypal.com` for testing

## Email / Resend Setup (optional)
1. Create an account at https://resend.com and verify a sending domain
2. Add to `.env.local`:
```
RESEND_API_KEY=re_xxx
EMAIL_FROM=MTL Trader <reports@yourdomain.com>
CRON_SECRET=<random-string>
```
3. Without these the app still runs; summary sends and the notifications cron are skipped
4. Optionally configure Supabase Auth to send through Resend SMTP so verification emails aren't rate-limited

## Google Sign-In Setup (optional)

Code status: the web login/signup pages and the hero on `/` all call `signInWithOAuth`, and the Flutter deep link scheme is registered on both platforms. Everything below is **dashboard work** — no further code changes are needed to complete the flow.

1. Google Cloud Console → APIs & Services → Credentials → create an **OAuth client ID** (Web application). Authorised redirect URI: `https://<your-project-ref>.supabase.co/auth/v1/callback`. The **Client ID** it hands you is the `000000-xxxx.apps.googleusercontent.com` string — that exact value goes in Supabase, never the anon key.
2. Configure the OAuth consent screen first, and add your own Google account under **Test users**. Until the app is published, only those accounts can sign in.
3. Supabase → Authentication → Providers → **Google**: enable it, paste the client ID + secret from step 1, leave **Allow users without an email** off.
4. Supabase → Authentication → URL Configuration:
   - Site URL: your deployed domain
   - Additional redirect URLs: `https://your-domain/auth/callback`, `http://localhost:3000/auth/callback`, and `com.mtltrader.app://login-callback` for the phone app
   - Google must only ever redirect to the Supabase `/auth/v1/callback` URL; Supabase then forwards to the `/auth/callback` values listed here
5. Flutter deep link (already committed, listed for reference): the scheme is registered so the browser can hand the session back
   - Android `android/app/src/main/AndroidManifest.xml`, inside the main activity:
     ```xml
     <intent-filter>
       <action android:name="android.intent.action.VIEW" />
       <category android:name="android.intent.category.DEFAULT" />
       <category android:name="android.intent.category.BROWSABLE" />
       <data android:scheme="com.mtltrader.app" android:host="login-callback" />
     </intent-filter>
     ```
   - iOS `ios/Runner/Info.plist`: a `CFBundleURLTypes` entry with `CFBundleURLSchemes` = `com.mtltrader.app`
   - Different scheme? Pass `--dart-define=OAUTH_REDIRECT=your.scheme://login-callback` and add that exact URL to Supabase

Without the provider enabled, every Google button surfaces Supabase's error and email/password keeps working.

## Email Verification Setup

The "no wrong emails" control is **Authentication → Sign In / Providers → Email → Confirm email**. Turn it on.

The app already assumes it is on: `/auth/login` and the Flutter `AuthGate` refuse a session whose `email_confirmed_at` is null and show a verify screen, and signup signs the user back out and says to check the inbox. With the toggle off, `signUp` returns a live session and those guards never fire, so unverified addresses walk straight into the dashboard.

Google accounts skip this by design — Google has already verified the address.

Checklist:
- [ ] Confirm email = on
- [ ] Site URL and redirect allows set (see above)
- [ ] Supabase SMTP configured, or Resend wired as the SMTP provider, so verification mail is not rate-limited
- [ ] One signup with a deliberately wrong address confirms the mail gates the dashboard

## Bank Transfer Setup (optional)
Set `BANK_NAME`, `BANK_ACCOUNT_NAME`, `BANK_ACCOUNT_NUMBER`, and `BANK_BRANCH` in `.env.local`; the payment page fetches them from `/api/bank-details`.

## Known Issues
- Toggling Light/Dark rebuilds the app subtree (`KeyedSubtree` keyed by mode), so navigation returns to the Desk tab and that screen refetches. Per-widget palette lookups through the context would avoid that, but they touch every screen
- Every instrument charts live OANDA CFD data: the app polls every 60s for all asset classes and shares one 45s client cache, so there is no separate delayed path or badge
- OANDA coverage is not the whole catalogue: `DOGEUSD` has no vendor mapping and `SOLUSD`/`XRPUSD`/`BNBUSD`/`ADAUSD` are refused with `Unsupported instrument`, so those five return "No chart data" instead of falling back. `BTCUSD` and `ETHUSD` work. Verified 2026-10-31 against the practice host
- OANDA's API licence covers your own account's trading, not redistributing its feed — clear the vendor terms before charging for charts
- The chart is OANDA-backed end to end: indices and energy resolve to its CFD instruments (NAS100 → `NAS100_USD`, USOIL → `WTICO_USD`, GER40 → `DE30_EUR`). Symbols OANDA does not carry answer 502 "No chart data" instead of falling back to another feed. Verified 2026-10-31: `EUR_USD` M5 candles return from the practice host
- Apply `supabase/migrations/20261028_journal_media_and_time_stats.sql` before using media, the time edge report or the redesigned dashboard; the RPCs and storage bucket live there
- Flutter is not installed in every dev environment. `mobile_flutter/` ships Dart source only: run `flutter create --platforms=android,ios --project-name mtl_trader_mobile .` once from that folder to generate `android/` and `ios/`, then `flutter pub get`
- `@next/swc-win32-x64-msvc` not a valid Win32 app (uses WASM fallback, works fine)
- Supabase anon key in `.env.local` may be placeholder - verify it's real
- PayPal keys need to be configured for payments to work
- `.env.example` now uses placeholders only and documents all PayPal/Resend/cron/bank vars (Stripe entries removed)
- PayPal upgrades are applied by the success-page capture call and, as a fallback, by the signature-verified webhook at `/api/webhooks/paypal`. Set `PAYPAL_WEBHOOK_ID` and register the webhook in the PayPal dashboard, otherwise the fallback is disabled
- Bank-transfer upgrades still require admin approval until a bank transaction API or webhook is connected
- Email summaries require `RESEND_API_KEY` + a Resend-verified domain; without them sends are no-ops (by design, never an error)
- The notifications cron and reconciliation cron both require `CRON_SECRET`; Vercel sets it via the project's env vars

## Pending / Nice to Have
- Trade notes/tags inline editing
- Bank transaction API/webhook for automatic bank-transfer activation
- Auto-expiry of trial/subscription statuses

## File Structure
```
src/app/
  page.tsx                    # Landing page
  layout.tsx                  # Root layout (with ThemeProvider)
  globals.css                 # Theme colors (dark + light)
  auth/login/page.tsx         # Login
  auth/signup/page.tsx        # Signup
  dashboard/page.tsx          # Dashboard (balance, equity curve, stats)
  dashboard/layout.tsx        # Sidebar navigation
  dashboard/trades/page.tsx   # Trade history list (with edit, export)
  dashboard/trades/new/page.tsx # Manual trade entry
  dashboard/trades/[id]/edit/page.tsx # Edit trade
  dashboard/import/page.tsx   # CSV import
  dashboard/analytics/page.tsx # Charts and analytics
  dashboard/settings/page.tsx # Settings (profile, balance, appearance, subscription, etc.)
  pricing/page.tsx            # Pricing page (PayPal + bank transfer)
  api/checkout/route.ts       # PayPal order creation API
  api/paypal/capture/route.ts # PayPal capture (amount + payer verified)
  api/webhooks/paypal/route.ts # Signature-verified PayPal webhook (authoritative upgrade)
  api/payment-requests/route.ts # Bank-transfer request creation (server-priced)
  api/admin/payments/route.ts # Admin approve/reject of payment requests
  api/admin/reconcile/route.ts # Replay captured-but-unapplied payments (admin or cron)
  api/bank-details/route.ts   # Bank details (from BANK_* env vars)
  api/market/candles/route.ts # Market-data proxy for the Flutter chart
  api/cron/notifications/route.ts # Daily/weekly/monthly summary emails (cron)
  api/plans/route.ts          # Plans API
src/components/
  journal-media.tsx           # Photo picker, voice recorder, audio upload, previews
mobile_flutter/               # Native Flutter app (flat design)
  lib/core/, lib/models/, lib/services/, lib/screens/, lib/ui/
supabase/migrations/20261028_journal_media_and_time_stats.sql
src/lib/
  supabase.ts                 # Browser Supabase client
  server-auth.ts              # Bearer auth + admin client (service role)
  subscription.ts             # Single source of truth for plan/trial/quota rules  import-parser.ts             # CSV/XLSX/SpreadsheetML trade parser (unit tested)
  market-candles.ts            # Provider chain, symbol mapping + candle normalisation
  rate-limit.ts               # Shared (Postgres-backed) per-user rate limiter
  payments.ts                 # PayPal helpers + idempotent applyPaidOrder
  email.ts                    # Resend wrapper (no-ops when unconfigured)
  summaries.ts                # Summary math + HTML email rendering
  auth-guards.ts              # Timing-safe bearer/cron secret checks
  bank.ts                     # Bank details from env
  utils.ts                    # formatCurrency, formatPercent, formatDuration, calculatePnL, getPointValue
  journal-media.ts            # Upload/sign/list/delete journal photos and audio
  edge-window.ts              # Best/worst hour and session ranking (unit tested)
  plans.ts                    # Pricing plan data
  theme.tsx                   # Dark/light mode context
src/types/
  index.ts                    # TypeScript types (Trade, User, etc.)
```
