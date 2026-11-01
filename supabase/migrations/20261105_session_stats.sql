-- Per-session totals, for the journal strip and the analytics table
--
-- Same four UTC windows, and the same comparison, as `trade_page`'s p_session
-- argument (migration 20261104), so a session's number here is the number the
-- filter would show. They are duplicated deliberately: an aggregate over every
-- trade is cheap in SQL and expensive as a page of rows dragged to the client.
--
-- A trade can land in two windows at once — London and New York both claim
-- 12:00–16:00 UTC — and it is counted in both, exactly as filtering by either
-- session would count it. Summing the rows is therefore not the account total,
-- and never was: the overlap is real, not double counting.
--
-- Trades with no open_time cannot be placed in a session and are left out; the
-- unfiltered journal still shows them.
--
-- Sessions with no trades are absent from the array rather than returned as
-- zeroes, so a client can tell "no trades yet" from "not loaded".

CREATE OR REPLACE FUNCTION public.session_stats()
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  WITH windows(session, first_hour, last_hour) AS (
    VALUES
      ('sydney', 21, 6),
      ('asian', 0, 9),
      ('london', 7, 16),
      ('newyork', 12, 21)
  ), scoped AS (
    SELECT
      pnl,
      EXTRACT(HOUR FROM (open_time AT TIME ZONE 'UTC'))::INT AS utc_hour
    FROM public.trades
    WHERE user_id = auth.uid()
      AND open_time IS NOT NULL
  ), buckets AS (
    SELECT w.session, s.pnl
    FROM windows w
    JOIN scoped s ON (
      CASE
        WHEN w.first_hour < w.last_hour
          THEN s.utc_hour >= w.first_hour AND s.utc_hour < w.last_hour
        ELSE s.utc_hour >= w.first_hour OR s.utc_hour < w.last_hour
      END
    )
  )
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'session', session,
        'trades', trades,
        'wins', wins,
        'losses', losses,
        'pnl', pnl
      )
      ORDER BY session
    ),
    '[]'::jsonb
  )
  FROM (
    SELECT
      session,
      COUNT(*)::INT AS trades,
      COUNT(*) FILTER (WHERE pnl > 0)::INT AS wins,
      COUNT(*) FILTER (WHERE pnl < 0)::INT AS losses,
      COALESCE(SUM(pnl), 0) AS pnl
    FROM buckets
    GROUP BY session
  ) totals;
$$;

REVOKE ALL ON FUNCTION public.session_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.session_stats() TO authenticated, service_role;
