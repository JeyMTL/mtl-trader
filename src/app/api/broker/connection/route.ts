import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { rateLimit } from '@/lib/rate-limit'
import { apiError, apiWarn, logEvent } from '@/lib/log'
import { readJsonBody } from '@/lib/request'
import {
  credentialKeyConfigured,
  encryptCredential,
  maskLogin,
  normalizeAccountLogin,
  normalizeBrokerName,
  normalizeServerName,
  validateInvestorPassword,
} from '@/lib/broker-credentials'

/**
 * Hosted MT5 sync connection.
 *
 * The customer hands over their account number and **investor** (read-only)
 * password once, from the phone. This route seals the password, records the
 * connection as `pending`, and from there a supervisor on our own hosts picks it
 * up, logs in, and streams closed trades to `/api/sync` exactly as a desktop
 * agent would.
 *
 *   GET    -> connection status (never the credential)
 *   POST   -> create or replace the connection
 *   DELETE -> disconnect and wipe the credential
 *
 * Nothing here ever returns the password, and the master password is rejected by
 * contract: only the investor password grants the read-only access this needs.
 */

export const runtime = 'nodejs'

const STATUS_COLUMNS =
  'provider, broker_name, server, account_login, status, last_attempt_at, last_sync_at, last_error, created_at, updated_at'

interface ConnectionRow {
  provider: string
  broker_name: string
  server: string
  account_login: string
  status: string
  last_attempt_at: string | null
  last_sync_at: string | null
  last_error: string | null
  created_at: string
  updated_at: string
}

function present(row: ConnectionRow) {
  return {
    connected: row.status === 'connected',
    provider: row.provider,
    broker: row.broker_name,
    server: row.server,
    // The full account number is the customer's own, but the UI never needs it:
    // masking keeps it off a screen share and out of a support screenshot.
    account: maskLogin(row.account_login),
    status: row.status,
    lastAttemptAt: row.last_attempt_at,
    lastSyncAt: row.last_sync_at,
    lastError: row.last_error,
    createdAt: row.created_at,
  }
}

async function loadConnection(userId: string) {
  const { data, error } = await getAdminClient()
    .from('broker_connections')
    .select(STATUS_COLUMNS)
    .eq('user_id', userId)
    .maybeSingle()

  if (error) throw new Error(error.message)
  return (data as ConnectionRow | null) ?? null
}

export async function GET(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const row = await loadConnection(user.id)
    return NextResponse.json(
      row ? present(row) : { connected: false, status: 'none' },
      { headers: { 'Cache-Control': 'no-store' } }
    )
  } catch (error: unknown) {
    return apiError('broker.connection.get', error, 500, 'Could not load the sync connection.')
  }
}

export async function POST(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    // Fail closed: without a key we cannot seal a credential, and storing one in
    // the clear is never the fallback.
    if (!credentialKeyConfigured()) {
      return NextResponse.json(
        { error: 'Automatic sync is not available yet.' },
        { status: 503 }
      )
    }

    const limit = await rateLimit(`broker-connect:${user.id}`, 10, 60 * 60 * 1000)
    if (!limit.ok) {
      return NextResponse.json(
        { error: 'Too many connection attempts. Please try again later.' },
        { status: 429, headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) } }
      )
    }

    const parsed = await readJsonBody<Record<string, unknown>>(req, { maxBytes: 16 * 1024 })
    if (!parsed.ok) return parsed.response
    const body = parsed.value

    const broker = normalizeBrokerName(body.broker)
    if (!broker) {
      return apiWarn('broker.connect.invalid_broker', 'Enter the broker name shown in MT5.', 400)
    }

    const server = normalizeServerName(body.server)
    if (!server) {
      return apiWarn(
        'broker.connect.invalid_server',
        'Enter the server exactly as MT5 shows it, for example ICMarketsSC-Live12.',
        400
      )
    }

    const login = normalizeAccountLogin(body.login)
    if (!login) {
      return apiWarn('broker.connect.invalid_login', 'The account number is digits only.', 400)
    }

    const investorPassword = validateInvestorPassword(body.investorPassword)
    if (!investorPassword) {
      return apiWarn(
        'broker.connect.invalid_password',
        'Enter your investor (read-only) password, not your trading password.',
        400
      )
    }

    const now = new Date().toISOString()
    const { error } = await getAdminClient()
      .from('broker_connections')
      .upsert(
        {
          user_id: user.id,
          provider: 'mt5',
          broker_name: broker,
          server,
          account_login: login,
          credential_cipher: encryptCredential(investorPassword),
          // Reconnecting resets the state machine: a supervisor must attempt
          // this credential fresh rather than trusting a stale `connected`.
          status: 'pending',
          last_attempt_at: now,
          last_error: null,
          updated_at: now,
        },
        { onConflict: 'user_id' }
      )

    if (error) {
      return apiError('broker.connect', error, 500, 'Could not save the connection.')
    }

    // The password and account number are deliberately absent from the log.
    logEvent('info', 'broker.connect', {
      userId: user.id,
      broker,
      server,
      account: maskLogin(login),
    })

    const row = await loadConnection(user.id)
    return NextResponse.json(
      row ? present(row) : { connected: false, status: 'pending' },
      { status: 202 }
    )
  } catch (error: unknown) {
    return apiError('broker.connect', error, 500, 'Could not save the connection.')
  }
}

export async function DELETE(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    // Wipes the credential and marks the row withdrawn in one write, so a
    // supervisor polling for work can never revive a session the customer
    // just removed. The row itself is kept: "disconnected on <date>" is useful
    // history, and it avoids resurrecting the connection on a stale page load.
    const { error } = await getAdminClient()
      .from('broker_connections')
      .update({
        credential_cipher: '',
        status: 'disconnected',
        last_error: null,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', user.id)

    if (error) {
      return apiError('broker.disconnect', error, 500, 'Could not disconnect the account.')
    }

    logEvent('info', 'broker.disconnect', { userId: user.id })
    return NextResponse.json({ connected: false, status: 'disconnected' })
  } catch (error: unknown) {
    return apiError('broker.disconnect', error, 500, 'Could not disconnect the account.')
  }
}
