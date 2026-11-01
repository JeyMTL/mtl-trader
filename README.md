# MTL Trader - Professional Trading Journal

A SaaS trading journal web app for tracking and analyzing MT5 trades.

## Features

- **Trade Import** - Upload MT5/broker trade history as CSV, .xlsx, or Excel-saved-as-CSV (auto-detects xlsx, tab/semicolon separators, and both MT5 and broker column layouts)
- **Dashboard** - A command-center desk: headline KPIs, equity/daily P&L chart, current-month heatmap, time edge, latest journal entries, recent fills and quick actions
- **Journal Media** - Attach chart screenshots (camera or gallery) and voice notes (recorded in the app or uploaded) to any trade. Files live in a private Supabase Storage bucket and are served through one-hour signed URLs
- **Trade Time Window** - Record the exact entry and exit date/time on every trade, with the time in market shown in the form, ticket and trade log
- **Time Edge Report** - The journal ranks entry hours and sessions in your own timezone, shows the most profitable and most losing windows, and draws a 24-hour P&L chart
- **Analytics** - Win rate, profit factor, equity curve, strategy analysis, and the time-of-day edge report
- **Trading Calendar** - Daily P&L heatmap
- **MT5 Auto Sync** - Python agent that syncs closed trades every 60s with proper entry/exit pairing; its token can be rotated or revoked from Settings
- **Subscription System** - 30-day unlimited free trial, then paid 30-day periods (PayPal + bank transfer). Each payment buys a period; access lapses unless it is renewed
- **PayPal Webhook** - Signature-verified webhook applies upgrades server-side, so a closed tab no longer loses a payment; refunds, reversals and disputes revoke access
- **Flutterwave Card Subscriptions** - Auto-renewing monthly card payments. The first charge subscribes the card to a payment plan, every renewal is applied by the signed webhook, and cancelling stops the card at the gateway while keeping the paid period
- **Email Verification** - Users must verify a real email address before using the journal
- **Monthly Trade Quota** - Enforced server-side by a Postgres trigger, which also rejects writes once a paid period has lapsed
- **Data Export & Deletion** - Self-service JSON export and a single-statement account deletion (cascading deletes, email confirmation required)
- **Server-Side Analytics** - Dashboard and analytics render on the server from Postgres aggregate RPCs, so the browser never downloads the whole journal
- **Row-Scoped Security** - Row Level Security plus a session-refreshing proxy that guards `/dashboard` before it renders
- **Payment Reconciliation** - A scheduled job replays captured PayPal payments through the same idempotent apply path, recovering payments whose webhook never arrived (it never downgrades an existing plan)
- **Rate Limiting** - Per-user limits on AI reviews, tag suggestions, sync agents, exports and payment requests, enforced with shared Postgres counters (not per-lambda memory)
- **Email Summaries** - Optional daily/weekly/monthly P&L summaries plus weekday journal reminders, sent through Resend, driven by the notification preferences in Settings and a scheduled cron
- **Native-Style Phone Shell** - In the web app at narrow viewports the dashboard becomes a bottom-tab layout: fixed app bar, 5-tab bar with a centre compose button, a More sheet, safe-area spacing, card lists instead of tables, and swipe between calendar months
- **Flutter Mobile App** - `mobile_flutter/` is a native Flutter client with a deliberately flat design: desk KPIs and charts, the journal, photo/voice-note capture, the time edge report and account settings, all against the same Supabase project
- **Dark Blue Theme** - Professional trading interface

## Tech Stack

- **Frontend:** Next.js 16, React 19, TypeScript, Tailwind CSS 4
- **Mobile:** Flutter 3.27+ (Dart 3.6+), Supabase Flutter, fl_chart
- **Backend:** Next.js API Routes
- **Database:** Supabase (PostgreSQL)
- **Auth:** Supabase Auth
- **Payments:** PayPal Checkout (one-time capture), Flutterwave card subscriptions (auto-renewing), and bank transfer with unique references and admin approval
- **Email:** Resend (transactional summaries; optional in production, no-ops when unconfigured)
- **Charts:** Recharts
- **CSV Parsing:** PapaParse + SheetJS (xlsx)
- **Tests:** Vitest
- **Hosting:** Vercel (free tier)

## Documentation

- [sales.html](sales.html) — buyer-facing product page for selling the app
- [docs/REPO_MAP.md](docs/REPO_MAP.md) — quick guide to the codebase and how the app fits together
- [docs/SELLER_BRIEF.md](docs/SELLER_BRIEF.md) — concise overview for a buyer or investor
- [docs/SELLER_PAGE.md](docs/SELLER_PAGE.md) — product brief for listings and outreach
- [mobile_flutter/README.md](mobile_flutter/README.md) — Flutter app bootstrap, permissions and build commands

## Setup Instructions

### 1. Install dependencies
```bash
npm install
```

### 2. Set up Supabase
1. Go to https://supabase.com and create a free project
2. Copy your project URL and anon key
3. Create a `.env.local` file (copy from `.env.example`)
4. Fill in your Supabase credentials

### 3. Create database tables

Run every migration in `supabase/migrations/` in filename order (they are idempotent). The schema, Row Level Security policies, and the monthly-quota trigger live there and are the authoritative source — do not hand-create tables.

`20261026_billing_lifecycle_and_scale.sql` adds the billing period columns, refund revocation, cascading deletes, the aggregate read functions (`trade_summary`, `equity_curve`, `symbol_stats`, `trade_breakdowns`, `daily_pnl`, `trade_page`, `day_trades`, `deposits_total`), the shared rate-limit table and function, and the notification send ledger. The server-rendered dashboard and analytics expect it: without it they log an error and render empty states.

`20261027_trade_tags.sql` adds tag search to `trade_page` and the `tag_stats` function behind the analytics tag table. Apply it after `20261026`.

`20261028_journal_media_and_time_stats.sql` adds the `trade_attachments` table, the private `journal-media` storage bucket and its policies, the `time_stats()` and `journal_feed()` RPCs, and attachment counts on `trade_page`. Apply it after `20261027`. The dashboard and analytics read `time_stats` and `journal_feed`; without them those panels log an error and render empty states, and photo/voice-note uploads fail.

`20261104_trade_page_session_filter.sql` adds the optional `p_session` argument to `trade_page` so the trade history can be narrowed to one UTC trading session (Asian, London, New York, Sydney). It drops the old four-argument signature first, because two overloads whose arguments all have defaults make PostgREST answer `PGRST203` instead of choosing one. Callers that pass no session keep working. Without it, the session chips render and then report that the database needs the update rather than showing an unfiltered list.

`20261105_session_stats.sql` adds `session_stats()`, the per-window aggregate behind the journal's session strip and the analytics Sessions table. It uses the same four windows as the filter, so a trade in the London/New York overlap is counted in both — filtering by either session does the same. `node --env-file=.env.local scripts/check-session-filter.mjs --token=<user jwt>` proves the buckets against your own rows, which a schema check cannot.

After deploying it, existing signed-in browsers must sign in once more. Sessions moved from localStorage to cookies so that server components and the proxy can authenticate them; that is a one-time cost and the old localStorage session is simply ignored.

### 4. Run Development Server
```bash
npm run dev
```

Visit http://localhost:3000

### 5. Enable email confirmation

In Supabase, open `Authentication` → `Providers` → `Email` and enable **Confirm email**. Add the local and production URLs under the Auth URL configuration so verification links return to the app.

Password recovery posts to `/auth/forgot`, and the emailed link lands on `/auth/reset`. Add both `http://localhost:3000/auth/reset` and `https://your-domain/auth/reset` to the Supabase **Redirect URLs** allowlist, or the recovery link will be rejected.

### 6. Configure email summaries (optional)
1. Create a free account at https://resend.com and verify the domain you want to send from
2. Set `RESEND_API_KEY` and `EMAIL_FROM` (e.g. `MTL Trader <reports@yourdomain.com>`)

With neither set the app still runs: summary sends and the notifications cron simply no-op. For Supabase Auth emails, point Supabase's SMTP settings at Resend so verification mail is not rate-limited or spam-filtered.

### 7. Configure bank transfer details (optional)
Set `BANK_NAME`, `BANK_ACCOUNT_NAME`, `BANK_ACCOUNT_NUMBER`, and `BANK_BRANCH` so the payment page shows real details. The values are served by `/api/bank-details` and never hardcoded in the client.

### 8. Deploy to Vercel
```bash
npx vercel
```

The crons in `vercel.json` (`/api/admin/reconcile` daily and `/api/cron/notifications`) require `CRON_SECRET` to be set in Vercel's environment variables and enable themselves automatically once deployed. The daily reconcile run does three things: replays captured PayPal payments, expires subscriptions whose 30-day period has ended, and sweeps stale rate-limit rows. Without it, a one-time payment would keep behaving like a lifetime grant.

## Testing

```bash
npm test          # run once
npm run test:watch
```

Coverage includes the trade-import parser (CSV, SpreadsheetML XML, signed costs, MT5 section boundaries), P&L/point-value math, the plan/trial/quota rules, the billing-period lifecycle (renewal stacking, expiry, cancellation, revocation), the timezone-aware notification windows/journal-reminder logic, the notifications cron route itself (batched users, send ledger, per-user failure isolation), the payment webhook (captures, refunds with and without order metadata, replays), account deletion, and the AI review pipeline (edge stats, note retrieval, structured-output validation, caching, providers, outcomes, auto-tagging).

CI (`.github/workflows/ci.yml`) runs lint, typecheck, tests and a production build on every push and pull request, so the suite is enforced rather than optional.

See `docs/AI.md` for the AI review architecture, endpoints, and provider setup.

To check notifications against real credentials (config audit, a Resend test send, or invoking the deployed cron):
```bash
node --env-file=.env.local scripts/check-notifications.mjs
node --env-file=.env.local scripts/check-notifications.mjs --send you@example.com
node --env-file=.env.local scripts/check-notifications.mjs --run
```

To audit payments and verify them live (PayPal credential check, or invoking the reconcile cron):
```bash
node --env-file=.env.local scripts/check-payments.mjs
node --env-file=.env.local scripts/check-payments.mjs --verify
node --env-file=.env.local scripts/check-payments.mjs --reconcile
```

## Pricing Tiers

| Plan | Price | Trades/Month |
|------|-------|--------------|
| Free Trial | $0 | Unlimited for 30 days |
| Basic | $2.50 | 50 |
| Pro | $5.00 | Unlimited |

Trades are counted per calendar month and enforcement lives in the database trigger, not just the UI. Historical imports (older months) do not count against the limit.

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase anon/publishable key |
| `SUPABASE_SERVICE_ROLE_KEY` | Server-only key used by API routes |
| `NEXT_PUBLIC_APP_URL` | Public base URL (PayPal return/cancel URLs) |
| `PAYPAL_CLIENT_ID` / `PAYPAL_CLIENT_SECRET` | PayPal REST app credentials |
| `PAYPAL_WEBHOOK_ID` | Webhook ID for signature verification (required for the webhook and reconciliation) |
| `FLUTTERWAVE_SECRET_KEY` | Flutterwave secret key; enables the card subscription checkout |
| `FLUTTERWAVE_SECRET_HASH` | Webhook secret hash from the Flutterwave dashboard (verifies `/api/webhooks/flutterwave`) |
| `FLUTTERWAVE_CURRENCY` | Currency for payment plans and charges (default `USD`) |
| `ERROR_REPORT_URL` | Optional JSON webhook that receives unhandled request errors; logs are structured either way |
| `PAYPAL_API_BASE` | Optional override of the PayPal REST base URL (defaults to production `https://api-m.paypal.com`; set to the sandbox URL for testing) |
| `CRON_SECRET` | Bearer secret Vercel Cron sends to `/api/admin/reconcile` and `/api/cron/notifications` |
| `RESEND_API_KEY` | Resend API key. When unset, email sending is a no-op (the app never fails because email is missing) |
| `EMAIL_FROM` | From address for summary emails, e.g. `MTL Trader <reports@yourdomain.com>` (must be a Resend-verified domain) |
| `BANK_NAME`, `BANK_ACCOUNT_NAME`, `BANK_ACCOUNT_NUMBER`, `BANK_BRANCH` | Bank transfer details shown on the payment page. When unset, the page shows a "contact support" message instead |
| `OPENAI_API_KEY` / `OPENAI_MODEL` | Optional; enables the AI journal review on OpenAI |
| `ANTHROPIC_API_KEY` / `ANTHROPIC_MODEL` | Optional alternative AI provider |
| `AI_PROVIDER`, `AI_BASE_URL`, `AI_API_KEY`, `AI_MODEL`, `AI_VISION_MODEL` | Optional AI overrides / OpenAI-compatible gateway |

The app uses the production PayPal endpoint (`api-m.paypal.com`); set `PAYPAL_API_BASE` to `https://api-m.sandbox.paypal.com` for testing.

## Project Structure

```
src/
├── app/
│   ├── page.tsx              # Landing page
│   ├── layout.tsx            # Root layout
│   ├── auth/
│   │   ├── login/page.tsx    # Login page
│   │   └── signup/page.tsx   # Signup page
│   ├── dashboard/
│   │   ├── page.tsx          # Dashboard overview
│   │   ├── trades/           # Trade history, add/edit
│   │   ├── import/page.tsx   # CSV/xlsx/xml import
│   │   ├── sync/page.tsx     # MT5 auto-sync setup
│   │   ├── analytics/page.tsx # Performance analytics
│   │   ├── calendar/page.tsx # Trading calendar
│   │   ├── admin/page.tsx    # Payment approval (is_admin only)
│   │   ├── payment/page.tsx  # Bank transfer flow
│   │   └── settings/page.tsx # User settings
│   ├── pricing/page.tsx      # Pricing page (PayPal + bank transfer)
│   └── api/                  # auth, checkout, paypal/capture, webhooks/paypal,
│                             # payment-requests, plans, subscription, sync (rotate),
│                             # admin (payments/users/reconcile), ai, bank-details,
│                             # account (delete/export), trial, cron/notifications
├── components/               # Reusable UI, including the server-rendered dashboard views
├── instrumentation.ts        # Request error reporting (structured logs + optional webhook)
├── proxy.ts                  # Next 16 proxy: session refresh + /dashboard auth guard
├── lib/                      # plans, subscription rules, import parser, auth helpers, utils,
│                             # payments, email, summaries, bank, auth-guards, rate-limit, log,
│                             # supabase (browser, cookie sessions), supabase-server (RSC)
└── types/                    # TypeScript types

mobile_flutter/               # Native Flutter app (flat design) — see mobile_flutter/README.md
mobile/                       # Legacy Capacitor wrapper (the web shell)
```

## Database Migrations

Run every migration in `supabase/migrations/` in filename order. Later migrations add the 30-day trial, notification preferences, server-only payment request creation, and the `payment_events` table used for idempotent payment application and reconciliation. Apply them to existing databases as well.

`payment_events` is written only by server routes (service role) and stores one row per processed payment event, keyed by `(provider, provider_event_id)`. It is what makes the capture call, the webhook, and reconciliation safe to run in any order or repeatedly.

Bank-transfer subscriptions require admin approval. The unique payment reference is already stored with the user and plan for a future bank API/webhook integration.

### Billing lifecycle

A paid order buys **one 30-day period**, not permanent access:

- `apply_paid_order` records the payment event, then sets `current_period_end` to *the later of now or the existing period end, plus 30 days*. Paying early stacks, so a renewal never costs remaining days.
- `revoke_paid_order` handles refunds, reversals and disputes: access is removed immediately and the event is recorded so a replayed refund is a no-op.
- `expire_lapsed_subscriptions` runs in the daily reconcile cron and downgrades accounts whose period has ended. The quota trigger also rejects writes the moment the period lapses, covering the gap before the job runs.
- Cancelling (`/api/subscription/cancel`) sets `cancel_at_period_end`; the user keeps the time they paid for and only the renewal stops.

This model uses one-time PayPal captures. Moving to recurring billing means switching to the PayPal Subscriptions API (or Stripe) and driving `current_period_end` from its webhooks; the rest of the app already reads that column, so the UI, quota and expiry keep working unchanged.

Grant yourself admin access (used for the Admin panel / payment approvals):

```sql
UPDATE users SET is_admin = true WHERE email = 'you@example.com';
```
