-- Unlimited trade volume on every paid plan.
--
-- Basic used to be capped at 50 trades a month while the *trial* was unlimited.
-- That inverted the deal: the day a customer paid, the product got worse in the
-- one place they would notice first, and a trader doing two trades a day hit the
-- cap about three weeks into the month. Volume is no longer a differentiator —
-- Basic and Pro both carry unlimited trades, and the plans differ on the
-- analysis workflow (backtester, replay) and the AI review allowance.
--
-- Two places had to change:
--
--   1. Existing rows. `apply_paid_order` and `apply_annual_order` write
--      `max_trades = CASE p_plan_id WHEN 'pro' THEN -1 ELSE 50 END`, so every
--      active Basic account still holds 50.
--   2. Future writes. Those functions hardcode the same CASE. Rather than
--      re-create two long functions (and risk the five-argument PostgREST calls
--      that PayPal, bank, Flutterwave and Paddle all use), the allowance is
--      pinned by a trigger: any row that is an active paid tier gets -1 whatever
--      the caller asked for. One choke point, so a future plan function cannot
--      reintroduce the cap by accident.
--
-- Nothing else moves: `enforce_trade_quota()` already treats -1 as unlimited,
-- the downgrade paths still write 0 for expired, cancelled and revoked accounts
-- (so they stay read-only), and the trial keeps its unlimited month.

-- 1. Existing paid accounts.
UPDATE public.users
SET max_trades = -1,
    trades_remaining = -1
WHERE subscription_status = 'active'
  AND subscription_tier IN ('basic', 'pro');

-- 2. Future writes.
CREATE OR REPLACE FUNCTION public.normalize_paid_allowance()
RETURNS TRIGGER AS $$
BEGIN
  -- Only an in-force paid period is unlimited. A lapsed row keeps whatever the
  -- expiry or revocation path set, and a manually comped plan gets the same
  -- unlimited volume every other paying customer gets.
  IF NEW.subscription_status = 'active'
     AND NEW.subscription_tier IN ('basic', 'pro') THEN
    NEW.max_trades := -1;
    NEW.trades_remaining := -1;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_normalize_paid_allowance ON public.users;
CREATE TRIGGER trg_normalize_paid_allowance
  BEFORE INSERT OR UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.normalize_paid_allowance();

COMMENT ON FUNCTION public.normalize_paid_allowance() IS
  'Pins max_trades to -1 (unlimited) for any active paid tier, so no plan function can cap a paying account below the trial.';

COMMENT ON FUNCTION public.enforce_trade_quota() IS
  'Refuses trade inserts past the monthly allowance. -1 is unlimited; every in-force paid tier is pinned to -1 by trg_normalize_paid_allowance.';
