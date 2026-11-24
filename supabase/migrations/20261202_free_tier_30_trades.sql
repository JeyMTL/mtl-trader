-- The free tier is 30 trades a month, and it is a tier rather than a tombstone.
--
-- Until now a lapsed trial was rewritten to max_trades = 0, and
-- enforce_trade_quota() raised on *any* insert from a lapsed trial before it
-- even read the allowance. A trader therefore kept a journal they could read
-- and nothing they could add — which also left the prop-firm simulator with
-- nothing new to measure, because that screen is computed from the journal.
--
-- Three places change:
--
--   1. Rows that are not in an in-force paid period or a running trial get the
--      free allowance, 30.
--   2. The daily expiry job writes 30 instead of 0 for both lapsed paid periods
--      and lapsed trials.
--   3. The quota trigger stops refusing a lapsed trial outright. It applies the
--      row's allowance: -1 is unlimited, 0 stays blocked (revoked accounts set
--      that explicitly), anything else is a monthly cap.
--
-- A running trial still ignores max_trades and is unlimited, which is what
-- public.trialFields() writes as well. The prop-firm simulator is part of the
-- free tier; nothing in the app gates it.

-- ------------------------------------------------------------
-- 1. Existing accounts get the free allowance
-- ------------------------------------------------------------
-- Paid rows are pinned to -1 by trg_normalize_paid_allowance, and a running
-- trial is unlimited regardless of the column, so neither is touched.
UPDATE public.users
SET max_trades = 30,
    trades_remaining = 30
WHERE NOT (
  (subscription_status = 'active' AND subscription_tier IN ('basic', 'pro'))
  OR (subscription_status = 'trial'
      AND trial_ends_at IS NOT NULL
      AND trial_ends_at > now())
);

ALTER TABLE public.users ALTER COLUMN max_trades SET DEFAULT 30;
ALTER TABLE public.users ALTER COLUMN trades_remaining SET DEFAULT 30;

-- ------------------------------------------------------------
-- 2. The daily expiry job downgrades to free, not to zero
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_lapsed_subscriptions()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  expired_paid INTEGER;
  expired_trials INTEGER;
BEGIN
  UPDATE public.users
  SET subscription_tier = 'free',
      subscription_status = 'expired',
      max_trades = 30,
      trades_remaining = 30,
      cancel_at_period_end = false
  WHERE subscription_status = 'active'
    AND current_period_end IS NOT NULL
    AND current_period_end <= now();

  GET DIAGNOSTICS expired_paid = ROW_COUNT;

  UPDATE public.users
  SET subscription_tier = 'free',
      subscription_status = 'expired',
      max_trades = 30,
      trades_remaining = 30,
      cancel_at_period_end = false
  WHERE subscription_status = 'trial'
    AND trial_ends_at IS NOT NULL
    AND trial_ends_at <= now();

  GET DIAGNOSTICS expired_trials = ROW_COUNT;

  RETURN expired_paid + expired_trials;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_lapsed_subscriptions()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_lapsed_subscriptions() TO service_role;

-- ------------------------------------------------------------
-- 3. The quota trigger enforces the allowance, not a trial wall
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_trade_quota()
RETURNS TRIGGER AS $$
DECLARE
  m_max INTEGER;
  m_status TEXT;
  m_trial_end TIMESTAMP WITH TIME ZONE;
  m_count BIGINT;
  m_ts TIMESTAMP WITH TIME ZONE;
BEGIN
  SELECT max_trades, subscription_status, trial_ends_at
  INTO m_max, m_status, m_trial_end
  FROM public.users
  WHERE id = NEW.user_id;

  -- A running trial is unlimited: volume is not what a trial withholds.
  IF m_status = 'trial'
     AND m_trial_end IS NOT NULL
     AND m_trial_end > now() THEN
    RETURN NEW;
  END IF;

  -- A missing allowance means the row predates the free tier; treat it as free
  -- rather than blocking a journal for a schema reason.
  m_max := COALESCE(m_max, 30);

  IF m_max = -1 THEN
    RETURN NEW;
  END IF;

  IF m_max <= 0 THEN
    RAISE EXCEPTION 'This account cannot add trades right now. Contact support if that is unexpected.';
  END IF;

  m_ts := COALESCE(NEW.close_time, NEW.open_time, NEW.created_at, now());

  -- Only the current month counts against a cap; importing last year's history
  -- is not what a monthly allowance limits.
  IF date_trunc('month', m_ts) <> date_trunc('month', now()) THEN
    RETURN NEW;
  END IF;

  SELECT COUNT(*) INTO m_count
  FROM public.trades
  WHERE user_id = NEW.user_id
    AND date_trunc('month', COALESCE(close_time, open_time, created_at)) = date_trunc('month', now());

  IF m_count >= m_max THEN
    RAISE EXCEPTION 'Monthly trade limit reached (% trades). Upgrade your plan for more.', m_max;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION public.enforce_trade_quota() IS
  'Applies the row allowance: a running trial and -1 are unlimited, 0 is blocked, anything else is a monthly cap. The free tier is 30.';
