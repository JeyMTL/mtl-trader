# MTL Trader - Project Notes

## What is this?
A SaaS trading journal web app for tracking and analyzing MT5 trades. Built with Next.js 16, React 19, TypeScript, Tailwind CSS 4, Supabase, Recharts, and Stripe.

## Completed Features
- **Landing page** - Hero, features, pricing, footer
- **Auth** - Login/signup with Supabase Auth
- **Dashboard** - Account balance, total P&L, win rate, profit factor, max drawdown, equity curve (Recharts), recent trades, quick actions
- **Trade History** - Search, filter (all/wins/losses), delete, edit trades
- **CSV Import** - Upload MT5 CSV trade history
- **Analytics** - Equity curve, P&L by day chart, monthly P&L chart, performance by symbol table, stats (win rate, profit factor, expectancy, max drawdown)
- **Manual Trade Entry** - Form at `/dashboard/trades/new` with symbol, buy/sell, entry/exit, lot size, SL, TP, commission, swap, strategy, dates, notes, live P&L preview
- **Trade Editing** - Edit form at `/dashboard/trades/[id]/edit` - same fields as manual entry
- **Export Trades** - Download filtered trades as CSV from trade history page
- **Dark/Light Mode** - Toggle in Settings > Appearance, saved to localStorage. Light mode uses soft muted tones for eye comfort
- **Settings** - Profile, Balance (deposits/withdrawals), Appearance, Subscription, Notifications, Security
- **Deposit/Withdrawal System** - Add deposits, view history, total balance. `deposits` table in Supabase with RLS policies
- **Stripe Integration** - Checkout API at `/api/checkout`, pricing page and settings subscription buttons redirect to Stripe
- **Account Management** - Stripe Customer Portal at `/api/portal` for cancel/update payment method. Webhook at `/api/webhooks/stripe` auto-updates Supabase when subscription changes

## Database Tables (Supabase)
- `users` - User profiles with subscription info
- `trades` - All trade data (symbol, type, entry/exit, lot, pnl, etc.)
- `deposits` - Deposit/withdrawal history (user_id, amount, type, description)

## Running the App
```bash
cd D:\mtl-trader
npm run dev
```
Runs on http://localhost:3000 (or 3001 if port is taken)

## Stripe Setup
To enable payments:
1. Create a Stripe account at https://stripe.com
2. Get API keys from Stripe dashboard
3. Create products/prices for Basic ($9.99/mo) and Pro ($29.99/mo)
4. Add to `.env.local`:
```
STRIPE_SECRET_KEY=sk_test_xxx
STRIPE_PRICE_BASIC=price_xxx
STRIPE_PRICE_PRO=price_xxx
NEXT_PUBLIC_APP_URL=http://localhost:3000
```

## Known Issues
- `@next/swc-win32-x64-msvc` not a valid Win32 app (uses WASM fallback, works fine)
- Supabase anon key in `.env.local` may be placeholder - verify it's real
- Stripe keys need to be configured for payments to work

## Pending / Nice to Have
- Trade notes/tags editing after import (notes field exists but no inline editing)
- Real-time MT5 sync (Pro feature)

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
