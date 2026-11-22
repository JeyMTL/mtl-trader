-- Per-object style for shared chart drawings.
--
-- Until now an object was geometry only: a rectangle was a rectangle, in
-- whatever colour the client happened to paint it. The phone's object settings
-- (and now the web desk's) let a trader pick the stroke colour, its width, a
-- dashed line, how solid a zone is filled, and whether the object is locked or
-- hidden. None of that is derivable from the anchors, so it needs a home.
--
-- It is one JSONB column with the phone's own keys — `c` (ARGB int), `w`
-- (stroke width), `d` (dashed), `f` (fill percent), `lk` (locked), `hd`
-- (hidden) — which is exactly what `DrawingLook.toJson()` already writes. The
-- two clients therefore share a vocabulary instead of each keeping its own, and
-- an object styled on one desk looks the same on the other.
--
-- `'{}'::jsonb` is the default rather than NULL: a row that predates this
-- column means "chart decides", and an empty object says that without every
-- reader having to null-check.

ALTER TABLE public.chart_drawings
  ADD COLUMN IF NOT EXISTS style JSONB NOT NULL DEFAULT '{}'::jsonb;

-- Restyling is an update to an existing object, so RLS needs nothing new: the
-- policies already scope every write to `auth.uid() = user_id`.

COMMENT ON COLUMN public.chart_drawings.style IS
  'DrawingLook JSON: c (ARGB), w (width), d (dashed), f (fill %), lk (locked), hd (hidden).';
