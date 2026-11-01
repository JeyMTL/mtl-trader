-- Reliable sync identity, convergence and tombstones.
--
-- Three defects made the old sync untrustworthy:
--   1. dedupe keyed on a *closing deal* id, which changes as a position scales
--      out, so a partially-closed trade was inserted twice with its full P&L
--      counted twice;
--   2. rows were insert-only, so a trade first seen mid-close never converged;
--   3. deleting a synced trade did not stick — the next poll re-imported it.
--
-- MT5 gives every position a stable `position_id` for its whole life, which is
-- the correct identity. Deletions are remembered in `sync_suppressions` rather
-- than by soft-deleting trades, so no read path anywhere has to learn to filter.

ALTER TABLE public.trades ADD COLUMN IF NOT EXISTS position_id BIGINT;

-- Must be a *full* unique index (no partial predicate) so PostgREST can target
-- it with `onConflict`. Multiple NULLs stay legal, which keeps CSV imports —
-- they carry no position — working exactly as before.
CREATE UNIQUE INDEX IF NOT EXISTS idx_trades_user_position
  ON public.trades (user_id, position_id);

-- The agent still reports `ticket`; index it for the pre-check that matches a
-- row imported by the previous agent version.
CREATE INDEX IF NOT EXISTS idx_trades_user_ticket_lookup
  ON public.trades (user_id, ticket) WHERE ticket IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.sync_suppressions (
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  position_id BIGINT NOT NULL,
  deleted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, position_id)
);

ALTER TABLE public.sync_suppressions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "sync_suppressions_select_own" ON public.sync_suppressions;
CREATE POLICY "sync_suppressions_select_own" ON public.sync_suppressions
  FOR SELECT USING (auth.uid() = user_id);

REVOKE ALL ON public.sync_suppressions FROM anon, authenticated;
GRANT SELECT (user_id, position_id, deleted_at)
  ON public.sync_suppressions TO authenticated;

/**
 * Remembers every synced trade the customer deletes, whatever path deleted it
 * (dashboard, mobile app, admin, account deletion RPC). A trigger is used
 * because the delete paths are many and one of them would always be missed.
 *
 * The `EXISTS` guard matters: deleting an *account* cascades into `trades`, and
 * without the guard this would try to insert a suppression for a user row that
 * is already gone and abort the whole account deletion on a foreign key.
 */
CREATE OR REPLACE FUNCTION public.record_sync_suppression()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(OLD.position_id, OLD.ticket) IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.users WHERE id = OLD.user_id) THEN
    INSERT INTO public.sync_suppressions (user_id, position_id)
    VALUES (OLD.user_id, COALESCE(OLD.position_id, OLD.ticket))
    ON CONFLICT (user_id, position_id) DO NOTHING;
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trades_record_sync_suppression ON public.trades;
CREATE TRIGGER trades_record_sync_suppression
  AFTER DELETE ON public.trades
  FOR EACH ROW EXECUTE FUNCTION public.record_sync_suppression();
