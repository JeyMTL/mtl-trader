-- ------------------------------------------------------------
-- billing_subscriptions: which remote subscription belongs to which account.
--
-- This table used to arrive with 20261030_flutterwave_billing.sql, which also
-- carried the Flutterwave integration this deployment no longer ships. The
-- Paddle webhook still records every subscription here — it is how cancel and
-- refund find the account from a Paddle subscription or transaction id — so the
-- table is kept and the provider-specific parts of that migration are not.
--
-- The definition is identical to the original, including the
-- UNIQUE (user_id, provider) constraint: the webhook upserts with
-- `onConflict: 'user_id,provider'`, which fails without it.
--
-- Idempotent: CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT EXISTS, so it is
-- harmless on a database that already ran 20261030.
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.billing_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  email TEXT,
  remote_plan_id TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, provider)
);

CREATE INDEX IF NOT EXISTS idx_billing_subscriptions_email
  ON public.billing_subscriptions (lower(email));

ALTER TABLE public.billing_subscriptions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.billing_subscriptions FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.billing_subscriptions TO service_role;
