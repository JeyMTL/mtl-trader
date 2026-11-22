-- Chart templates: a named canvas look, owned by a user and shared by both desks.
--
-- A template is the paint only — colours, grid, crosshair, studies, clock — and
-- no instrument or interval, so it can be stamped onto whichever chart is open.
-- The phone has kept these in SharedPreferences and the web desk in
-- localStorage; this table is the copy that makes "MTL" mean the same look on
-- both.
--
-- `style` is the phone's own `ChartStyle.toJson()` object, unaltered: the phone
-- is the older client and the one with the longer settings list, so its keys are
-- the vocabulary. The web desk reads the subset it can paint and writes the rest
-- back untouched, which is what keeps a phone-only setting (a study period, the
-- watermark) from being erased by a save made in a browser.
--
-- `slug` is the case-insensitive identity of a name. It exists as a plain column
-- rather than a `lower(name)` unique index because both clients upsert with
-- PostgREST's `on_conflict`, which names columns: a unique index on an
-- expression cannot be targeted by an upsert. Keeping the slug in the row means
-- "MTL" and "mtl" are one template on every device.

CREATE TABLE IF NOT EXISTS public.chart_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES public.users(id) ON DELETE CASCADE,
  slug TEXT NOT NULL,
  name TEXT NOT NULL,
  style JSONB NOT NULL DEFAULT '{}'::jsonb,
  -- Client-supplied edit time: an offline phone pushing this afternoon's save
  -- must not claim to be newer than a save made tonight, and a server-side
  -- `now()` would make it look like it did.
  edited_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chart_templates_name_length CHECK (char_length(btrim(name)) BETWEEN 1 AND 30),
  CONSTRAINT chart_templates_slug_matches_name CHECK (slug = lower(btrim(name))),
  CONSTRAINT chart_templates_user_slug_key UNIQUE (user_id, slug)
);

CREATE INDEX IF NOT EXISTS idx_chart_templates_user_edited
  ON public.chart_templates (user_id, edited_at DESC);

ALTER TABLE public.chart_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own chart templates" ON public.chart_templates;
CREATE POLICY "Users can view own chart templates" ON public.chart_templates
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own chart templates" ON public.chart_templates;
CREATE POLICY "Users can insert own chart templates" ON public.chart_templates
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own chart templates" ON public.chart_templates;
CREATE POLICY "Users can update own chart templates" ON public.chart_templates
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own chart templates" ON public.chart_templates;
CREATE POLICY "Users can delete own chart templates" ON public.chart_templates
  FOR DELETE USING (auth.uid() = user_id);

-- No `BEFORE UPDATE` trigger: `edited_at` is the client's claim about when the
-- look was changed, and overwriting it here would break the merge both clients
-- rely on.
