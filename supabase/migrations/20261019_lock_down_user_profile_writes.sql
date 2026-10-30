-- Profile self-service must not grant control of roles, plans, or sync secrets.
REVOKE INSERT, UPDATE ON TABLE public.users FROM PUBLIC, anon, authenticated;

GRANT UPDATE (
  full_name,
  timezone,
  currency,
  notifications_email,
  notifications_daily,
  notifications_weekly,
  notifications_marketing,
  notifications_journal_reminders,
  notifications_monthly_overview,
  notifications_monthly_email
) ON TABLE public.users TO authenticated;

-- Paid-order events and plan changes must commit or roll back together.
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

  current_rank := CASE account.subscription_tier
    WHEN 'pro' THEN 2
    WHEN 'basic' THEN 1
    ELSE 0
  END;
  requested_rank := CASE p_plan_id WHEN 'pro' THEN 2 ELSE 1 END;
  new_max_trades := CASE p_plan_id WHEN 'pro' THEN -1 ELSE 50 END;
  event_status := CASE
    WHEN account.subscription_status = 'active' AND current_rank > requested_rank
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

  UPDATE public.users
  SET subscription_tier = p_plan_id,
      subscription_status = 'active',
      max_trades = new_max_trades,
      trades_remaining = new_max_trades
  WHERE id = p_user_id;

  RETURN 'applied';
END;
$$;

REVOKE ALL ON FUNCTION public.apply_paid_order(UUID, TEXT, TEXT, TEXT, NUMERIC)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_paid_order(UUID, TEXT, TEXT, TEXT, NUMERIC)
  TO service_role;

CREATE OR REPLACE FUNCTION public.review_bank_payment_request(
  p_request_id UUID,
  p_reviewer_id UUID,
  p_action TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  payment_request public.payment_requests%ROWTYPE;
  payment_result TEXT;
BEGIN
  IF p_action IS NULL OR p_action NOT IN ('approve', 'reject') THEN
    RETURN 'invalid_action';
  END IF;

  SELECT * INTO payment_request
  FROM public.payment_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN 'not_found';
  END IF;
  IF payment_request.status <> 'pending' THEN
    RETURN 'already_processed';
  END IF;

  IF p_action = 'reject' THEN
    UPDATE public.payment_requests
    SET status = 'rejected',
        reviewed_by = p_reviewer_id,
        reviewed_at = NOW()
    WHERE id = p_request_id;
    RETURN 'rejected';
  END IF;

  payment_result := public.apply_paid_order(
    payment_request.user_id,
    'bank',
    'bank:request:' || payment_request.id::TEXT,
    payment_request.plan_id,
    payment_request.amount
  );

  IF payment_result NOT IN ('applied', 'would_downgrade', 'duplicate') THEN
    RETURN payment_result;
  END IF;

  UPDATE public.payment_requests
  SET status = 'approved',
      reviewed_by = p_reviewer_id,
      reviewed_at = NOW()
  WHERE id = p_request_id;

  RETURN payment_result;
END;
$$;

REVOKE ALL ON FUNCTION public.review_bank_payment_request(UUID, UUID, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.review_bank_payment_request(UUID, UUID, TEXT)
  TO service_role;
