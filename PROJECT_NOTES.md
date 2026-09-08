# MTL Trader - Project Notes

## What is this?
A SaaS trading journal web app for tracking and analyzing MT5 trades. Built with Next.js 16, React 19, TypeScript, Tailwind CSS 4, Supabase, Recharts, and Stripe.

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
- **PayPal Integration** - Checkout API at `/api/checkout` creates a PayPal order; `/api/paypal/capture` verifies the payer, the paid amount, and applies the plan to the user's account
- **Bank Transfer Payments** - Manual payment flow at `/dashboard/payment` submits a payment request; admins approve/reject via `/dashboard/admin` (protected by `is_admin` flag, not subscription tier)
- **Monthly Trade Quota** - Postgres trigger (`enforce_trade_quota`) blocks inserts beyond the plan's monthly limit; historical imports don't count against it
- **Import Reliability** - Trades are stamped with `import_id` so deleting an import removes exactly those trades; MT5 tickets are captured for sync/import dedupe

## Database Tables (Supabase)
- `users` - User profiles with subscription info, `agent_token`, `is_admin`
- `trades` - All trade data (symbol, type, entry/exit, lot, pnl, `ticket`, `import_id`, etc.)
- `deposits` - Deposit/withdrawal history (user_id, amount, type, description)
- `payment_requests` - Bank transfer payment requests awaiting admin approval

Schema + RLS + quota trigger live in `supabase/migrations/20260908_full_schema_rls_quota.sql` (idempotent).
Grant admin with: `UPDATE users SET is_admin = true WHERE email = 'you@example.com';`

## Running the App
```bash
cd D:\mtl-trader
npm run dev
```
Runs on http://localhost:3000 (or 3001 if port is taken)

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
4. The app currently uses the production PayPal endpoint (`api-m.paypal.com`); switch `PAYPAL_BASE` to `https://api-m.sandbox.paypal.com` for testing.

## Known Issues
- `@next/swc-win32-x64-msvc` not a valid Win32 app (uses WASM fallback, works fine)
- Supabase anon key in `.env.local` may be placeholder - verify it's real
- PayPal keys need to be configured for payments to work
- `.env.example` contains real-looking values - sanitize it before sharing
- There is no PayPal webhook yet; plan upgrades rely on the capture call from the success page (keep it, and don't close the tab before it completes)

## Pending / Nice to Have
- Trade notes/tags inline editing
- PayPal webhook for robust subscription state
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
  pricing/page.tsx            # Pricing page (Stripe checkout)
  api/checkout/route.ts       # Stripe checkout session API
  api/portal/route.ts         # Stripe customer portal API
  api/webhooks/stripe/route.ts # Stripe webhook handler
  api/plans/route.ts          # Plans API
src/lib/
  supabase.ts                 # Supabase client
  utils.ts                    # formatCurrency, formatPercent, calculatePnL
  plans.ts                    # Pricing plan data
  theme.tsx                   # Dark/light mode context
src/types/
  index.ts                    # TypeScript types (Trade, User, etc.)
```
