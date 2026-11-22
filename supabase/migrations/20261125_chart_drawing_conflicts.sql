-- Edit-time conflict resolution for shared chart drawings.
--
-- `updated_at` records when a row was *written*, which is a property of the
-- network rather than of the trader. Two devices editing the same level need to
-- know which edit happened later in real life, even when the older one reaches
-- the table last — an offline phone syncing at midnight must not overwrite the
-- level moved on the web desk that afternoon.
--
-- So every write now carries `edited_at`: the moment the trader made the change.
-- Both clients compare it and the later edit stands, with the content signature
-- as a tie-break so two devices always converge on the same winner.

ALTER TABLE public.chart_drawings
  ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_chart_drawings_edited_at
  ON public.chart_drawings (user_id, symbol, edited_at);

-- A device with a badly set clock should not be able to own a level forever by
-- editing it "in 2031". Anything more than ten minutes ahead is treated as now.
CREATE OR REPLACE FUNCTION public.clamp_chart_drawing_edit()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.edited_at > now() + interval '10 minutes' THEN
    NEW.edited_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chart_drawings_clamp_edit ON public.chart_drawings;
CREATE TRIGGER chart_drawings_clamp_edit
  BEFORE INSERT OR UPDATE ON public.chart_drawings
  FOR EACH ROW EXECUTE FUNCTION public.clamp_chart_drawing_edit();
