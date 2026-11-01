-- Session filter for the trade log
--
-- The journal can now be narrowed to one trading session, using the same UTC
-- windows the chart shades. A trade is placed by the hour it was opened, in UTC:
-- converting to each user's zone would move the Asian open into their afternoon
-- and mean the filter matched different trades for different people.
--
-- p_session accepts 'asian', 'london', 'newyork', 'sydney', or null / 'all'. An
-- unknown value filters nothing rather than matching nothing, so an older client
-- sending a name this function has not learned about still gets its rows back
-- instead of an empty journal.
--
-- Trades with no open_time cannot be placed in a session and are excluded while
-- a session filter is active. Nothing changes for the other filters.
--
-- Recreating the function with a longer argument list would leave the four
-- argument version in place as an overload, and PostgREST answers a call that
-- fits both with PGRST203 ("ambiguous function") rather than choosing one. The
-- old signature is dropped first, and the web dashboard keeps working because
-- every new argument has a default.

DROP FUNCTION IF EXISTS public.trade_page(INTEGER, INTEGER, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.trade_page(
  p_limit INTEGER DEFAULT 25,
  p_offset INTEGER DEFAULT 0,
  p_search TEXT DEFAULT NULL,
  p_filter TEXT DEFAULT 'all',
  p_session TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  -- The UTC hour has to be computed in its own step: an output alias cannot be
  -- referenced from the WHERE clause that defines it.
  WITH scoped AS (
    SELECT *,
      EXTRACT(HOUR FROM (open_time AT TIME ZONE 'UTC'))::INT AS utc_hour
    FROM public.trades
    WHERE user_id = auth.uid()
      AND (
        p_search IS NULL OR btrim(p_search) = ''
        OR symbol ILIKE '%' || btrim(p_search) || '%'
        OR COALESCE(strategy, '') ILIKE '%' || btrim(p_search) || '%'
        OR EXISTS (
          SELECT 1
          FROM unnest(COALESCE(tags, ARRAY[]::TEXT[])) AS tag
          WHERE tag ILIKE '%' || btrim(p_search) || '%'
        )
      )
      AND (p_filter IS DISTINCT FROM 'wins' OR pnl > 0)
      AND (p_filter IS DISTINCT FROM 'losses' OR pnl < 0)
  ), filtered AS (
    SELECT *
    FROM scoped s
    WHERE (
      p_session IS NULL
      OR btrim(p_session) = ''
      OR lower(btrim(p_session)) = 'all'
      OR CASE lower(btrim(p_session))
        -- Sydney opens the week's trading and runs past UTC midnight.
        WHEN 'sydney' THEN (s.utc_hour >= 21 OR s.utc_hour < 6)
        WHEN 'asian' THEN (s.utc_hour >= 0 AND s.utc_hour < 9)
        WHEN 'london' THEN (s.utc_hour >= 7 AND s.utc_hour < 16)
        WHEN 'newyork' THEN (s.utc_hour >= 12 AND s.utc_hour < 21)
        ELSE TRUE
      END
    )
  ), page AS (
    SELECT f.*, COALESCE(f.close_time, f.open_time, f.created_at) AS sort_key
    FROM filtered f
    ORDER BY COALESCE(f.close_time, f.open_time, f.created_at) DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 25), 1), 200)
    OFFSET GREATEST(COALESCE(p_offset, 0), 0)
  ), enriched AS (
    SELECT p.*,
      (SELECT COUNT(*)::INT FROM public.trade_attachments a
        WHERE a.trade_id = p.id AND a.user_id = auth.uid() AND a.kind = 'image') AS image_count,
      (SELECT COUNT(*)::INT FROM public.trade_attachments a
        WHERE a.trade_id = p.id AND a.user_id = auth.uid() AND a.kind = 'audio') AS audio_count
    FROM page p
  )
  SELECT jsonb_build_object(
    'total', (SELECT COUNT(*) FROM filtered),
    'total_pnl', COALESCE((SELECT SUM(pnl) FROM filtered), 0),
    'trades', COALESCE(
      -- utc_hour is an internal column; strip it so the payload shape the
      -- clients already parse stays exactly as it was.
      (SELECT jsonb_agg(
          to_jsonb(enriched) - 'sort_key' - 'utc_hour'
          ORDER BY enriched.sort_key DESC
        ) FROM enriched),
      '[]'::jsonb
    )
  );
$$;

REVOKE ALL ON FUNCTION public.trade_page(INTEGER, INTEGER, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.trade_page(INTEGER, INTEGER, TEXT, TEXT, TEXT) TO authenticated, service_role;
