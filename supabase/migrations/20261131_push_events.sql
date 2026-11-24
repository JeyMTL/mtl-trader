-- ============================================================
-- Notifications that must happen at most once
--
-- Trial-ending and prop-rule-breach pushes are computed from state that keeps
-- being true: a trial is inside its last day for a whole day, and a breached
-- account stays breached until the drawdown resets or the day rolls over. A
-- sweep that ran every hour without a record of what it had already said would
-- send the same sentence twelve times.
--
-- `event_key` is what makes a notification unique: the trial's end date for a
-- trial reminder, `<status>:<day>` for a breach, so a second breach of the same
-- rule on a later day is still news. The primary key is the dedupe, so a
-- duplicate insert is the signal that the send has 23505-ahead of it.
--
-- A sent row is deleted again when FCM reports it sent nothing (no service
-- account configured, no device registered), so a later attempt can still
-- deliver it rather than losing it forever.
--
-- RLS is on with no policies, like `push_tokens`: this table is written and read
-- only by the service role.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.push_events (
  user_id    uuid NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  kind       text NOT NULL,
  event_key  text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, kind, event_key)
);

CREATE INDEX IF NOT EXISTS push_events_created_idx ON public.push_events (created_at);

ALTER TABLE public.push_events ENABLE ROW LEVEL SECURITY;
