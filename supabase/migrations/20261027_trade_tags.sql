-- ============================================================
-- Tags, end to end: searchable in the trade log, and summarised
-- for the analytics "Performance by tag" section.
-- Idempotent: safe to re-run.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Trade log search now includes tags
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trade_page(
  p_limit INTEGER DEFAULT 25,
  p_offset INTEGER DEFAULT 0,
  p_search TEXT DEFAULT NULL,
  p_filter TEXT DEFAULT 'all'
)
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  WITH filtered AS (
    SELECT *
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
  ), page AS (
    SELECT f.*, COALESCE(f.close_time, f.open_time, f.created_at) AS sort_key
    FROM filtered f
    ORDER BY COALESCE(f.close_time, f.open_time, f.created_at) DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 25), 1), 200)
    OFFSET GREATEST(COALESCE(p_offset, 0), 0)
  )
  SELECT jsonb_build_object(
    'total', (SELECT COUNT(*) FROM filtered),
    'total_pnl', COALESCE((SELECT SUM(pnl) FROM filtered), 0),
    'trades', COALESCE((SELECT jsonb_agg(to_jsonb(page) - 'sort_key' ORDER BY page.sort_key DESC) FROM page), '[]'::jsonb)
  );
$$;

REVOKE ALL ON FUNCTION public.trade_page(INTEGER, INTEGER, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.trade_page(INTEGER, INTEGER, TEXT, TEXT) TO authenticated, service_role;

-- ------------------------------------------------------------
-- 2. Per-tag performance
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tag_stats(p_limit INTEGER DEFAULT 12)
RETURNS TABLE (
  tag TEXT,
  trades BIGINT,
  wins BIGINT,
  losses BIGINT,
  pnl NUMERIC,
  win_rate NUMERIC
)
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT
    t.tag,
    COUNT(*)::BIGINT AS trades,
    COUNT(*) FILTER (WHERE tr.pnl > 0)::BIGINT AS wins,
    COUNT(*) FILTER (WHERE tr.pnl < 0)::BIGINT AS losses,
    COALESCE(SUM(tr.pnl), 0)::NUMERIC AS pnl,
    CASE
      WHEN COUNT(*) > 0
        THEN ROUND((COUNT(*) FILTER (WHERE tr.pnl > 0))::NUMERIC / COUNT(*) * 100, 1)
      ELSE 0
    END AS win_rate
  FROM public.trades AS tr
  CROSS JOIN LATERAL unnest(COALESCE(tr.tags, ARRAY[]::TEXT[])) AS t(tag)
  WHERE tr.user_id = auth.uid()
  GROUP BY t.tag
  ORDER BY pnl DESC, trades DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 12), 1), 50);
$$;

REVOKE ALL ON FUNCTION public.tag_stats(INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tag_stats(INTEGER) TO authenticated, service_role;
