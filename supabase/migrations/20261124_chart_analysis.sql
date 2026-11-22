-- Shared chart analysis: drawings pinned to a symbol, owned by a user.
--
-- The phone keeps its objects on the device today (shared_preferences per
-- symbol). This table is the cross-device copy: same `kind` names as the Flutter
-- `DrawingKind` enum (`ray`, `trend`, `fib`, `fibExtension`, `rectangle`,
-- `ellipse`, `vline`, `text`, `measure`, `brush`, `arrowUp`, `arrowDown`) and
-- the same `points` shape — a JSON array of `{ t, p }`, epoch milliseconds and
-- price. Storing the points rather than start/end columns is what lets one table
-- carry a two-anchor shape, a fib ladder and a freehand stroke alike.
--
-- RLS is ownership-only, exactly like `trades`: every policy compares
-- `auth.uid()` to `user_id`, so a drawing can never be read or written for
-- another account, and the service role keeps full access for admin work.

CREATE TABLE IF NOT EXISTS public.chart_drawings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- `auth.uid()` as the default is what lets both clients insert without
  -- naming the owner, and it is the same value the RLS policy checks, so the
  -- two can never disagree.
  user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES public.users(id) ON DELETE CASCADE,
  symbol TEXT NOT NULL,
  kind TEXT NOT NULL,
  points JSONB NOT NULL DEFAULT '[]'::jsonb,
  text TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Every read is "this user's objects on this symbol".
CREATE INDEX IF NOT EXISTS idx_chart_drawings_user_symbol
  ON public.chart_drawings (user_id, symbol, created_at);

ALTER TABLE public.chart_drawings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own chart drawings" ON public.chart_drawings;
CREATE POLICY "Users can view own chart drawings" ON public.chart_drawings
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own chart drawings" ON public.chart_drawings;
CREATE POLICY "Users can insert own chart drawings" ON public.chart_drawings
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own chart drawings" ON public.chart_drawings;
CREATE POLICY "Users can update own chart drawings" ON public.chart_drawings
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own chart drawings" ON public.chart_drawings;
CREATE POLICY "Users can delete own chart drawings" ON public.chart_drawings
  FOR DELETE USING (auth.uid() = user_id);

-- `updated_at` is the tie-breaker a future merge needs when the same symbol is
-- edited on two devices.
CREATE OR REPLACE FUNCTION public.touch_chart_drawing()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chart_drawings_touch ON public.chart_drawings;
CREATE TRIGGER chart_drawings_touch
  BEFORE UPDATE ON public.chart_drawings
  FOR EACH ROW EXECUTE FUNCTION public.touch_chart_drawing();
