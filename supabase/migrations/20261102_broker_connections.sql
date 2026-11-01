-- Hosted broker sync.
--
-- A phone cannot run an MT5 Expert Advisor, so a customer whose only device is
-- the mobile app cannot push their own trades. Instead the sync service logs in
-- with the account's *investor* (read-only) password and streams history from
-- our side. This table is the customer's side of that: which account to connect,
-- and the sealed credential used to do it.
--
-- The credential is AES-256-GCM sealed in the application (`src/lib/broker-credentials.ts`)
-- before it ever reaches Postgres, so this table alone is useless without
-- SYNC_CREDENTIAL_KEY. The master/trading password is never accepted.

CREATE TABLE IF NOT EXISTS public.broker_connections (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL DEFAULT 'mt5' CHECK (provider IN ('mt5', 'mt4')),
  broker_name TEXT NOT NULL,
  server TEXT NOT NULL,
  account_login TEXT NOT NULL,
  -- `v1:<iv>:<tag>:<ciphertext>`, base64. Empty string means "wiped".
  credential_cipher TEXT NOT NULL,
  -- pending: accepted, waiting for a session
  -- connecting: a supervisor has picked it up
  -- connected: streaming
  -- failed: last attempt errored (see last_error)
  -- disconnected: the customer removed it; wipe the session
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'connecting', 'connected', 'failed', 'disconnected')),
  last_attempt_at TIMESTAMPTZ,
  last_sync_at TIMESTAMPTZ,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.broker_connections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "broker_connections_select_own" ON public.broker_connections;
CREATE POLICY "broker_connections_select_own" ON public.broker_connections
  FOR SELECT USING (auth.uid() = user_id);

-- No insert/update/delete policy, deliberately: every write goes through
-- /api/broker/connection with the service role, so a browser can neither set a
-- credential nor flip its own status to `connected`.
--
-- Column grants keep the ciphertext out of reach even for a read: a signed-in
-- user may see the connection itself but never `credential_cipher`. Without
-- this, `select *` from the anon key would hand out every sealed password.
REVOKE ALL ON public.broker_connections FROM anon, authenticated;
GRANT SELECT (
  user_id,
  provider,
  broker_name,
  server,
  account_login,
  status,
  last_attempt_at,
  last_sync_at,
  last_error,
  created_at,
  updated_at
) ON public.broker_connections TO authenticated;

CREATE INDEX IF NOT EXISTS idx_broker_connections_status
  ON public.broker_connections (status);

-- The supervisor claims work with `status = 'pending'` ordered by creation time.
CREATE INDEX IF NOT EXISTS idx_broker_connections_pending
  ON public.broker_connections (created_at)
  WHERE status = 'pending';
