-- ============================================================
-- Signup: "Database error saving new user"
--
-- Supabase Auth answers exactly this on any failure of the INSERT INTO
-- auth.users — `{"code":"unexpected_failure","message":"Database error saving
-- new user"}`. The clients (web `/auth/signup`, the Flutter login screen) only
-- call `auth.signUp`, and the profile row is created afterwards by
-- `/api/auth/signup` through the service role, so nothing in this repo can
-- produce that message: it is a database-side failure in Auth's own write.
--
-- Two causes fit this project, and both are repaired here:
--
--   1. A `handle_new_user`-style trigger on auth.users. The function has to be
--      SECURITY DEFINER with a pinned `search_path` (public.users has RLS and,
--      since 20261019, no INSERT privilege for clients), and it must tolerate a
--      profile row that already exists — otherwise every signup fails with a
--      permission, RLS or duplicate-key error, which Auth reports as the message
--      above and nothing more.
--   2. A profile row left behind holding the email. When an auth user is deleted
--      but its `public.users` row survives, the next signup with that address
--      hits `users_email_key` inside the trigger and dies the same way. That is
--      what "one person cannot sign up, everyone else can" usually means.
--
-- The trigger is also what gives a *phone* account its profile row: the Flutter
-- app signs up straight against Supabase and never calls the web route, so
-- without this a mobile signup has no `public.users` row, no trial and no plan.
--
-- Idempotent: safe to re-run.
-- ============================================================

-- Diagnose before/after (SQL editor). Empty means no profile trigger was ever
-- created — and then the failing write is somewhere else (an Auth hook, or the
-- project itself); check Supabase → Authentication → Logs for the raw error.
--
--   SELECT t.tgname, p.proname, p.prosecdef
--   FROM pg_trigger t
--   JOIN pg_proc p ON p.oid = t.tgfoid
--   WHERE t.tgrelid = 'auth.users'::regclass AND NOT t.tgisinternal;
--
--   SELECT u.id, u.email
--   FROM public.users u
--   WHERE NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id = u.id);

-- ------------------------------------------------------------
-- 1. Orphan profiles: an account was deleted, its row was not
-- ------------------------------------------------------------
-- `delete_account_data()` and the cascade work (20261026), but a row written by
-- an older hand-made trigger can still outlive its auth user. Those rows hold an
-- email nobody can ever sign up with, so they are removed first.
DELETE FROM public.users u
WHERE NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id = u.id);

-- ------------------------------------------------------------
-- 2. Remove legacy app-owned triggers on auth.users
-- ------------------------------------------------------------
-- Any profile trigger written by hand in the dashboard lives in `public`; the
-- ones Supabase installs itself live in `auth` and are left alone. Dropping by
-- lookup rather than by name is deliberate: the broken trigger's name is not
-- recorded in this repo, and leaving it in place would abort every signup
-- before the replacement below ever runs.
DO $$
DECLARE
  leftover RECORD;
BEGIN
  FOR leftover IN
    SELECT t.tgname
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE t.tgrelid = 'auth.users'::regclass
      AND NOT t.tgisinternal
      AND n.nspname = 'public'
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON auth.users', leftover.tgname);
  END LOOP;
END
$$;

-- ------------------------------------------------------------
-- 3. One profile writer, and only this one
-- ------------------------------------------------------------
-- SECURITY DEFINER because Auth writes as `supabase_auth_admin`: an invoker
-- function is subject to public.users' RLS (its policies compare against
-- `auth.uid()`, which is NULL during signup) and to the revoked INSERT
-- privilege from 20261019. `search_path` is pinned so the function cannot be
-- pointed at another schema.
--
-- The row it writes is what `trialFields()` in `src/lib/subscription.ts` writes:
-- free tier, trial status, unlimited allowance for the 30 days. `/api/auth/signup`
-- upserts the same values afterwards with `ignoreDuplicates`, so the two cannot
-- disagree and a repeat cannot restart the trial.
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
    now() + INTERVAL '30 days',
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
  'Creates the public.users profile on signup. Security definer with a pinned search_path so Auth can write past RLS, and conflict-tolerant so a profile problem can never block account creation.';

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
