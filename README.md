# MTL Trader - Professional Trading Journal

A SaaS trading journal web app for tracking and analyzing MT5 trades.

## Features

- **Trade Import** - Upload MT5/broker trade history as CSV, .xlsx, or Excel-saved-as-CSV (auto-detects xlsx, tab/semicolon separators, and both MT5 and broker column layouts)
- **Dashboard** - Overview of your trading performance
- **Analytics** - Win rate, profit factor, equity curve, strategy analysis
- **Trading Calendar** - Daily P&L heatmap
- **MT5 Auto Sync** - Python agent that syncs closed trades every 60s with proper entry/exit pairing
- **Subscription System** - 30-day unlimited free trial + paid tiers (PayPal + bank transfer)
- **PayPal Webhook** - Signature-verified webhook applies upgrades server-side, so a closed tab no longer loses a payment
- **Email Verification** - Users must verify a real email address before using the journal
- **Monthly Trade Quota** - Enforced server-side by a Postgres trigger
- **Payment Reconciliation** - A scheduled job replays captured PayPal payments through the same idempotent apply path, recovering payments whose webhook never arrived (it never downgrades an existing plan)
- **Rate Limiting** - Per-user limits on AI reviews and payment requests
- **Email Summaries** - Optional daily/weekly/monthly P&L summaries plus weekday journal reminders, sent through Resend, driven by the notification preferences in Settings and a scheduled cron
- **Dark Blue Theme** - Professional trading interface

## Tech Stack

- **Frontend:** Next.js 16, React 19, TypeScript, Tailwind CSS 4
- **Backend:** Next.js API Routes
- **Database:** Supabase (PostgreSQL)
- **Auth:** Supabase Auth
- **Payments:** PayPal Checkout (one-time capture) + bank transfer with unique references and admin approval
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

### 4. Run Development Server
```bash
npm run dev
```

Visit http://localhost:3000

### 5. Enable email confirmation

In Supabase, open `Authentication` → `Providers` → `Email` and enable **Confirm email**. Add the local and production URLs under the Auth URL configuration so verification links return to the app.

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

The crons in `vercel.json` (`/api/admin/reconcile` daily and `/api/cron/notifications`) require `CRON_SECRET` to be set in Vercel's environment variables and enable themselves automatically once deployed.

## Testing

```bash
npm test          # run once
npm run test:watch
```

Coverage includes the trade-import parser (CSV, SpreadsheetML XML, signed costs, MT5 section boundaries), P&L/point-value math, the plan/trial/quota rules, the timezone-aware notification windows/journal-reminder logic, and the notifications cron route itself (mocked Supabase + Resend).

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
| `PAYPAL_API_BASE` | Optional override of the PayPal REST base URL (defaults to production `https://api-m.paypal.com`; set to the sandbox URL for testing) |
| `CRON_SECRET` | Bearer secret Vercel Cron sends to `/api/admin/reconcile` and `/api/cron/notifications` |
| `RESEND_API_KEY` | Resend API key. When unset, email sending is a no-op (the app never fails because email is missing) |
| `EMAIL_FROM` | From address for summary emails, e.g. `MTL Trader <reports@yourdomain.com>` (must be a Resend-verified domain) |
| `BANK_NAME`, `BANK_ACCOUNT_NAME`, `BANK_ACCOUNT_NUMBER`, `BANK_BRANCH` | Bank transfer details shown on the payment page. When unset, the page shows a "contact support" message instead |
| `OPENAI_API_KEY` / `OPENAI_MODEL` | Optional, for the AI trading review |

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
│                             # payment-requests, plans, subscription, sync, admin, ai,
│                             # bank-details, cron/notifications
├── components/               # Reusable components
├── lib/                      # plans, subscription rules, import parser, auth helpers, utils,
│                             # payments, email, summaries, bank, auth-guards, rate-limit
└── types/                    # TypeScript types
```

## Database Migrations

Run every migration in `supabase/migrations/` in filename order. Later migrations add the 30-day trial, notification preferences, server-only payment request creation, and the `payment_events` table used for idempotent payment application and reconciliation. Apply them to existing databases as well.

`payment_events` is written only by server routes (service role) and stores one row per processed payment event, keyed by `(provider, provider_event_id)`. It is what makes the capture call, the webhook, and reconciliation safe to run in any order or repeatedly.

Bank-transfer subscriptions require admin approval. The unique payment reference is already stored with the user and plan for a future bank API/webhook integration.

Grant yourself admin access (used for the Admin panel / payment approvals):

```sql
UPDATE users SET is_admin = true WHERE email = 'you@example.com';
```
