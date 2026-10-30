-- ============================================================
-- MTL Trader — billing lifecycle, aggregate reads, shared limits
-- Idempotent: safe to run on an existing database.
--
-- What this migration fixes:
--   1. A paid order used to grant access forever. Paid plans now carry a real
--      30-day period (`current_period_end`) and lapse without a renewal.
--   2. Refunds/reversals had no effect on access. `revoke_paid_order` records the
--      event idempotently and downgrades the account.
--   3. Account deletion left orphaned rows behind. User-owned tables now cascade.
--   4. Every page pulled the whole journal into the browser. Aggregates and
--      pagination now happen in Postgres (`trade_summary`, `equity_curve`,
--      `symbol_stats`, `daily_pnl`, `trade_page`).
--   5. The rate limiter was per-lambda. `check_rate_limit` is shared state.
--   6. The notification cron could double-send. `notification_sends` is a ledger.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Billing period columns
-- ------------------------------------------------------------
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS current_period_start TIMESTAMPTZ;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS current_period_end TIMESTAMPTZ;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS cancel_at_period_end BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS last_payment_at TIMESTAMPTZ;

-- Existing paid accounts were sold as "monthly" but were actually unlimited.
-- Give them one full period from now rather than cutting access off on deploy.
UPDATE public.users
SET current_period_start = COALESCE(current_period_start, now()),
    current_period_end = GREATEST(now(), COALESCE(current_period_end, now())) + INTERVAL '30 days',
    last_payment_at = COALESCE(last_payment_at, now())
WHERE subscription_status = 'active'
  AND subscription_tier IN ('basic', 'pro')
  AND current_period_end IS NULL;

-- ------------------------------------------------------------
-- 2. Payment application that owns the period
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_paid_order(
  p_user_id UUID,
  p_provider TEXT,
  p_provider_event_id TEXT,
  p_plan_id TEXT,
  p_amount NUMERIC
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  account public.users%ROWTYPE;
  expected_amount NUMERIC;
  new_max_trades INTEGER;
  event_row_id UUID;
  current_rank INTEGER;
  requested_rank INTEGER;
  event_status TEXT;
  period_still_active BOOLEAN;
  period_start TIMESTAMPTZ;
BEGIN
  IF p_provider IS NULL OR p_provider NOT IN ('paypal', 'bank')
    OR p_provider_event_id IS NULL OR btrim(p_provider_event_id) = '' THEN
    RETURN 'invalid_plan';
  END IF;

  expected_amount := CASE p_plan_id
    WHEN 'basic' THEN 2.50
    WHEN 'pro' THEN 5.00
    ELSE NULL
  END;

  IF expected_amount IS NULL THEN
    RETURN 'invalid_plan';
  END IF;
  IF p_amount IS DISTINCT FROM expected_amount THEN
    RETURN 'amount_mismatch';
  END IF;

  SELECT * INTO account
  FROM public.users
  WHERE id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN 'unknown_user';
  END IF;

  period_still_active := account.subscription_status = 'active'
    AND account.current_period_end IS NOT NULL
    AND account.current_period_end > now();

  current_rank := CASE account.subscription_tier
    WHEN 'pro' THEN 2
    WHEN 'basic' THEN 1
    ELSE 0
  END;
  requested_rank := CASE p_plan_id WHEN 'pro' THEN 2 ELSE 1 END;
  new_max_trades := CASE p_plan_id WHEN 'pro' THEN -1 ELSE 50 END;
  event_status := CASE
    WHEN period_still_active AND current_rank > requested_rank
      THEN 'skipped_downgrade'
    ELSE 'applied'
  END;

  INSERT INTO public.payment_events (
    user_id, provider, provider_event_id, plan_id, amount, status
  )
  VALUES (
    p_user_id, p_provider, p_provider_event_id, p_plan_id, p_amount, event_status
  )
  ON CONFLICT (provider, provider_event_id) DO NOTHING
  RETURNING id INTO event_row_id;

  IF event_row_id IS NULL THEN
    RETURN 'duplicate';
  END IF;

  IF event_status = 'skipped_downgrade' THEN
    RETURN 'would_downgrade';
  END IF;

  -- Renewals stack onto unexpired time, so a user who pays early never loses days.
  period_start := CASE WHEN period_still_active THEN account.current_period_start ELSE now() END;

  UPDATE public.users
  SET subscription_tier = p_plan_id,
      subscription_status = 'active',
      max_trades = new_max_trades,
      trades_remaining = new_max_trades,
      current_period_start = period_start,
      current_period_end = GREATEST(now(), COALESCE(account.current_period_end, now())) + INTERVAL '30 days',
      cancel_at_period_end = false,
      last_payment_at = now()
  WHERE id = p_user_id;

  RETURN 'applied';
END;
$$;

REVOKE ALL ON FUNCTION public.apply_paid_order(UUID, TEXT, TEXT, TEXT, NUMERIC)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_paid_order(UUID, TEXT, TEXT, TEXT, NUMERIC)
  TO service_role;

-- Refunds, reversals and disputes revoke access immediately. The provider event
-- id makes a replayed refund a no-op, exactly like a replayed capture.
CREATE OR REPLACE FUNCTION public.revoke_paid_order(
  p_user_id UUID,
  p_provider TEXT,
  p_provider_event_id TEXT,
  p_plan_id TEXT,
  p_amount NUMERIC
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  event_row_id UUID;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN 'unknown_user';
  END IF;
  IF p_provider IS NULL OR p_provider NOT IN ('paypal', 'bank')
    OR p_provider_event_id IS NULL OR btrim(p_provider_event_id) = '' THEN
    RETURN 'invalid_plan';
  END IF;

  -- Check first: the event row references users(id), so a refund for an account
  -- that has already been deleted must be acknowledged, not retried forever.
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RETURN 'unknown_user';
  END IF;

  INSERT INTO public.payment_events (
    user_id, provider, provider_event_id, plan_id, amount, status
  )
  VALUES (
    p_user_id, p_provider, p_provider_event_id,
    COALESCE(p_plan_id, 'unknown'), COALESCE(p_amount, 0), 'revoked'
  )
  ON CONFLICT (provider, provider_event_id) DO NOTHING
  RETURNING id INTO event_row_id;

  IF event_row_id IS NULL THEN
    RETURN 'duplicate';
  END IF;

  UPDATE public.users
  SET subscription_tier = 'free',
      subscription_status = 'cancelled',
      max_trades = 0,
      trades_remaining = 0,
      current_period_end = now(),
      cancel_at_period_end = false
  WHERE id = p_user_id;

  RETURN 'revoked';
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_paid_order(UUID, TEXT, TEXT, TEXT, NUMERIC)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_paid_order(UUID, TEXT, TEXT, TEXT, NUMERIC)
  TO service_role;

-- Ends access for periods that have lapsed. Run daily by the reconcile cron so
-- a one-time payment cannot behave like a lifetime subscription.
CREATE OR REPLACE FUNCTION public.expire_lapsed_subscriptions()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  expired_count INTEGER;
BEGIN
  UPDATE public.users
  SET subscription_tier = 'free',
      subscription_status = 'expired',
      max_trades = 0,
      trades_remaining = 0,
      cancel_at_period_end = false
  WHERE subscription_status = 'active'
    AND current_period_end IS NOT NULL
    AND current_period_end <= now();

  GET DIAGNOSTICS expired_count = ROW_COUNT;
  RETURN expired_count;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_lapsed_subscriptions()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_lapsed_subscriptions() TO service_role;

-- ------------------------------------------------------------
-- 3. Cascade deletes so account removal is one atomic statement
-- ------------------------------------------------------------
DO $$
DECLARE
  fk RECORD;
BEGIN
  FOR fk IN
    SELECT c.conname, t.relname
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    WHERE c.contype = 'f'
      AND c.confrelid = 'public.users'::regclass
      AND t.relnamespace = 'public'::regnamespace
  LOOP
    EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', fk.relname, fk.conname);
    EXECUTE format(
      'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE',
      fk.relname, fk.conname
    );
  END LOOP;
END
$$;

CREATE OR REPLACE FUNCTION public.delete_account_data(p_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RETURN 'invalid';
  END IF;

  DELETE FROM public.users WHERE id = p_user_id;

  IF FOUND THEN
    RETURN 'deleted';
  END IF;
  RETURN 'not_found';
END;
$$;

REVOKE ALL ON FUNCTION public.delete_account_data(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_account_data(UUID) TO service_role;

-- ------------------------------------------------------------
-- 4. Quota trigger that honours the paid period
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_trade_quota()
RETURNS TRIGGER AS $$
DECLARE
  m_max INTEGER;
  m_count BIGINT;
  m_ts TIMESTAMP WITH TIME ZONE;
  m_status TEXT;
  m_period_end TIMESTAMP WITH TIME ZONE;
  m_trial_end TIMESTAMP WITH TIME ZONE;
BEGIN
  SELECT COALESCE(max_trades, -1), subscription_status, current_period_end, trial_ends_at
  INTO m_max, m_status, m_period_end, m_trial_end
  FROM users WHERE id = NEW.user_id;

  IF m_status = 'trial' AND m_trial_end IS NOT NULL AND m_trial_end <= now() THEN
    RAISE EXCEPTION 'Free trial ended. Choose a paid plan to add trades.';
  END IF;

  -- The daily expiry job downgrades lapsed accounts; this closes the window
  -- between the period ending and the job running.
  IF m_status = 'active' AND m_period_end IS NOT NULL AND m_period_end <= now() THEN
    RAISE EXCEPTION 'Your subscription has expired. Renew to add trades.';
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
    RAISE EXCEPTION 'Monthly trade limit reached (% trades). Upgrade your plan for unlimited trades.', m_max;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_enforce_trade_quota ON trades;
CREATE TRIGGER trg_enforce_trade_quota
  BEFORE INSERT ON trades
  FOR EACH ROW EXECUTE FUNCTION enforce_trade_quota();

-- ------------------------------------------------------------
-- 5. Indexes for the reads the app actually performs
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_trades_user_close ON trades (user_id, close_time DESC);
CREATE INDEX IF NOT EXISTS idx_trades_user_open ON trades (user_id, open_time DESC);
CREATE INDEX IF NOT EXISTS idx_trades_user_pnl ON trades (user_id, pnl);
CREATE INDEX IF NOT EXISTS idx_users_period_end ON users (current_period_end) WHERE subscription_status = 'active';

-- ------------------------------------------------------------
-- 6. Aggregate read RPCs (SECURITY INVOKER — RLS still applies)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trade_summary()
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  WITH scope AS (
    SELECT pnl, COALESCE(close_time, open_time, created_at) AS traded_at
    FROM public.trades
    WHERE user_id = auth.uid()
  ), month AS (
    SELECT pnl, traded_at::date AS day
    FROM scope
    WHERE date_trunc('month', traded_at) = date_trunc('month', now())
  ), month_days AS (
    SELECT day, SUM(pnl) AS pnl FROM month GROUP BY day
  ), agg AS (
    SELECT
      (SELECT COUNT(*)::INT FROM scope) AS total_trades,
      (SELECT COUNT(*)::INT FROM scope WHERE pnl > 0) AS wins,
      (SELECT COUNT(*)::INT FROM scope WHERE pnl < 0) AS losses,
      (SELECT COUNT(*)::INT FROM month) AS month_trades,
      (SELECT COUNT(*)::INT FROM month WHERE pnl > 0) AS month_wins,
      (SELECT COALESCE(SUM(pnl), 0)::NUMERIC FROM month) AS month_pnl,
      (SELECT COUNT(*)::INT FROM month_days WHERE pnl > 0) AS month_winning_days,
      (SELECT COALESCE(SUM(pnl), 0)::NUMERIC FROM scope) AS total_pnl,
      (SELECT COALESCE(SUM(pnl), 0)::NUMERIC FROM scope WHERE pnl > 0) AS gross_profit,
      (SELECT COALESCE(-SUM(pnl), 0)::NUMERIC FROM scope WHERE pnl < 0) AS gross_loss,
      (SELECT COALESCE(MAX(pnl), 0)::NUMERIC FROM scope) AS best_trade,
      (SELECT COALESCE(MIN(pnl), 0)::NUMERIC FROM scope) AS worst_trade,
      (SELECT EXISTS (SELECT 1 FROM scope WHERE traded_at::date = now()::date)) AS has_trade_today
  )
  SELECT to_jsonb(agg) FROM agg;
$$;

CREATE OR REPLACE FUNCTION public.deposits_total()
RETURNS NUMERIC
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(SUM(amount), 0)::NUMERIC
  FROM public.deposits
  WHERE user_id = auth.uid();
$$;

-- Weekday and month breakdowns for the analytics charts.
CREATE OR REPLACE FUNCTION public.trade_breakdowns()
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  WITH scoped AS (
    SELECT pnl, COALESCE(close_time, open_time, created_at) AS traded_at
    FROM public.trades
    WHERE user_id = auth.uid()
  ), weekdays AS (
    SELECT EXTRACT(DOW FROM traded_at)::INT AS dow,
           COUNT(*)::INT AS trades,
           COUNT(*) FILTER (WHERE pnl > 0)::INT AS wins,
           COUNT(*) FILTER (WHERE pnl <= 0)::INT AS losses,
           COALESCE(SUM(pnl), 0)::NUMERIC AS pnl
    FROM scoped
    GROUP BY 1
  ), months AS (
    SELECT to_char(date_trunc('month', traded_at), 'YYYY-MM') AS month,
           COALESCE(SUM(pnl), 0)::NUMERIC AS pnl
    FROM scoped
    GROUP BY 1
  )
  SELECT jsonb_build_object(
    'weekdays', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object('dow', dow, 'wins', wins, 'losses', losses, 'pnl', pnl) ORDER BY dow) FROM weekdays),
      '[]'::jsonb
    ),
    'months', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object('month', month, 'pnl', pnl) ORDER BY month) FROM months),
      '[]'::jsonb
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.equity_curve()
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  WITH daily AS (
    SELECT date_trunc('day', COALESCE(close_time, open_time, created_at))::date AS day,
           SUM(pnl)::NUMERIC AS pnl,
           COUNT(*)::INT AS trades
    FROM public.trades
    WHERE user_id = auth.uid()
    GROUP BY 1
  ), running AS (
    SELECT day, pnl, trades, SUM(pnl) OVER (ORDER BY day)::NUMERIC AS cumulative
    FROM daily
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(running) ORDER BY day), '[]'::jsonb) FROM running;
$$;

CREATE OR REPLACE FUNCTION public.symbol_stats(p_limit INTEGER DEFAULT 10)
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.pnl DESC), '[]'::jsonb)
  FROM (
    SELECT symbol,
           COUNT(*)::INT AS trades,
           COUNT(*) FILTER (WHERE pnl > 0)::INT AS wins,
           COALESCE(SUM(pnl), 0)::NUMERIC AS pnl
    FROM public.trades
    WHERE user_id = auth.uid()
    GROUP BY symbol
    ORDER BY SUM(pnl) DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 10), 1), 100)
  ) s;
$$;

CREATE OR REPLACE FUNCTION public.daily_pnl(p_from DATE, p_to DATE)
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  WITH daily AS (
    SELECT COALESCE(close_time, open_time, created_at)::date AS day,
           SUM(pnl)::NUMERIC AS pnl,
           COUNT(*)::INT AS trades
    FROM public.trades
    WHERE user_id = auth.uid()
      AND COALESCE(close_time, open_time, created_at) >= p_from
      AND COALESCE(close_time, open_time, created_at) < (p_to + INTERVAL '1 day')
    GROUP BY 1
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(daily) ORDER BY day), '[]'::jsonb) FROM daily;
$$;

/** Month the calendar should open on (the latest trade), without loading history. */
CREATE OR REPLACE FUNCTION public.latest_trade_day()
RETURNS DATE
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT MAX(COALESCE(close_time, open_time, created_at))::date
  FROM public.trades
  WHERE user_id = auth.uid();
$$;

/** The trades of one calendar day, for the day detail table. */
CREATE OR REPLACE FUNCTION public.day_trades(p_day DATE)
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  WITH scoped AS (
    SELECT id, symbol, type, entry_price, exit_price, lot_size, pnl, commission, swap,
           strategy, close_time, open_time, created_at,
           COALESCE(close_time, open_time, created_at) AS traded_at
    FROM public.trades
    WHERE user_id = auth.uid()
      AND COALESCE(close_time, open_time, created_at)::date = p_day
    ORDER BY traded_at
    LIMIT 500
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(scoped) - 'traded_at' ORDER BY traded_at), '[]'::jsonb) FROM scoped;
$$;

-- Server-side pagination for the trade list. `total` and `total_pnl` describe the
-- whole filtered set, so the UI never needs the full history to show a footer.
CREATE OR REPLACE FUNCTION public.trade_page(
  p_limit INTEGER DEFAULT 25,
  p_offset INTEGER DEFAULT 0,
  p_search TEXT DEFAULT NULL,
  p_filter TEXT DEFAULT 'all'
)
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  WITH filtered AS (
    SELECT *
    FROM public.trades
    WHERE user_id = auth.uid()
      AND (
        p_search IS NULL OR btrim(p_search) = ''
        OR symbol ILIKE '%' || btrim(p_search) || '%'
        OR COALESCE(strategy, '') ILIKE '%' || btrim(p_search) || '%'
      )
      AND (p_filter IS DISTINCT FROM 'wins' OR pnl > 0)
      AND (p_filter IS DISTINCT FROM 'losses' OR pnl < 0)
  ), page AS (
    SELECT f.*, COALESCE(f.close_time, f.open_time, f.created_at) AS sort_key
    FROM filtered f
    ORDER BY COALESCE(f.close_time, f.open_time, f.created_at) DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 25), 1), 200)
    OFFSET GREATEST(COALESCE(p_offset, 0), 0)
  )
  SELECT jsonb_build_object(
    'total', (SELECT COUNT(*) FROM filtered),
    'total_pnl', COALESCE((SELECT SUM(pnl) FROM filtered), 0),
    'trades', COALESCE((SELECT jsonb_agg(to_jsonb(page) - 'sort_key' ORDER BY page.sort_key DESC) FROM page), '[]'::jsonb)
  );
$$;

REVOKE ALL ON FUNCTION public.trade_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.trade_summary() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.equity_curve() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.equity_curve() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.deposits_total() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.deposits_total() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.trade_breakdowns() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.trade_breakdowns() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.symbol_stats(INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.symbol_stats(INTEGER) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.daily_pnl(DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.daily_pnl(DATE, DATE) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.trade_page(INTEGER, INTEGER, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.trade_page(INTEGER, INTEGER, TEXT, TEXT) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.latest_trade_day() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.latest_trade_day() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.day_trades(DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.day_trades(DATE) TO authenticated, service_role;

-- ------------------------------------------------------------
-- 7. Shared rate limiting (replaces per-lambda in-memory buckets)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.rate_limits (
  key TEXT PRIMARY KEY,
  count INTEGER NOT NULL,
  reset_at TIMESTAMPTZ NOT NULL
);

ALTER TABLE public.rate_limits ENABLE ROW LEVEL SECURITY;
-- No policies: only the service role (server routes) may touch this table.

CREATE OR REPLACE FUNCTION public.check_rate_limit(
  p_key TEXT,
  p_limit INTEGER,
  p_window_ms INTEGER
)
RETURNS TABLE (allowed BOOLEAN, remaining INTEGER, retry_after_ms INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  bucket public.rate_limits%ROWTYPE;
BEGIN
  IF p_key IS NULL OR btrim(p_key) = '' OR p_limit IS NULL OR p_limit <= 0
     OR p_window_ms IS NULL OR p_window_ms <= 0 THEN
    RAISE EXCEPTION 'check_rate_limit requires a key, a positive limit and a positive window';
  END IF;

  INSERT INTO public.rate_limits AS r (key, count, reset_at)
  VALUES (p_key, 1, now() + make_interval(secs => p_window_ms / 1000.0))
  ON CONFLICT (key) DO UPDATE
    SET count = CASE
          WHEN r.reset_at <= now() THEN 1
          ELSE r.count + 1
        END,
        reset_at = CASE
          WHEN r.reset_at <= now() THEN now() + make_interval(secs => p_window_ms / 1000.0)
          ELSE r.reset_at
        END
  RETURNING * INTO bucket;

  allowed := bucket.count <= p_limit;
  remaining := GREATEST(p_limit - bucket.count, 0);
  retry_after_ms := GREATEST(CEIL(EXTRACT(EPOCH FROM (bucket.reset_at - now())) * 1000)::INTEGER, 0);
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.check_rate_limit(TEXT, INTEGER, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_rate_limit(TEXT, INTEGER, INTEGER) TO service_role;

CREATE OR REPLACE FUNCTION public.sweep_rate_limits()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  removed INTEGER;
BEGIN
  DELETE FROM public.rate_limits WHERE reset_at < now() - INTERVAL '1 day';
  GET DIAGNOSTICS removed = ROW_COUNT;
  RETURN removed;
END;
$$;

REVOKE ALL ON FUNCTION public.sweep_rate_limits() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sweep_rate_limits() TO service_role;

-- ------------------------------------------------------------
-- 8. Notification send ledger (makes re-running the cron safe)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notification_sends (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  window_key TEXT NOT NULL,
  sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, kind, window_key)
);

CREATE INDEX IF NOT EXISTS idx_notification_sends_user
  ON public.notification_sends (user_id, sent_at DESC);

ALTER TABLE public.notification_sends ENABLE ROW LEVEL SECURITY;
-- No policies: written and read only by the cron route via the service role.

-- Only the trades inside the windows being emailed, so the cron no longer reads
-- each user's whole journal. Service-role only (it takes an explicit user id).
CREATE OR REPLACE FUNCTION public.notification_trades(p_user_id UUID, p_since TIMESTAMPTZ)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH scoped AS (
    SELECT pnl, close_time, open_time, created_at,
           COALESCE(close_time, open_time, created_at) AS traded_at
    FROM public.trades
    WHERE user_id = p_user_id
      AND COALESCE(close_time, open_time, created_at) >= p_since
  )
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object('pnl', pnl, 'close_time', close_time, 'open_time', open_time, 'created_at', created_at)
      ORDER BY traded_at
    ),
    '[]'::jsonb
  )
  FROM scoped;
$$;

REVOKE ALL ON FUNCTION public.notification_trades(UUID, TIMESTAMPTZ)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notification_trades(UUID, TIMESTAMPTZ) TO service_role;
