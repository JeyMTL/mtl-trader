-- ------------------------------------------------------------
-- Annual plans: Basic $120/year, Pro $290/year.
--
-- Annual is applied by a second function rather than by adding a day-count
-- argument to `apply_paid_order`: that function is called by five-argument
-- PostgREST calls from the PayPal, bank, Flutterwave and Paddle paths, and
-- changing its signature would silently break whichever caller was not updated
-- in the same deploy. This one is additive, so the monthly path keeps working
-- exactly as it does today.
--
-- Everything except the amounts and the period length is copied verbatim from
-- 20261109_prices.sql: same provider allow-list, same idempotency key, same
-- refusal to downgrade an unexpired higher plan, same stacking of unexpired time.
--
-- Grandfathering still applies to the monthly function only. When the first
-- annual customer renews, Paddle repeats `transaction.completed` for the same
-- subscription, so a renewal simply stacks another 365 days here.
--
-- Idempotent: CREATE OR REPLACE, so re-running is safe.
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
  IF p_provider IS NULL OR p_provider NOT IN ('paypal', 'bank', 'flutterwave', 'paddle')
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
