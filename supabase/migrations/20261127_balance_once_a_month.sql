-- One balance change per calendar month.
--
-- The desk reads the account as `deposits_total()` plus the journal's P&L, so a
-- balance that can be topped up at will stops measuring anything: every losing
-- month can be reset with another deposit, and the curve flatters the trader.
-- The rule is enforced here rather than in the app because the app is not the
-- only writer (the web settings page is the other), and a rule a client enforces
-- lasts until somebody opens a different client.
--
-- RESTRICTIVE narrows the existing "Users can insert own deposits" policy
-- instead of replacing it: a row has to pass both. Service-role writes bypass
-- RLS, so billing and anything the supervisor records are unaffected.
--
-- The month is UTC. `created_at` carries a time zone and is set by the server
-- clock, so the phone's timezone cannot decide whether a change is available.
--
-- The check on the new row's own `created_at` is what stops a client backdating
-- an insert to slip past the tombstone-free subquery.
DROP POLICY IF EXISTS "One balance change per month" ON public.deposits;
CREATE POLICY "One balance change per month" ON public.deposits
  AS RESTRICTIVE
  FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND created_at >= date_trunc('month', now() AT TIME ZONE 'utc') AT TIME ZONE 'utc'
    AND NOT EXISTS (
      SELECT 1
      FROM public.deposits AS existing
      WHERE existing.user_id = auth.uid()
        AND existing.created_at >=
          date_trunc('month', now() AT TIME ZONE 'utc') AT TIME ZONE 'utc'
    )
  );
