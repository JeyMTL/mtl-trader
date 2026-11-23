-- ============================================================
-- Trial length: 7 days -> 3 days, for new signups only
--
-- One change, forward-only: `handle_new_user` writes a 3-day trial. It is the
-- real writer — `/api/auth/signup` upserts with `ignoreDuplicates`, so this
-- function wins over `trialFields()` in `src/lib/subscription.ts`. The constant
-- is changed alongside it so anything that reads the length (copy, the trial
-- banner, notifications) agrees with the row.
--
-- Existing trials are deliberately not rewritten: someone who was given 7 days
-- keeps them until their own `trial_ends_at`. Shortening a trial a trader is
-- already using would take days away that were promised.
--
-- Everything else in the function is unchanged from
-- 20261128_seven_day_trial.sql; it is reproduced whole because Postgres has
-- no "replace one literal in a function".
--
-- Idempotent: CREATE OR REPLACE / DROP TRIGGER IF EXISTS.
-- ============================================================

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
    now() + INTERVAL '3 days',
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
  'Creates the public.users profile on signup with a 3-day unlimited trial. Security definer with a pinned search_path so Auth can write past RLS, and conflict-tolerant so a profile problem can never block account creation.';

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
