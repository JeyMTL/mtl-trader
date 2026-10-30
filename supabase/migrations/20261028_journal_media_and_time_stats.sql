-- ============================================================
-- Journal media + time-of-day performance
-- Idempotent: safe to re-run.
-- ------------------------------------------------------------
-- 1. Photos and voice notes attach to a trade (the journal entry).
-- 2. `time_stats` reports which hours and sessions pay and which lose,
--    in the user's own timezone.
-- 3. `journal_feed` powers the dashboard journal panel.
-- 4. `trade_page` now reports attachment counts so the trade log can
--    show that an entry carries a photo or a recording.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Attachments
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.trade_attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  trade_id UUID NOT NULL REFERENCES public.trades(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('image', 'audio')),
  storage_path TEXT NOT NULL,
  file_name TEXT,
  mime_type TEXT,
  size_bytes BIGINT,
  duration_seconds NUMERIC,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_trade_attachments_trade
  ON public.trade_attachments (trade_id, created_at);
CREATE INDEX IF NOT EXISTS idx_trade_attachments_user
  ON public.trade_attachments (user_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_trade_attachments_path
  ON public.trade_attachments (storage_path);

ALTER TABLE public.trade_attachments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own attachments" ON public.trade_attachments;
CREATE POLICY "Users can view own attachments" ON public.trade_attachments
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own attachments" ON public.trade_attachments;
CREATE POLICY "Users can insert own attachments" ON public.trade_attachments
  FOR INSERT WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.trades t
      WHERE t.id = trade_id AND t.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can update own attachments" ON public.trade_attachments;
CREATE POLICY "Users can update own attachments" ON public.trade_attachments
  FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own attachments" ON public.trade_attachments;
CREATE POLICY "Users can delete own attachments" ON public.trade_attachments
  FOR DELETE USING (auth.uid() = user_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.trade_attachments TO authenticated;

-- ------------------------------------------------------------
-- 2. Private storage bucket. Paths are `<user_id>/<...>` so the
--    folder check is enough to keep journals apart.
-- ------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'journal-media',
  'journal-media',
  false,
  26214400, -- 25 MB
  ARRAY[
    'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif',
    'audio/webm', 'audio/ogg', 'audio/mpeg', 'audio/mp4', 'audio/wav',
    'audio/x-wav', 'audio/x-m4a', 'audio/m4a', 'audio/aac'
  ]
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Journal media read" ON storage.objects;
CREATE POLICY "Journal media read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'journal-media'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Journal media insert" ON storage.objects;
CREATE POLICY "Journal media insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'journal-media'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Journal media update" ON storage.objects;
CREATE POLICY "Journal media update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'journal-media'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Journal media delete" ON storage.objects;
CREATE POLICY "Journal media delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'journal-media'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- ------------------------------------------------------------
-- 3. Time-of-day and session performance
--    Entries are bucketed by when the trade was opened (the decision),
--    converted to the user's timezone. Trades without an open time fall
--    back to the close time, then to the row's creation time.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.time_stats()
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  WITH zone AS (
    SELECT COALESCE(NULLIF(btrim(timezone), ''), 'UTC') AS name
    FROM public.users
    WHERE id = auth.uid()
  ), scoped AS (
    SELECT
      pnl,
      COALESCE(open_time, close_time, created_at)
        AT TIME ZONE COALESCE((SELECT name FROM zone), 'UTC') AS local_entry,
      COALESCE(open_time, close_time, created_at)
        AT TIME ZONE 'UTC' AS utc_entry,
      CASE
        WHEN open_time IS NOT NULL AND close_time IS NOT NULL
          THEN GREATEST(EXTRACT(EPOCH FROM (close_time - open_time)) / 60.0, 0)
        ELSE NULL
      END AS hold_minutes
    FROM public.trades
    WHERE user_id = auth.uid()
  ), hours AS (
    SELECT
      EXTRACT(HOUR FROM local_entry)::INT AS hour,
      COUNT(*)::INT AS trades,
      COUNT(*) FILTER (WHERE pnl > 0)::INT AS wins,
      COUNT(*) FILTER (WHERE pnl < 0)::INT AS losses,
      COALESCE(SUM(pnl), 0)::NUMERIC AS pnl
    FROM scoped
    GROUP BY 1
  ), sessions AS (
    -- Market sessions are UTC-based; hours above stay in the user's timezone.
    SELECT
      CASE
        WHEN EXTRACT(HOUR FROM utc_entry) < 8 THEN 'Asian'
        WHEN EXTRACT(HOUR FROM utc_entry) < 13 THEN 'London'
        WHEN EXTRACT(HOUR FROM utc_entry) < 16 THEN 'London / New York'
        WHEN EXTRACT(HOUR FROM utc_entry) < 21 THEN 'New York'
        ELSE 'Late'
      END AS session,
      MIN(EXTRACT(HOUR FROM utc_entry))::INT AS first_hour,
      MAX(EXTRACT(HOUR FROM utc_entry))::INT AS last_hour,
      COUNT(*)::INT AS trades,
      COUNT(*) FILTER (WHERE pnl > 0)::INT AS wins,
      COUNT(*) FILTER (WHERE pnl < 0)::INT AS losses,
      COALESCE(SUM(pnl), 0)::NUMERIC AS pnl
    FROM scoped
    GROUP BY 1
  ), holds AS (
    SELECT
      COUNT(*)::INT AS trades,
      ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY hold_minutes))::NUMERIC, 1) AS median_minutes,
      ROUND(AVG(hold_minutes)::NUMERIC, 1) AS average_minutes
    FROM scoped
    WHERE hold_minutes IS NOT NULL
  )
  SELECT jsonb_build_object(
    'timezone', COALESCE((SELECT name FROM zone), 'UTC'),
    'hours', COALESCE(
      (SELECT jsonb_agg(to_jsonb(hours) ORDER BY hour) FROM hours),
      '[]'::jsonb
    ),
    'sessions', COALESCE(
      (SELECT jsonb_agg(to_jsonb(sessions) ORDER BY first_hour) FROM sessions),
      '[]'::jsonb
    ),
    'hold', COALESCE((SELECT to_jsonb(holds) FROM holds), '{"trades":0,"median_minutes":null,"average_minutes":null}'::jsonb)
  );
$$;

REVOKE ALL ON FUNCTION public.time_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.time_stats() TO authenticated, service_role;

-- ------------------------------------------------------------
-- 4. Latest journal entries (notes and/or media), for the dashboard
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.journal_feed(p_limit INTEGER DEFAULT 6)
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  WITH scoped AS (
    SELECT
      t.id, t.symbol, t.type, t.pnl, t.strategy, t.notes, t.tags,
      t.open_time, t.close_time, t.created_at,
      COALESCE(t.close_time, t.open_time, t.created_at) AS sort_key
    FROM public.trades t
    WHERE t.user_id = auth.uid()
      AND (
        NULLIF(btrim(COALESCE(t.notes, '')), '') IS NOT NULL
        OR EXISTS (
          SELECT 1 FROM public.trade_attachments a
          WHERE a.trade_id = t.id AND a.user_id = auth.uid()
        )
      )
    ORDER BY COALESCE(t.close_time, t.open_time, t.created_at) DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 6), 1), 20)
  )
  SELECT COALESCE(
    jsonb_agg(
      (to_jsonb(s) - 'sort_key') || jsonb_build_object(
        'image_count', (
          SELECT COUNT(*)::INT FROM public.trade_attachments a
          WHERE a.trade_id = s.id AND a.user_id = auth.uid() AND a.kind = 'image'
        ),
        'audio_count', (
          SELECT COUNT(*)::INT FROM public.trade_attachments a
          WHERE a.trade_id = s.id AND a.user_id = auth.uid() AND a.kind = 'audio'
        ),
        'attachments', COALESCE((
          SELECT jsonb_agg(
            jsonb_build_object(
              'id', a.id,
              'kind', a.kind,
              'mime_type', a.mime_type,
              'duration_seconds', a.duration_seconds
            ) ORDER BY a.created_at
          )
          FROM public.trade_attachments a
          WHERE a.trade_id = s.id AND a.user_id = auth.uid()
        ), '[]'::jsonb)
      )
      ORDER BY s.sort_key DESC
    ),
    '[]'::jsonb
  )
  FROM scoped s;
$$;

REVOKE ALL ON FUNCTION public.journal_feed(INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.journal_feed(INTEGER) TO authenticated, service_role;

-- ------------------------------------------------------------
-- 5. Trade list carries its attachment counts
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
      (SELECT jsonb_agg(to_jsonb(enriched) - 'sort_key' ORDER BY enriched.sort_key DESC) FROM enriched),
      '[]'::jsonb
    )
  );
$$;

REVOKE ALL ON FUNCTION public.trade_page(INTEGER, INTEGER, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.trade_page(INTEGER, INTEGER, TEXT, TEXT) TO authenticated, service_role;
