-- ============================================================
-- Prop-firm rule compliance.
--
-- A prop evaluation is lost by breaching a rule, not by losing a trade, so the
-- useful thing to show is the headroom left on each rule. The rules are stored
-- per account and the standing is computed from the trades themselves.
--
-- The status function takes an explicit user id and is granted only to
-- service_role: it is called by the authenticated route, never by the browser,
-- so a signed-in user cannot read someone else's account standing.
--
-- Reading the account size as the starting equity is deliberate. A prop account
-- opens at its nominal balance and the evaluation measures P&L from there, not
-- from whatever the trader deposited into a personal broker.
--
-- Idempotent: CREATE IF NOT EXISTS / CREATE OR REPLACE, safe to re-run.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.prop_rules (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  account_size NUMERIC(14, 2) NOT NULL CHECK (account_size > 0),
  max_daily_loss_pct NUMERIC(5, 2) NOT NULL DEFAULT 5
    CHECK (max_daily_loss_pct > 0 AND max_daily_loss_pct <= 50),
  max_drawdown_pct NUMERIC(5, 2) NOT NULL DEFAULT 10
    CHECK (max_drawdown_pct > 0 AND max_drawdown_pct <= 100),
  trailing_drawdown BOOLEAN NOT NULL DEFAULT TRUE,
  profit_target_pct NUMERIC(5, 2) NOT NULL DEFAULT 10
    CHECK (profit_target_pct >= 0 AND profit_target_pct <= 200),
  min_trading_days INTEGER NOT NULL DEFAULT 5
    CHECK (min_trading_days >= 0 AND min_trading_days <= 60),
  started_on DATE NOT NULL DEFAULT CURRENT_DATE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Server-only table: the dashboard route writes with the service role, which
-- bypasses RLS. Without policies, anon/authenticated can read nothing.
ALTER TABLE public.prop_rules ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.prop_rules FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.prop_status(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r public.prop_rules%ROWTYPE;
  v_start TIMESTAMPTZ;
  v_day_start TIMESTAMPTZ;
  v_daily_pnl NUMERIC;
  v_total_pnl NUMERIC;
  v_peak NUMERIC;
  v_equity NUMERIC;
  v_drawdown NUMERIC;
  v_limit NUMERIC;
  v_target NUMERIC;
  v_daily_cap NUMERIC;
  v_days INTEGER;
  v_status TEXT;
BEGIN
  SELECT * INTO r FROM public.prop_rules WHERE user_id = p_user_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('configured', false);
  END IF;

  v_start := r.started_on::timestamptz;
  v_day_start := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';

  SELECT COALESCE(SUM(pnl), 0) INTO v_daily_pnl
  FROM public.trades
  WHERE user_id = p_user_id
    AND COALESCE(close_time, open_time, created_at) >= v_day_start;

  SELECT COALESCE(SUM(pnl), 0) INTO v_total_pnl
  FROM public.trades
  WHERE user_id = p_user_id
    AND COALESCE(close_time, open_time, created_at) >= v_start;

  -- Highest running balance since the evaluation began. A trailing drawdown is
  -- measured from that peak, which is what makes it harder than a static one.
  SELECT COALESCE(MAX(running), 0) INTO v_peak
  FROM (
    SELECT SUM(pnl) OVER (ORDER BY COALESCE(close_time, open_time, created_at)) AS running
    FROM public.trades
    WHERE user_id = p_user_id
      AND COALESCE(close_time, open_time, created_at) >= v_start
  ) AS series;
  v_peak := GREATEST(COALESCE(v_peak, 0), 0);

  v_equity := r.account_size + v_total_pnl;
  v_drawdown := GREATEST(0, (r.account_size + v_peak) - v_equity);
  IF r.trailing_drawdown THEN
    v_limit := (r.account_size + v_peak) * r.max_drawdown_pct / 100;
  ELSE
    v_limit := r.account_size * r.max_drawdown_pct / 100;
  END IF;

  v_daily_cap := r.account_size * r.max_daily_loss_pct / 100;
  v_target := r.account_size * r.profit_target_pct / 100;

  SELECT COUNT(DISTINCT (COALESCE(close_time, open_time, created_at) AT TIME ZONE 'UTC')::date)
  INTO v_days
  FROM public.trades
  WHERE user_id = p_user_id
    AND COALESCE(close_time, open_time, created_at) >= v_start;

  v_status := CASE
    WHEN v_daily_pnl <= -v_daily_cap THEN 'breach_daily'
    WHEN v_drawdown >= v_limit THEN 'breach_drawdown'
    WHEN v_daily_pnl <= -v_daily_cap * 0.8 THEN 'warn_daily'
    WHEN v_drawdown >= v_limit * 0.8 THEN 'warn_drawdown'
    ELSE 'ok'
  END;

  RETURN jsonb_build_object(
    'configured', true,
    'account_size', r.account_size,
    'equity', ROUND(v_equity, 2),
    'peak_equity', ROUND(r.account_size + v_peak, 2),
    'daily_pnl', ROUND(v_daily_pnl, 2),
    'daily_loss_limit', ROUND(v_daily_cap, 2),
    'daily_headroom', ROUND(GREATEST(0, v_daily_cap + v_daily_pnl), 2),
    'drawdown', ROUND(v_drawdown, 2),
    'drawdown_limit', ROUND(v_limit, 2),
    'drawdown_headroom', ROUND(GREATEST(0, v_limit - v_drawdown), 2),
    'profit_target', ROUND(v_target, 2),
    'profit_progress', ROUND(v_total_pnl, 2),
    'trading_days', v_days,
    'min_trading_days', r.min_trading_days,
    'trailing_drawdown', r.trailing_drawdown,
    'max_daily_loss_pct', r.max_daily_loss_pct,
    'max_drawdown_pct', r.max_drawdown_pct,
    'profit_target_pct', r.profit_target_pct,
    'status', v_status
  );
END;
$$;

REVOKE ALL ON FUNCTION public.prop_status(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prop_status(UUID) TO service_role;
