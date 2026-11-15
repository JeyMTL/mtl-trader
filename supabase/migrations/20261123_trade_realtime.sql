-- Let the mobile app hear about a newly journaled trade immediately.
--
-- The supervisor journals a close in ~2 seconds; without this the app would
-- only notice on its next manual refresh. Realtime is an optimization, not the
-- only path: the app also polls every 10 seconds, so a project that has not
-- applied this migration still refreshes, just less instantly.
--
-- INSERTs carry the whole row, so no REPLICA IDENTITY change is needed. RLS is
-- enforced by Realtime using the subscriber's JWT; the client only subscribes
-- with a user filter on its own id.

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.trades;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;  -- project without the default publication
END $$;
