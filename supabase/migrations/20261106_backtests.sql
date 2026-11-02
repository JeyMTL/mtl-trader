-- Saved backtests.
--
-- A backtest result is only worth keeping if it is reproducible, so the row
-- stores everything that decided it: the strategy id and its normalised params,
-- the cost model and sizing, the exact data window, the metrics and the trades.
-- Re-running the same inputs must produce the same row, and a stored run without
-- its assumptions is a number with no context.
--
-- Like `broker_connections`, every write goes through the API with the service
-- role: a browser must not be able to insert a run it never executed, or edit a
-- metric to look better.

CREATE TABLE IF NOT EXISTS public.backtests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  symbol TEXT NOT NULL,
  timeframe TEXT NOT NULL DEFAULT 'M1',
  strategy_id TEXT NOT NULL,
  strategy_params JSONB NOT NULL DEFAULT '{}'::jsonb,
  config JSONB NOT NULL,
  bar_count INTEGER NOT NULL,
  period_start TIMESTAMPTZ NOT NULL,
  period_end TIMESTAMPTZ NOT NULL,
  metrics JSONB NOT NULL,
  -- Independent in-sample / out-of-sample runs over the same data.
  split_metrics JSONB,
  equity_curve JSONB,
  trades JSONB,
  assumptions JSONB NOT NULL DEFAULT '[]'::jsonb,
  warnings JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.backtests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "backtests_select_own" ON public.backtests;
CREATE POLICY "backtests_select_own" ON public.backtests
  FOR SELECT USING (auth.uid() = user_id);

-- No insert/update/delete policy on purpose: runs are created by
-- POST /api/backtest, which validates and simulates before writing.
REVOKE ALL ON public.backtests FROM anon, authenticated;
GRANT SELECT ON public.backtests TO authenticated;

CREATE INDEX IF NOT EXISTS idx_backtests_user_created
  ON public.backtests (user_id, created_at DESC);
