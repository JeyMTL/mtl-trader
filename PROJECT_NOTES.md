# MTL Trader - Project Notes

## What is this?
A SaaS trading journal web app for tracking and analyzing MT5 trades. Built with Next.js 16, React 19, TypeScript, Tailwind CSS 4, Supabase, Recharts, and PayPal.

## Completed Features
- **Landing page** - Hero, features, pricing, footer
- **Auth** - Login/signup with Supabase Auth
- **Dashboard** - Account balance, total P&L, win rate, profit factor, max drawdown, equity curve (Recharts), recent trades, quick actions
- **Trade History** - Search, filter (all/wins/losses), delete, edit trades
- **CSV Import** - Upload MT5 CSV trade history; also reads .xlsx files and Excel-saved-as-CSV (auto-detects the real format via magic bytes + delimiter sniffing, and maps columns from headers for both MT5 and broker layouts)
- **Analytics** - Equity curve, P&L by day chart, monthly P&L chart, performance by symbol table, stats (win rate, profit factor, expectancy, max drawdown)
- **Manual Trade Entry** - Form at `/dashboard/trades/new` with symbol, buy/sell, entry/exit, lot size, SL, TP, commission, swap, strategy, dates, notes, live P&L preview
- **Trade Editing** - Edit form at `/dashboard/trades/[id]/edit` - same fields as manual entry
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
- **Bank Details API** - `/api/bank-details` serves bank transfer details from `BANK_*` env vars so they are no longer hardcoded in the client

## Database Tables (Supabase)
- `users` - User profiles with subscription info, `agent_token`, `is_admin`
- `trades` - All trade data (symbol, type, entry/exit, lot, pnl, `ticket`, `import_id`, etc.)
- `deposits` - Deposit/withdrawal history (user_id, amount, type, description)
- `payment_requests` - Bank transfer payment requests awaiting admin approval
- `payment_events` - One row per processed payment event (`provider` + `provider_event_id` unique), for idempotent application and reconciliation

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
Vitest covers the import parser, P&L/point-value math, the plan/trial/quota rules, payment idempotency, summary rendering, and the auth/bank guards.

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

## Bank Transfer Setup (optional)
Set `BANK_NAME`, `BANK_ACCOUNT_NAME`, `BANK_ACCOUNT_NUMBER`, and `BANK_BRANCH` in `.env.local`; the payment page fetches them from `/api/bank-details`.

## Known Issues
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
  api/cron/notifications/route.ts # Daily/weekly/monthly summary emails (cron)
  api/plans/route.ts          # Plans API
src/lib/
  supabase.ts                 # Browser Supabase client
  server-auth.ts              # Bearer auth + admin client (service role)
  subscription.ts             # Single source of truth for plan/trial/quota rules
  import-parser.ts            # CSV/XLSX/SpreadsheetML trade parser (unit tested)
  rate-limit.ts               # In-memory per-user rate limiter
  payments.ts                 # PayPal helpers + idempotent applyPaidOrder
  email.ts                    # Resend wrapper (no-ops when unconfigured)
  summaries.ts                # Summary math + HTML email rendering
  auth-guards.ts              # Timing-safe bearer/cron secret checks
  bank.ts                     # Bank details from env
  utils.ts                    # formatCurrency, formatPercent, calculatePnL, getPointValue
  plans.ts                    # Pricing plan data
  theme.tsx                   # Dark/light mode context
src/types/
  index.ts                    # TypeScript types (Trade, User, etc.)
```
