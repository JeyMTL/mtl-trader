-- Measured per-trade excursions, so exit capture is a table read instead of a
-- vendor call every time Analytics renders.
--
-- `trades` already holds entry and exit; the move between them is invisible
-- without the chart. For each closed trade the API measures the best and worst
-- price while it was open from the OANDA candles this app already serves:
--
--   mfe       maximum favourable excursion, in price units
--   mae       maximum adverse excursion, in price units
--   realised  the exit's move in the trade's direction
--   capture   realised / mfe, NULL when the trade never went the trader's way
--
-- A row exists only when the bars covered the whole trade (`complete`), because
-- a partial series understates the move and flatters the exit. Deleting a trade
-- deletes its measurement; nothing here is derived data the customer cannot
-- regenerate by reopening Analytics.
--
-- RLS is ownership-only, the same rule as `trades` and `chart_drawings`. The API
-- writes with the service role, so these policies are for the "read my own
-- numbers" path a future dashboard read would use.

CREATE TABLE IF NOT EXISTS public.trade_excursions (
  trade_id UUID PRIMARY KEY REFERENCES public.trades(id) ON DELETE CASCADE,
  user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES public.users(id) ON DELETE CASCADE,
  mfe NUMERIC NOT NULL,
  mae NUMERIC NOT NULL,
  realised NUMERIC NOT NULL,
  -- No ratio when mfe is zero: a trade that never moved in the trader's favour
  -- has nothing to capture, and a 0 could not be told apart from a total loss.
  capture NUMERIC,
  peak_at TIMESTAMPTZ,
  bars INTEGER NOT NULL,
  bar_interval TEXT NOT NULL,
  complete BOOLEAN NOT NULL DEFAULT true,
  measured_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Every read is "my measurements in this date range".
CREATE INDEX IF NOT EXISTS idx_trade_excursions_user_measured
  ON public.trade_excursions (user_id, measured_at DESC);

ALTER TABLE public.trade_excursions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own trade excursions" ON public.trade_excursions;
CREATE POLICY "Users can view own trade excursions" ON public.trade_excursions
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own trade excursions" ON public.trade_excursions;
CREATE POLICY "Users can insert own trade excursions" ON public.trade_excursions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own trade excursions" ON public.trade_excursions;
CREATE POLICY "Users can update own trade excursions" ON public.trade_excursions
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own trade excursions" ON public.trade_excursions;
CREATE POLICY "Users can delete own trade excursions" ON public.trade_excursions
  FOR DELETE USING (auth.uid() = user_id);

-- Account deletion is a single `DELETE FROM users`, so both foreign keys here
-- (`trade_id` and `user_id`) cascade and a deleted journal leaves no measurements
-- behind.
COMMENT ON TABLE public.trade_excursions IS
  'Per-trade MFE/MAE and exit capture, measured from OANDA candles. One row per trade, written by /api/analytics/excursion.';
