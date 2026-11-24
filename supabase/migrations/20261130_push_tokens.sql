-- ============================================================
-- Device tokens for server-sent notifications
--
-- One row per device, keyed by the FCM registration token itself: FCM can
-- rotate a token, and a rotated token arrives as a new row rather than an
-- update to an old one. A user may hold several (phone and tablet), so
-- `user_id` is indexed but is not unique.
--
-- RLS is on with no policies, which is deliberate: a token is a capability to
-- wake someone's phone, so it is written and read only by the service role in
-- the API routes, never by the app or the browser. Deleting the user cascades,
-- so no orphaned tokens can outlive the account.
--
-- Idempotent: CREATE TABLE / INDEX IF NOT EXISTS.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.push_tokens (
  token      text PRIMARY KEY,
  user_id    uuid NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  platform   text NOT NULL DEFAULT 'android',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS push_tokens_user_idx ON public.push_tokens (user_id);

ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;
