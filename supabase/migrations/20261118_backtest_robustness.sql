-- Robustness on saved backtests.
--
-- Both values are derived from the same bars and trades the run already stores,
-- but keeping them means a saved report renders its benchmark and reshuffle
-- range without replaying the simulation. They are written by the API with the
-- service role like every other column, so they cannot be edited by a browser.

ALTER TABLE public.backtests
  ADD COLUMN IF NOT EXISTS benchmark JSONB,
  ADD COLUMN IF NOT EXISTS stress JSONB;
