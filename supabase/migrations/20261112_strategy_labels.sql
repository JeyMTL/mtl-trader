-- ============================================================
-- Distinct strategy labels, for the journal form's suggestion chips.
--
-- The strategy field is free text, and typing it quickly produces variants of
-- the same model ("ICT Silver Bullet", "ICT SILVEE BULLET", "ict silver bullet").
-- Those become separate rows in the analytics matrix, which silently splits the
-- performance of one setup. The form offers the labels this trader has already
-- used, so the common path is tapping the existing spelling.
--
-- Labels are trimmed and grouped case-sensitively, matching `strategy_stats`:
-- merging case here would hide the duplicate instead of preventing it, and the
-- two functions must agree or the chips would suggest a label the matrix splits.
--
-- Idempotent: CREATE OR REPLACE, safe to re-run.
-- ============================================================

CREATE OR REPLACE FUNCTION public.strategy_labels(p_limit INTEGER DEFAULT 20)
RETURNS TABLE (
  label TEXT,
  trades BIGINT
)
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT
    btrim(strategy) AS label,
    COUNT(*)::BIGINT AS trades
  FROM public.trades
  WHERE user_id = auth.uid()
    AND strategy IS NOT NULL
    AND btrim(strategy) <> ''
  GROUP BY btrim(strategy)
  ORDER BY trades DESC, label ASC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
$$;

REVOKE ALL ON FUNCTION public.strategy_labels(INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.strategy_labels(INTEGER) TO authenticated, service_role;
