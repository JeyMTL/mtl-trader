# MTL Trader - Professional Trading Journal

A SaaS trading journal web app for tracking and analyzing MT5 trades.

## Features

- **Trade Import** - Upload MT5 CSV trade history
- **Dashboard** - Overview of your trading performance
- **Analytics** - Win rate, profit factor, equity curve, strategy analysis
- **Subscription System** - Free trial + paid tiers
- **Dark Blue Theme** - Professional trading interface

## Tech Stack

- **Frontend:** Next.js 16, React 19, TypeScript, Tailwind CSS 4
- **Backend:** Next.js API Routes
- **Database:** Supabase (PostgreSQL)
- **Auth:** Supabase Auth
- **Payments:** Stripe
- **Charts:** Recharts
- **CSV Parsing:** PapaParse
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
| Basic | $9.99 | 50 |
| Pro | $29.99 | Unlimited |

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
│   │   ├── trades/page.tsx   # Trade history
│   │   ├── import/page.tsx   # CSV import
│   │   ├── analytics/page.tsx # Performance analytics
│   │   └── settings/page.tsx # User settings
│   ├── pricing/page.tsx      # Pricing page
│   └── api/                  # API routes
├── components/               # Reusable components
├── lib/                      # Utilities, config, plans
└── types/                    # TypeScript types
```
