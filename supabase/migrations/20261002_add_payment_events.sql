-- ============================================================
-- payment_events — idempotent record of processed paid orders
-- ============================================================
-- Each PayPal capture (and, later, bank payment) is recorded once, keyed by the
-- provider event id. Reconciliation reads this table to avoid re-applying an
-- order, and it doubles as an audit trail of what was applied vs skipped.
--
-- Writes happen only through server-side routes using the service role, which
-- bypasses RLS. Users may read their own rows.

CREATE TABLE IF NOT EXISTS payment_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  provider TEXT NOT NULL DEFAULT 'paypal',
  provider_event_id TEXT NOT NULL,
  plan_id TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  status TEXT NOT NULL DEFAULT 'applied',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- One row per provider event: the unique index is what makes reconciliation safe.
CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_events_provider_event
  ON payment_events (provider, provider_event_id);

CREATE INDEX IF NOT EXISTS idx_payment_events_user
  ON payment_events (user_id, created_at);

ALTER TABLE payment_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own payment events" ON payment_events;
CREATE POLICY "Users can view own payment events" ON payment_events
  FOR SELECT USING (auth.uid() = user_id);
