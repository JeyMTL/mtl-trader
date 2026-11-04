-- ============================================================
-- Backfill: accounts that have no profile row
--
-- `20261116_new_user_profile_trigger.sql` only covers accounts created from now
-- on. Every account that was created before it exists in `auth.users` and may
-- have no `public.users` row at all — the phone app signs up straight against
-- Supabase and never calls `/api/auth/signup`, so a mobile signup had nothing to
-- write the profile.
--
-- A missing row is not cosmetic. The app reads the plan from it, so the account
-- shows no trial; `/api/trial/activate` answers 404; `enforce_trade_quota` treats
-- an unknown user as unlimited; and the account cannot be paid for, because the
-- order functions all answer `unknown_user`.
--
-- The values written are exactly what a new signup gets (`trialFields()` in
-- `src/lib/subscription.ts`): free tier, trial status, unlimited allowance for 30
-- days from now. Accounts that already have a row are untouched, so nobody's
-- running trial is restarted and no paid plan is rewritten.
--
-- Idempotent: re-running inserts nothing.
-- ============================================================

-- How many are missing (run on its own first if you want the number):
--
--   SELECT count(*) AS missing_profiles
--   FROM auth.users a
--   WHERE a.email IS NOT NULL
--     AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = a.id);

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
SELECT
  a.id,
  a.email,
  COALESCE(a.raw_user_meta_data->>'full_name', ''),
  'free',
  'trial',
  now() + INTERVAL '30 days',
  -1,
  -1
FROM auth.users a
WHERE a.email IS NOT NULL
  AND btrim(a.email) <> ''
  AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = a.id)
-- Same guard as the trigger: a row holding that email (a live one, or one the
-- 20261116 cleanup has already removed) must not abort the backfill.
ON CONFLICT DO NOTHING;
