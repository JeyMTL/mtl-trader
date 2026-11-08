-- The trader's standing definition of an acceptable setup, for the custom
-- backtest compiler.
--
-- The compiler is stateless by design: every compile sees only what the browser
-- sends with it. That is right for reproducibility, but it means a trader
-- explaining "what I count as a valid fair value gap" had to retype it every
-- time. This column is the one place those words are kept, so the backtest panel
-- can load them, show them back, and send them with each description.
--
-- It lives on `playbooks` because it is the same kind of thing the rest of that
-- row already is: the trader's own reflection on how they trade. The browser
-- writes it under the existing RLS policies, and no server route writes here.

ALTER TABLE public.playbooks
  ADD COLUMN IF NOT EXISTS backtest_brief TEXT NOT NULL DEFAULT '';

COMMENT ON COLUMN public.playbooks.backtest_brief IS
  'What the trader counts as an acceptable setup. Sent with every AI strategy compile.';
