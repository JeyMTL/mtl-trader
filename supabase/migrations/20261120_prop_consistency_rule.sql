-- ============================================================
-- Prop-firm consistency rule.
--
-- Most evaluations do not stop at "hit the profit target": they also cap how
-- much of that profit may come from a single day. A 30% consistency rule means
-- no one day may account for more than 30% of the total gain, so a trader who
-- makes the target in one lucky session still has to prove the edge is repeatable.
--
-- The rule is stored per account like the others and reported by `prop_status()`
-- from the trades themselves. A negative or zero total has no consistency to
-- measure, so the rule is silent until the account is in profit.
--
-- Idempotent: ADD COLUMN IF NOT EXISTS / CREATE OR REPLACE, safe to re-run.
-- ============================================================

ALTER TABLE public.prop_rules
  ADD COLUMN IF NOT EXISTS consistency_pct NUMERIC(5, 2) NOT NULL DEFAULT 30
    CHECK (consistency_pct > 0 AND consistency_pct <= 100);

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
  v_best_day NUMERIC;
  v_consistency NUMERIC;
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

  -- The best single day in the evaluation, and its share of the total gain.
  SELECT COALESCE(MAX(day_pnl), 0) INTO v_best_day
  FROM (
    SELECT SUM(pnl) AS day_pnl
    FROM public.trades
    WHERE user_id = p_user_id
      AND COALESCE(close_time, open_time, created_at) >= v_start
    GROUP BY (COALESCE(close_time, open_time, created_at) AT TIME ZONE 'UTC')::date
  ) AS days;
  v_best_day := GREATEST(COALESCE(v_best_day, 0), 0);
  v_consistency := CASE
    WHEN v_total_pnl > 0 THEN v_best_day / v_total_pnl * 100
    ELSE 0
  END;

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
    WHEN v_total_pnl > 0 AND v_consistency > r.consistency_pct THEN 'breach_consistency'
    WHEN v_daily_pnl <= -v_daily_cap * 0.8 THEN 'warn_daily'
    WHEN v_drawdown >= v_limit * 0.8 THEN 'warn_drawdown'
    WHEN v_total_pnl > 0 AND v_consistency >= r.consistency_pct * 0.9 THEN 'warn_consistency'
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
    'best_day_pnl', ROUND(v_best_day, 2),
    'consistency', ROUND(v_consistency, 2),
    'consistency_pct', r.consistency_pct,
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
