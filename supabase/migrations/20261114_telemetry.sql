-- Lightweight product telemetry: crashes and the activation funnel.
--
-- Deliberately first-party. A third-party crash service needs an account, a DSN
-- in the build and a paid tier once volume grows; this table needs none of that
-- and answers the two questions that actually matter before launch: where do
-- people drop out, and what is breaking on their device?
--
-- Nothing here is allowed to identify a person. No email, no IP, no free text
-- from the journal — `properties` is capped and the route drops oversized
-- payloads rather than storing a novel.
--
-- Rows are written only by the service role from /api/telemetry, so RLS is on
-- with no policies at all: a signed-in client cannot read another user's rows,
-- and cannot read its own either.

CREATE TABLE IF NOT EXISTS public.telemetry_events (
  id BIGSERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Anonymous until the user signs in; cleared rather than cascaded so the
  -- counts survive an account deletion (they carry no journal content).
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,

  -- Random per-launch id, so one session's events can be read in order without
  -- identifying the device across launches.
  session_id TEXT NOT NULL,

  platform TEXT NOT NULL,
  app_version TEXT,
  event TEXT NOT NULL,
  properties JSONB NOT NULL DEFAULT '{}'::jsonb,

  CONSTRAINT telemetry_event_shape CHECK (event ~ '^[a-z][a-z0-9_.]{1,63}$'),
  CONSTRAINT telemetry_session_shape CHECK (session_id ~ '^[A-Za-z0-9_-]{6,64}$'),
  CONSTRAINT telemetry_platform_shape CHECK (platform ~ '^[a-z]{3,12}$'),
  CONSTRAINT telemetry_properties_small CHECK (pg_column_size(properties) <= 2048)
);

-- Two access patterns: "what happened in the last hour" (funnel) and "which
-- errors does this event have" (crash triage).
CREATE INDEX IF NOT EXISTS telemetry_events_created_idx
  ON public.telemetry_events (created_at DESC);

CREATE INDEX IF NOT EXISTS telemetry_events_event_created_idx
  ON public.telemetry_events (event, created_at DESC);

CREATE INDEX IF NOT EXISTS telemetry_events_user_idx
  ON public.telemetry_events (user_id, created_at DESC)
  WHERE user_id IS NOT NULL;

ALTER TABLE public.telemetry_events ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.telemetry_events FROM PUBLIC, anon, authenticated;
GRANT INSERT ON public.telemetry_events TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.telemetry_events_id_seq TO service_role;

COMMENT ON TABLE public.telemetry_events IS
  'Crash and funnel events posted by the app. Service-role writes only; no client can read it.';

-- Retention. There is no cron wired to this on purpose — run it from the SQL
-- editor or a scheduled job when the table reaches whatever you consider large.
-- 90 days is long enough to compare two months of the funnel and short enough
-- that the table never becomes the biggest thing in the database.
CREATE OR REPLACE FUNCTION public.prune_telemetry(p_keep_days INTEGER DEFAULT 90)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  removed INTEGER;
BEGIN
  DELETE FROM public.telemetry_events
  WHERE created_at < now() - make_interval(days => GREATEST(p_keep_days, 1));
  GET DIAGNOSTICS removed = ROW_COUNT;
  RETURN removed;
END;
$$;

REVOKE ALL ON FUNCTION public.prune_telemetry(INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prune_telemetry(INTEGER) TO service_role;
