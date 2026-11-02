-- ============================================================
-- Per-strategy performance for the analytics page.
--
-- The label is free text typed on the journal form, so it is grouped
-- trimmed and case-sensitive: "SMA cross" and "sma cross" are two rows.
-- That is deliberate — the page cannot guess which of the trader's
-- spellings mean the same thing, and silently merging them would merge
-- two different strategies that happen to share a name.
--
-- Empty labels are grouped as 'Untagged' rather than dropped, because a
-- blank strategy is common and hiding it would overstate the numbers of
-- everything else.
--
-- Idempotent: safe to re-run.
-- ============================================================

CREATE OR REPLACE FUNCTION public.strategy_stats(p_limit INTEGER DEFAULT 20)
RETURNS TABLE (
  strategy TEXT,
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
    COALESCE(NULLIF(btrim(tr.strategy), ''), 'Untagged') AS strategy,
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
  WHERE tr.user_id = auth.uid()
  GROUP BY COALESCE(NULLIF(btrim(tr.strategy), ''), 'Untagged')
  ORDER BY pnl DESC, trades DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
$$;

REVOKE ALL ON FUNCTION public.strategy_stats(INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.strategy_stats(INTEGER) TO authenticated, service_role;
