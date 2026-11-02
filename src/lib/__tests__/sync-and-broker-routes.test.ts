import { describe, it, expect, beforeEach, vi } from 'vitest'

type Row = Record<string, unknown>

const state = vi.hoisted(() => ({
  authUser: { id: 'u1', email: 'trader@example.com', email_confirmed_at: '2026-01-01T00:00:00Z' } as Row | null,
  agentToken: 'token-abc',
  emailConfirmed: true,
  trades: [] as Row[],
  suppressions: [] as number[],
  upserted: [] as Row[],
  updates: [] as Row[],
  connection: null as Row | null,
  upsertError: null as { message: string } | null,
  // The sync route now checks entitlement, so the mocked account has to be a
  // live Pro one; otherwise every ingest test would be refused with 402.
  account: {
    subscription_tier: 'pro',
    subscription_status: 'active',
    trial_ends_at: null,
    max_trades: -1,
    current_period_end: new Date(Date.now() + 30 * 86_400_000).toISOString(),
    cancel_at_period_end: false,
  } as Row,
}))

/** A tiny stand-in for the Supabase query builder, recording thenable calls. */
function chain(table: string) {
  const calls: { method: string; args: unknown[] }[] = []
  const build: Record<string, unknown> = {
    calls,
    select: (...args: unknown[]) => (calls.push({ method: 'select', args }), build),
    eq: (...args: unknown[]) => (calls.push({ method: 'eq', args }), build),
    in: (...args: unknown[]) => (calls.push({ method: 'in', args }), build),
    update: (...args: unknown[]) => (calls.push({ method: 'update', args }), build),
    upsert: (...args: unknown[]) => (calls.push({ method: 'upsert', args }), build),
    maybeSingle: async () => single(table, calls),
    then: (resolve: (v: unknown) => unknown, reject: (e: unknown) => unknown) =>
      Promise.resolve(awaited(table, calls)).then(resolve, reject),
  }
  return build
}

function single(table: string, calls: { method: string; args: unknown[] }[]) {
  if (table === 'users') {
    return state.authUser
      ? { data: { id: 'u1', agent_token: state.agentToken, ...state.account }, error: null }
      : { data: null, error: null }
  }
  if (table === 'broker_connections') return { data: state.connection, error: null }
  return { data: null, error: null }
}

function awaited(table: string, calls: { method: string; args: unknown[] }[]) {
  const upsert = calls.find((c) => c.method === 'upsert')
  if (upsert) {
    const payload = upsert.args[0] as Row | Row[]
    const rows = Array.isArray(payload) ? payload : [payload]
    if (state.upsertError) return { data: null, error: state.upsertError }

    if (table === 'broker_connections') {
      const now = new Date().toISOString()
      state.connection = {
        provider: 'mt5',
        created_at: now,
        updated_at: now,
        last_attempt_at: now,
        last_sync_at: null,
        last_error: null,
        ...rows[0],
      }
      return { data: null, error: null }
    }

    // Insert only the positions not already stored, mirroring ignoreDuplicates.
    const known = new Set(state.trades.map((row) => Number(row.position_id)))
    const fresh = rows.filter((row) => !known.has(Number(row.position_id)))
    for (const row of fresh) state.trades.push(row)
    state.upserted.push(...fresh)
    return { data: fresh.map((_, index) => ({ id: `new-${index}` })), error: null }
  }

  const update = calls.find((c) => c.method === 'update')
  if (update) {
    state.updates.push(update.args[0] as Row)
    if (table === 'broker_connections' && state.connection) {
      state.connection = { ...state.connection, ...(update.args[0] as Row) }
    }
    return { error: null }
  }

  const select = calls.find((c) => c.method === 'select')
  const column = (select?.args[0] as string) ?? ''
  if (table === 'trades') {
    if (column === 'position_id') {
      return { data: state.trades.filter((r) => r.position_id != null).map((r) => ({ position_id: r.position_id })), error: null }
    }
    if (column === 'ticket') {
      return { data: state.trades.filter((r) => r.ticket != null).map((r) => ({ ticket: r.ticket })), error: null }
    }
    return { data: [], error: null }
  }
  if (table === 'sync_suppressions') {
    return { data: state.suppressions.map((position_id) => ({ position_id })), error: null }
  }
  return { data: [], error: null }
}

vi.mock('@/lib/server-auth', () => ({
  getAdminClient: () => ({
    from: (table: string) => chain(table),
    auth: {
      admin: {
        getUserById: async () => ({
          data: { user: state.emailConfirmed ? state.authUser : null },
          error: null,
        }),
      },
    },
  }),
  getAuthUser: async () => state.authUser,
}))

vi.mock('@/lib/rate-limit', () => ({
  rateLimit: async () => ({ ok: true, remaining: 999, retryAfterMs: 0 }),
  clientKey: () => 'test',
  sweepExpired: () => {},
}))

const KEY = Buffer.alloc(32, 7).toString('base64')

function closedTrade(over: Row = {}): Row {
  return {
    position_id: 101,
    ticket: 9001,
    symbol: 'EURUSD',
    type: 'BUY',
    entry_price: 1.1,
    exit_price: 1.12,
    lot_size: 0.1,
    pnl: 20,
    open_time: '2026-10-01T10:00:00Z',
    close_time: '2026-10-01T12:00:00Z',
    ...over,
  }
}

async function postSync(body: Row, token = 'token-abc'): Promise<Response> {
  const { POST } = await import('@/app/api/sync/route')
  return POST(
    new Request('http://localhost/api/sync', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ userId: 'u1', token, ...body }),
    })
  )
}

beforeEach(() => {
  state.authUser = { id: 'u1', email: 'trader@example.com', email_confirmed_at: '2026-01-01T00:00:00Z' }
  state.agentToken = 'token-abc'
  // Individual tests replace the account; reset so ordering cannot decide
  // whether an ingest test is entitled.
  state.account = {
    subscription_tier: 'pro',
    subscription_status: 'active',
    trial_ends_at: null,
    max_trades: -1,
    current_period_end: new Date(Date.now() + 30 * 86_400_000).toISOString(),
    cancel_at_period_end: false,
  }
  state.emailConfirmed = true
  state.trades = []
  state.suppressions = []
  state.upserted = []
  state.updates = []
  state.connection = null
  state.upsertError = null
  state.account = {
    ...state.account,
    subscription_tier: 'pro',
    subscription_status: 'active',
    trial_ends_at: null,
    max_trades: -1,
    current_period_end: new Date(Date.now() + 30 * 86_400_000).toISOString(),
  }
  process.env.SYNC_CREDENTIAL_KEY = KEY
  delete process.env.SYNC_SUPERVISOR_TOKEN
})

describe('sync ingest', () => {
  it('imports a closed position', async () => {
    const res = await postSync({ trades: [closedTrade()] })
    expect(res.status).toBe(200)
    expect((await res.json()).imported).toBe(1)
    expect(state.upserted).toHaveLength(1)
    expect(state.upserted[0]).toMatchObject({ position_id: 101, user_id: 'u1', symbol: 'EURUSD' })
  })

  it('collapses two observations of the same position into one row', async () => {
    const res = await postSync({
      trades: [closedTrade({ ticket: 9001, pnl: 5 }), closedTrade({ ticket: 9002, pnl: 20 })],
    })
    expect((await res.json()).imported).toBe(1)
    expect(state.upserted).toHaveLength(1)
    // The later observation carries the final P&L for the whole position.
    expect(state.upserted[0].pnl).toBe(20)
  })

  it('ignores a re-sent batch instead of duplicating it', async () => {
    state.trades = [{ position_id: 101, ticket: 9001 }]
    const res = await postSync({ trades: [closedTrade()] })
    const body = await res.json()
    expect(body.imported).toBe(0)
    expect(body.skipped).toBe(1)
    expect(state.upserted).toHaveLength(0)
  })

  it('honours a deletion tombstone', async () => {
    state.suppressions = [101]
    const res = await postSync({ trades: [closedTrade()] })
    const body = await res.json()
    expect(body.imported).toBe(0)
    expect(body.suppressed).toBe(1)
    expect(state.upserted).toHaveLength(0)
  })

  it('matches a row written by the older ticket-keyed agent', async () => {
    state.trades = [{ ticket: 9001 }]
    const res = await postSync({ trades: [closedTrade()] })
    expect((await res.json()).imported).toBe(0)
    expect(state.upserted).toHaveLength(0)
  })

  it('skips one invalid row but keeps the valid ones', async () => {
    const res = await postSync({
      trades: [closedTrade({ position_id: 202 }), closedTrade({ position_id: 203, close_time: '2026-09-01T00:00:00Z' })],
    })
    const body = await res.json()
    expect(res.status).toBe(200)
    expect(body.imported).toBe(1)
    expect(body.invalid).toBe(1)
  })

  it('rejects a naive timestamp by reading it as UTC, not local time', async () => {
    const res = await postSync({ trades: [closedTrade({ close_time: '2026-10-01T12:00:00' })] })
    expect(res.status).toBe(200)
    expect(String(state.upserted[0].close_time)).toBe('2026-10-01T12:00:00.000Z')
  })

  it('refuses a batch where nothing is valid', async () => {
    const res = await postSync({ trades: [closedTrade({ close_time: '2030-01-01T00:00:00Z' })] })
    expect(res.status).toBe(400)
    expect(state.upserted).toHaveLength(0)
  })

  it('lets a Basic account sync, because autosync is part of the entry tier', async () => {
    state.account = {
      subscription_tier: 'basic',
      subscription_status: 'active',
      trial_ends_at: null,
      max_trades: 50,
      current_period_end: new Date(Date.now() + 30 * 86_400_000).toISOString(),
      cancel_at_period_end: false,
    }

    const res = await postSync({ trades: [closedTrade()] })
    expect(res.status).toBe(200)
    expect(state.upserted).toHaveLength(1)
  })

  it('refuses a lapsed account with a payment-required response', async () => {
    state.account = {
      subscription_tier: 'basic',
      subscription_status: 'active',
      trial_ends_at: null,
      max_trades: 50,
      current_period_end: new Date(Date.now() - 60_000).toISOString(),
      cancel_at_period_end: false,
    }

    const res = await postSync({ trades: [closedTrade()] })
    expect(res.status).toBe(402)
    expect((await res.json()).code).toBe('upgrade_required')
    expect(state.upserted).toHaveLength(0)
  })

  it('lets a live trial sync, because the trial is the Pro pitch', async () => {
    state.account = {
      subscription_tier: 'free',
      subscription_status: 'trial',
      trial_ends_at: new Date(Date.now() + 5 * 86_400_000).toISOString(),
      max_trades: -1,
      current_period_end: null,
      cancel_at_period_end: false,
    }

    const res = await postSync({ trades: [closedTrade()] })
    expect(res.status).toBe(200)
    expect(state.upserted).toHaveLength(1)
  })

  it('rejects a wrong token', async () => {
    const res = await postSync({ trades: [closedTrade()] }, 'nope')
    expect(res.status).toBe(401)
    expect(state.upserted).toHaveLength(0)
  })

  it('accepts the supervisor secret without an agent token', async () => {
    process.env.SYNC_SUPERVISOR_TOKEN = 'super-secret'
    const { POST } = await import('@/app/api/sync/route')
    const res = await POST(
      new Request('http://localhost/api/sync', {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: 'Bearer super-secret' },
        body: JSON.stringify({ userId: 'u1', trades: [closedTrade()] }),
      })
    )
    expect(res.status).toBe(200)
    expect(state.upserted).toHaveLength(1)
  })
})

describe('broker connection', () => {
  async function connect(body: Row): Promise<Response> {
    const { POST } = await import('@/app/api/broker/connection/route')
    return POST(
      new Request('http://localhost/api/broker/connection', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(body),
      })
    )
  }

  const valid = {
    broker: 'IC Markets',
    server: 'ICMarketsSC-Live12',
    login: '12345678',
    investorPassword: 'read-only-pass',
  }

  it('requires a session', async () => {
    state.authUser = null
    const { POST } = await import('@/app/api/broker/connection/route')
    const res = await POST(new Request('http://localhost/api/broker/connection', { method: 'POST', body: '{}' }))
    expect(res.status).toBe(401)
  })

  it('fails closed when no credential key is configured', async () => {
    delete process.env.SYNC_CREDENTIAL_KEY
    const res = await connect(valid)
    expect(res.status).toBe(503)
    expect(state.connection).toBeNull()
  })

  it('stores a sealed credential and never returns it', async () => {
    const res = await connect(valid)
    const body = await res.json()
    expect(res.status).toBe(202)
    expect(JSON.stringify(body)).not.toContain('read-only-pass')
    expect(body.account).toBe('•••••678')
    expect(body.status).toBe('pending')

    const stored = String(state.connection?.credential_cipher)
    expect(stored.startsWith('v1:')).toBe(true)
    expect(stored).not.toContain('read-only-pass')
  })

  it('rejects a malformed account number', async () => {
    const res = await connect({ ...valid, login: '12 34' })
    expect(res.status).toBe(400)
    expect(state.connection).toBeNull()
  })

  it('wipes the credential on disconnect', async () => {
    await connect(valid)
    const { DELETE } = await import('@/app/api/broker/connection/route')
    const res = await DELETE(
      new Request('http://localhost/api/broker/connection', {
        method: 'DELETE',
        headers: { authorization: 'Bearer session' },
      })
    )
    expect(res.status).toBe(200)
    const wipe = state.updates.at(-1)
    expect(wipe).toMatchObject({ credential_cipher: '', status: 'disconnected' })
  })
})
