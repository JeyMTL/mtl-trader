-- Daily stop: the loss limit a trader commits to before the session.
--
-- The limit lives on `playbooks` because that is where the trader's own rules
-- already are, and it is read by the Day Over card, the trade form gate and the
-- `/api/day-state` route. `0` means "no rule" on both columns, so an account
-- that has not opted in behaves exactly as before.
--
-- `trading_days` stores the two things that cannot be derived from trades: the
-- trader's own debrief after a stop, and the reason they gave if they overrode
-- it. One row per user per local day (`day_key`), which is what makes the
-- override scoped to a single day rather than to the account.
--
-- Nothing here blocks a trade at the database level. Trades are also written by
-- the sync supervisor and by historical imports, which are records rather than
-- decisions, so the gate belongs in the journal UI and the day-state route.

ALTER TABLE public.playbooks
  ADD COLUMN IF NOT EXISTS daily_loss_limit NUMERIC NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS max_trades_per_day INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS lock_mode TEXT NOT NULL DEFAULT 'off';

COMMENT ON COLUMN public.playbooks.daily_loss_limit IS
  'Loss budget for one trading day, in the account currency. 0 disables the daily stop.';
COMMENT ON COLUMN public.playbooks.max_trades_per_day IS
  'Most entries allowed in one trading day. 0 disables the cap.';
COMMENT ON COLUMN public.playbooks.lock_mode IS
  'off = journal only; soft = the guard EA freezes MT5, journal stays open and can override; hard = freezes MT5 and the journal until the reset.';

-- Re-runnable: `ADD CONSTRAINT` has no IF NOT EXISTS.
DO $$
BEGIN
  ALTER TABLE public.playbooks
    ADD CONSTRAINT playbooks_lock_mode_check
    CHECK (lock_mode IN ('off', 'soft', 'hard'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.trading_days (
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  -- Local calendar day, `YYYY-MM-DD`, in `timezone` below.
  day_key TEXT NOT NULL,
  -- The zone the day was measured in, so a later timezone change cannot move it.
  timezone TEXT NOT NULL DEFAULT 'UTC',
  -- Snapshot of the day when the trader answered the debrief.
  stopped_pnl NUMERIC,
  stopped_at TIMESTAMPTZ,
  debrief_followed BOOLEAN,
  debrief_valid BOOLEAN,
  debrief_note TEXT NOT NULL DEFAULT '',
  override_reason TEXT,
  override_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, day_key)
);

ALTER TABLE public.trading_days ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "trading_days_select_own" ON public.trading_days;
CREATE POLICY "trading_days_select_own" ON public.trading_days
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "trading_days_insert_own" ON public.trading_days;
CREATE POLICY "trading_days_insert_own" ON public.trading_days
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "trading_days_update_own" ON public.trading_days;
CREATE POLICY "trading_days_update_own" ON public.trading_days
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "trading_days_delete_own" ON public.trading_days;
CREATE POLICY "trading_days_delete_own" ON public.trading_days
  FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_trading_days_user_day
  ON public.trading_days (user_id, day_key);
