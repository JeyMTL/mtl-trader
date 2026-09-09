-- ============================================================
-- MTL Trader — complete schema, RLS policies, and quota trigger
-- Idempotent: safe to run on an existing database.
-- ============================================================

-- ---------- users ----------
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  full_name TEXT,
  subscription_tier TEXT DEFAULT 'free',
  subscription_status TEXT DEFAULT 'trial',
  trial_ends_at TIMESTAMP WITH TIME ZONE,
  trades_remaining INTEGER DEFAULT -1,
  max_trades INTEGER DEFAULT -1,
  stripe_customer_id TEXT,
  agent_token TEXT,
  is_admin BOOLEAN NOT NULL DEFAULT false,
  timezone TEXT DEFAULT 'UTC',
  currency TEXT DEFAULT 'USD',
  notifications_email BOOLEAN DEFAULT true,
  notifications_daily BOOLEAN DEFAULT true,
  notifications_weekly BOOLEAN DEFAULT false,
  notifications_marketing BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS full_name TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_tier TEXT DEFAULT 'free';
ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_status TEXT DEFAULT 'trial';
ALTER TABLE users ADD COLUMN IF NOT EXISTS trial_ends_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS trades_remaining INTEGER DEFAULT -1;
ALTER TABLE users ADD COLUMN IF NOT EXISTS max_trades INTEGER DEFAULT -1;
ALTER TABLE users ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS agent_token TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS timezone TEXT DEFAULT 'UTC';
ALTER TABLE users ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'USD';
ALTER TABLE users ADD COLUMN IF NOT EXISTS notifications_email BOOLEAN DEFAULT true;
ALTER TABLE users ADD COLUMN IF NOT EXISTS notifications_daily BOOLEAN DEFAULT true;
ALTER TABLE users ADD COLUMN IF NOT EXISTS notifications_weekly BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS notifications_marketing BOOLEAN DEFAULT false;

-- ---------- trades ----------
CREATE TABLE IF NOT EXISTS trades (
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
  ticket BIGINT,
  import_id TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE trades ADD COLUMN IF NOT EXISTS ticket BIGINT;
ALTER TABLE trades ADD COLUMN IF NOT EXISTS import_id TEXT;
ALTER TABLE trades ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE trades ADD COLUMN IF NOT EXISTS tags TEXT[];

-- ---------- deposits ----------
CREATE TABLE IF NOT EXISTS deposits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  amount NUMERIC NOT NULL,
  type TEXT NOT NULL DEFAULT 'deposit',
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ---------- payment_requests ----------
CREATE TABLE IF NOT EXISTS payment_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id),
  plan_id TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  reference TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  reviewed_by UUID,
  reviewed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ---------- indexes ----------
CREATE UNIQUE INDEX IF NOT EXISTS idx_trades_user_ticket ON trades (user_id, ticket) WHERE ticket IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_trades_user_created ON trades (user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_trades_user_import ON trades (user_id, import_id);

-- ============================================================
-- Row Level Security
-- ============================================================
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE trades ENABLE ROW LEVEL SECURITY;
ALTER TABLE deposits ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_requests ENABLE ROW LEVEL SECURITY;

-- users: own row only
DROP POLICY IF EXISTS "Users can view own profile" ON users;
CREATE POLICY "Users can view own profile" ON users
  FOR SELECT USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can insert own profile" ON users;
CREATE POLICY "Users can insert own profile" ON users
  FOR INSERT WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update own profile" ON users;
CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE USING (auth.uid() = id);

-- trades: own rows only
DROP POLICY IF EXISTS "Users can view own trades" ON trades;
CREATE POLICY "Users can view own trades" ON trades
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own trades" ON trades;
CREATE POLICY "Users can insert own trades" ON trades
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own trades" ON trades;
CREATE POLICY "Users can update own trades" ON trades
  FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own trades" ON trades;
CREATE POLICY "Users can delete own trades" ON trades
  FOR DELETE USING (auth.uid() = user_id);

-- deposits: own rows only
DROP POLICY IF EXISTS "Users can view own deposits" ON deposits;
CREATE POLICY "Users can view own deposits" ON deposits
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own deposits" ON deposits;
CREATE POLICY "Users can insert own deposits" ON deposits
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own deposits" ON deposits;
CREATE POLICY "Users can update own deposits" ON deposits
  FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own deposits" ON deposits;
CREATE POLICY "Users can delete own deposits" ON deposits
  FOR DELETE USING (auth.uid() = user_id);

-- payment_requests: users see/manage only their own.
-- Admins operate through server-side API routes (service role bypasses RLS).
DROP POLICY IF EXISTS "Users can view own payment requests" ON payment_requests;
CREATE POLICY "Users can view own payment requests" ON payment_requests
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own payment requests" ON payment_requests;
CREATE POLICY "Users can insert own payment requests" ON payment_requests
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ============================================================
-- Monthly trade quota enforcement
-- Hard server-side limit: current-month trades may not exceed max_trades.
-- Historical imports (older months) are NOT counted, so users can
-- import their full MT5 history on any plan. Pro (max_trades = -1) is unlimited.
-- ============================================================
CREATE OR REPLACE FUNCTION enforce_trade_quota()
RETURNS TRIGGER AS $$
DECLARE
  m_max INTEGER;
  m_count BIGINT;
  m_ts TIMESTAMP WITH TIME ZONE;
BEGIN
  SELECT COALESCE(max_trades, -1) INTO m_max FROM users WHERE id = NEW.user_id;
  IF EXISTS (
    SELECT 1 FROM users
    WHERE id = NEW.user_id
      AND subscription_status = 'trial'
      AND trial_ends_at IS NOT NULL
      AND trial_ends_at <= now()
  ) THEN
    RAISE EXCEPTION 'Free trial ended. Choose a paid plan to add trades.';
  END IF;
  IF m_max IS NULL OR m_max = -1 THEN
    RETURN NEW; -- unlimited (pro) or unknown user
  END IF;

  m_ts := COALESCE(NEW.close_time, NEW.open_time, NEW.created_at, now());

  -- Only enforce for trades in the current month
  IF date_trunc('month', m_ts) <> date_trunc('month', now()) THEN
    RETURN NEW;
  END IF;

  SELECT COUNT(*) INTO m_count
  FROM trades
  WHERE user_id = NEW.user_id
    AND date_trunc('month', COALESCE(close_time, open_time, created_at)) = date_trunc('month', now());

  IF m_count >= m_max THEN
    RAISE EXCEPTION 'Monthly trade limit reached (% trades). Upgrade your plan for more.', m_max;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_enforce_trade_quota ON trades;
CREATE TRIGGER trg_enforce_trade_quota
  BEFORE INSERT ON trades
  FOR EACH ROW EXECUTE FUNCTION enforce_trade_quota();

-- ---------- Optional: grant admin ----------
-- Admins are granted explicitly, NOT by subscription tier.
-- Run this for yourself (and any other admins):
--   UPDATE users SET is_admin = true WHERE email = 'you@example.com';