# MTL Trader - Professional Trading Journal

A SaaS trading journal web app for tracking and analyzing MT5 trades.

## Features

- **Trade Import** - Upload MT5/broker trade history as CSV, .xlsx, or Excel-saved-as-CSV (auto-detects xlsx, tab/semicolon separators, and both MT5 and broker column layouts)
- **Dashboard** - Overview of your trading performance
- **Analytics** - Win rate, profit factor, equity curve, strategy analysis
- **Trading Calendar** - Daily P&L heatmap
- **MT5 Auto Sync** - Python agent that syncs closed trades every 60s with proper entry/exit pairing
- **Subscription System** - Free trial + paid tiers (PayPal + bank transfer)
- **Monthly Trade Quota** - Enforced server-side by a Postgres trigger
- **Dark Blue Theme** - Professional trading interface

## Tech Stack

- **Frontend:** Next.js 16, React 19, TypeScript, Tailwind CSS 4
- **Backend:** Next.js API Routes
- **Database:** Supabase (PostgreSQL)
- **Auth:** Supabase Auth
- **Payments:** PayPal Checkout (one-time capture) + manual bank transfer with admin approval
- **Charts:** Recharts
- **CSV Parsing:** PapaParse + SheetJS (xlsx)
- **Hosting:** Vercel (free tier)

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

### 3. Create Database Tables
Run this SQL in Supabase SQL Editor:

```sql
-- Users table
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  full_name TEXT,
  subscription_tier TEXT DEFAULT 'free',
  subscription_status TEXT DEFAULT 'trial',
  trial_ends_at TIMESTAMP WITH TIME ZONE,
  trades_remaining INTEGER DEFAULT 10,
  max_trades INTEGER DEFAULT 10,
  stripe_customer_id TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Trades table
CREATE TABLE trades (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  symbol TEXT NOT NULL,
  type TEXT NOT NULL,
  entry_price NUMERIC NOT NULL,
  exit_price NUMERIC NOT NULL,
  lot_size NUMERIC NOT NULL,
  stop_loss NUMERIC,
  take_profit NUMERIC,
  pnl NUMERIC NOT NULL,
  commission NUMERIC DEFAULT 0,
  swap NUMERIC DEFAULT 0,
  open_time TIMESTAMP WITH TIME ZONE,
  close_time TIMESTAMP WITH TIME ZONE,
  timeframe TEXT,
  strategy TEXT,
  notes TEXT,
  tags TEXT[],
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Deposits table
CREATE TABLE deposits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  amount NUMERIC NOT NULL,
  type TEXT NOT NULL DEFAULT 'deposit',
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 4. Run Development Server
```bash
npm run dev
```

Visit http://localhost:3000

### 5. Deploy to Vercel
```bash
npx vercel
```

## Pricing Tiers

| Plan | Price | Trades/Month |
|------|-------|--------------|
| Free Trial | $0 | 10 |
| Basic | $2.50 | 50 |
| Pro | $5.00 | Unlimited |

Trades are counted per calendar month (historical imports don't count against the limit).

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
│   │   ├── import/page.tsx   # CSV/xlsx import
│   │   ├── sync/page.tsx     # MT5 auto-sync setup
│   │   ├── analytics/page.tsx # Performance analytics
│   │   ├── calendar/page.tsx # Trading calendar
│   │   ├── admin/page.tsx    # Payment approval (is_admin only)
│   │   ├── payment/page.tsx  # Bank transfer flow
│   │   └── settings/page.tsx # User settings
│   ├── pricing/page.tsx      # Pricing page
│   └── api/                  # API routes (auth, checkout, paypal/capture, sync, admin)
├── components/               # Reusable components
├── lib/                      # Utilities, config, plans, server-auth
└── types/                    # TypeScript types
```

## Database Migrations

Run migrations in `supabase/migrations/` in order. The latest migration
(`20260908_full_schema_rls_quota.sql`) is idempotent and creates the full
schema, RLS policies, and the monthly quota trigger — safe to run on an
existing database.

Grant yourself admin access (used for the Admin panel / payment approvals):

```sql
UPDATE users SET is_admin = true WHERE email = 'you@example.com';
```
