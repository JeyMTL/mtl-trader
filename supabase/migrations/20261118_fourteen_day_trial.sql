-- ============================================================
-- Trial length: 30 days -> 14 days
--
-- Two changes, both forward-only:
--
--   1. `handle_new_user` writes a 14-day trial instead of 30. It is the real
--      writer: `/api/auth/signup` upserts with `ignoreDuplicates`, so the SQL
--      wins over `trialFields()` in `src/lib/subscription.ts`. The constant is
--      changed too, but a fresh signup gets its dates from here.
--   2. `expire_lapsed_subscriptions` now also closes trials whose end date has
--      passed. Before this, a lapsed trial kept `subscription_status = 'trial'`
--      and `max_trades = -1`, so the dashboard and the app showed "trial" and
--      "Unlimited" long after the server had started refusing writes. The daily
--      reconcile cron already calls this function.
--
-- Existing trials are deliberately not rewritten: anyone who was granted 30
-- days keeps them until their own `trial_ends_at`. Only new signups get 14.
--
-- Idempotent: CREATE OR REPLACE / DROP TRIGGER IF EXISTS.
-- ============================================================

-- ------------------------------------------------------------
-- 1. New signups: 14 days
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- A provider that verifies no address (phone, some SSO) has nothing to key a
  -- profile on; Auth must still succeed, so the trigger simply steps aside.
  IF NEW.email IS NULL OR btrim(NEW.email) = '' THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.users (
    id,
    email,
    full_name,
    subscription_tier,
    subscription_status,
    trial_ends_at,
    max_trades,
    trades_remaining
  )
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    'free',
    'trial',
    now() + INTERVAL '14 days',
    -1,
    -1
  )
  -- Untargeted on purpose: it swallows the primary-key clash of a replayed
  -- insert *and* the unique-email clash of a stale row, and neither can be
  -- allowed to fail the auth insert. The profile is then repaired by
  -- /api/auth/signup (service role) the way it is for every other account.
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_user() IS
  'Creates the public.users profile on signup with a 14-day unlimited trial. Security definer with a pinned search_path so Auth can write past RLS, and conflict-tolerant so a profile problem can never block account creation.';

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ------------------------------------------------------------
-- 2. Lapsed trials close with the lapsed paid periods
-- ------------------------------------------------------------
-- `expire_lapsed_subscriptions` is what the daily reconcile cron runs. Adding
-- trials here makes the stored row agree with the server-side checks: a trial
-- past its end reads as expired and has no allowance, so the upgrade prompt has
-- something true to show.
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
      max_trades = 0,
      trades_remaining = 0,
      cancel_at_period_end = false
  WHERE subscription_status = 'active'
    AND current_period_end IS NOT NULL
    AND current_period_end <= now();

  GET DIAGNOSTICS expired_paid = ROW_COUNT;

  UPDATE public.users
  SET subscription_tier = 'free',
      subscription_status = 'expired',
      max_trades = 0,
      trades_remaining = 0,
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
