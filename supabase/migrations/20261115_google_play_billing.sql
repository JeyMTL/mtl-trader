-- ============================================================
-- Google Play subscriptions
--
-- Google Play sells a subscription through its own billing system and tells the
-- *server* whether it is real. The app never asserts anything it can be sure of:
-- it hands over the purchase token, the server asks Google what that token is
-- worth, and only then is a plan applied. The token is kept here so a renewal can
-- be re-checked without the buyer having to open the app again.
--
-- Two things change:
--
--   1. `payment_events` gains a 'google' provider. The two order functions below
--      are copied verbatim from 20261109_prices.sql and 20261110_annual_plans.sql
--      — same amounts, same idempotency key, same refusal to downgrade — with
--      only the provider allow-list extended. They are re-created here rather
--      than given a new name because every provider (PayPal, bank, Paddle) calls
--      the five-argument versions through PostgREST, and a second function would
--      split the record of what has been paid for.
--
--   2. `google_play_subscriptions` holds one token per account. Re-checking a
--      token is idempotent: the order event is keyed on the token plus the period
--      end, so a renewal applies once and a replay applies nothing.
--
-- Idempotent: CREATE TABLE IF NOT EXISTS / CREATE OR REPLACE.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.google_play_subscriptions (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  purchase_token TEXT NOT NULL,
  product_id TEXT NOT NULL,
  plan_id TEXT NOT NULL,
  interval TEXT NOT NULL DEFAULT 'month',
  -- Google's own state string, kept so a support question can be answered
  -- without guessing what the row meant at the time.
  state TEXT,
  expires_at TIMESTAMPTZ,
  acknowledged BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The reconcile job walks subscriptions that are still in force, oldest expiry
-- first, so the index matches that read.
CREATE INDEX IF NOT EXISTS idx_google_play_subscriptions_expiry
  ON public.google_play_subscriptions (expires_at ASC);

ALTER TABLE public.google_play_subscriptions ENABLE ROW LEVEL SECURITY;
-- No policies: written and read only by the server (service role). A client that
-- could insert here could hand itself a paid plan.
REVOKE ALL ON public.google_play_subscriptions FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.google_play_subscriptions TO service_role;

-- ------------------------------------------------------------
-- Monthly purchase, now also accepting Google Play.
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
  IF p_provider IS NULL OR p_provider NOT IN ('paypal', 'bank', 'flutterwave', 'paddle', 'google')
    OR p_provider_event_id IS NULL OR btrim(p_provider_event_id) = '' THEN
    RETURN 'invalid_plan';
  END IF;

  expected_amount := CASE p_plan_id
    WHEN 'basic' THEN 12.00
    WHEN 'pro' THEN 29.00
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
  new_max_trades := CASE p_plan_id WHEN 'pro' THEN -1 ELSE -1 END;
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

  -- Renewals stack onto unexpired time, so paying early never loses days.
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

-- ------------------------------------------------------------
-- Annual purchase, now also accepting Google Play.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_annual_order(
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
  IF p_provider IS NULL OR p_provider NOT IN ('paypal', 'bank', 'flutterwave', 'paddle', 'google')
    OR p_provider_event_id IS NULL OR btrim(p_provider_event_id) = '' THEN
    RETURN 'invalid_plan';
  END IF;

  expected_amount := CASE p_plan_id
    WHEN 'basic' THEN 120.00
    WHEN 'pro' THEN 290.00
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
  new_max_trades := -1;
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

  -- Renewals stack onto unexpired time, so renewing early never loses days.
  period_start := CASE WHEN period_still_active THEN account.current_period_start ELSE now() END;

  UPDATE public.users
  SET subscription_tier = p_plan_id,
      subscription_status = 'active',
      max_trades = new_max_trades,
      trades_remaining = new_max_trades,
      current_period_start = period_start,
      current_period_end = GREATEST(now(), COALESCE(account.current_period_end, now())) + INTERVAL '365 days',
      cancel_at_period_end = false,
      last_payment_at = now()
  WHERE id = p_user_id;

  RETURN 'applied';
END;
$$;

REVOKE ALL ON FUNCTION public.apply_annual_order(UUID, TEXT, TEXT, TEXT, NUMERIC)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_annual_order(UUID, TEXT, TEXT, TEXT, NUMERIC)
  TO service_role;
