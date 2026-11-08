-- Trading playbook + AI-compiled strategies.
--
-- `playbooks` is the trader's own checklist: the rules they follow, the days
-- they trade and the sessions those days contain. The reminder lead time is
-- stored with it so the in-app reminder and any future email agree on one
-- number. One row per user, written by the browser under RLS because it is
-- their own reflection, not a computed result.
--
-- `backtests` gains the compiled rule spec and the rolling-window summary. A
-- custom run is only reproducible if its spec is stored beside the numbers, and
-- the same rule applies to every column here: the browser can read, never write.

CREATE TABLE IF NOT EXISTS public.playbooks (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  rules JSONB NOT NULL DEFAULT '[]'::jsonb,
  days INTEGER[] NOT NULL DEFAULT '{1,2,3,4,5}',
  sessions JSONB NOT NULL DEFAULT '[]'::jsonb,
  reminder_minutes INTEGER NOT NULL DEFAULT 60,
  reminders_enabled BOOLEAN NOT NULL DEFAULT true,
  notes TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.playbooks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "playbooks_select_own" ON public.playbooks;
CREATE POLICY "playbooks_select_own" ON public.playbooks
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "playbooks_insert_own" ON public.playbooks;
CREATE POLICY "playbooks_insert_own" ON public.playbooks
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "playbooks_update_own" ON public.playbooks;
CREATE POLICY "playbooks_update_own" ON public.playbooks
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "playbooks_delete_own" ON public.playbooks;
CREATE POLICY "playbooks_delete_own" ON public.playbooks
  FOR DELETE USING (auth.uid() = user_id);

ALTER TABLE public.backtests
  ADD COLUMN IF NOT EXISTS rule_spec JSONB,
  ADD COLUMN IF NOT EXISTS walk_forward JSONB;
