import { beforeEach, describe, expect, it, vi } from 'vitest'

/**
 * The one flow the business depends on, run through the real handlers:
 *
 *   signup → trial profile → Paddle payment → the plan the store page sells
 *
 * Every other test checks one module. This one exists because the expensive bugs
 * have been between modules: a price changed on the page but not in the amount
 * the webhook applies, an annual purchase routed through the monthly function,
 * a profile created without trial dates. Each of those passes every unit test
 * and fails only when the pieces are wired together.
 *
 * Supabase is faked (there is no database in CI), so this proves the wiring and
 * the arithmetic on the way to the database, not the SQL itself — the migration
 * tests and `docs/OPERATIONS.md` cover that boundary.
 */

type Row = Record<string, unknown>

const state = vi.hoisted(() => ({
  authUser: { id: 'u1', email: 'trader@example.com' } as Row | null,
  users: new Map<string, Row>(),
  applied: [] as Row[],
  seenEvents: new Set<string>(),
  writes: [] as Row[],
}))

interface FakeBuilder {
  select: (...args: unknown[]) => FakeBuilder
  eq: () => FakeBuilder
  neq: () => FakeBuilder
  order: () => FakeBuilder
  limit: () => FakeBuilder
  maybeSingle: () => Promise<{ data: null; error: null }>
  single: () => Promise<{ data: null; error: null }>
  upsert: (row: Row) => Promise<{ data: null; error: null }>
  insert: (row: Row) => Promise<{ data: null; error: null }>
  update: (row: Row) => { eq: () => Promise<{ data: null; error: null }> }
  delete: () => { eq: () => Promise<{ data: null; error: null }> }
}

/**
 * A permissive stand-in for the admin client. The handlers touch `users` and
 * `billing_subscriptions`, and a missing method would surface as a 500 in a test
 * whose subject is the wiring rather than the query builder — so reads always
 * return nothing and writes are recorded.
 */
function fakeClient() {
  const builder = () => {
    const api = {} as FakeBuilder
    api.select = () => api
    api.eq = () => api
    api.neq = () => api
    api.order = () => api
    api.limit = () => api
    api.maybeSingle = async () => ({ data: null, error: null })
    api.single = async () => ({ data: null, error: null })
    api.upsert = async (row: Row) => {
      state.writes.push({ table: 'users', op: 'upsert', row })
      if (row && typeof row === 'object') state.users.set(String(row.id), row)
      return { data: null, error: null }
    }
    api.insert = async (row: Row) => {
      state.writes.push({ table: 'insert', op: 'insert', row })
      return { data: null, error: null }
    }
    api.update = (row: Row) => {
      state.writes.push({ table: 'update', op: 'update', row })
      return { eq: async () => ({ data: null, error: null }) }
    }
    api.delete = () => ({ eq: async () => ({ data: null, error: null }) })
    return api
  }

  return {
    auth: {
      admin: {
        getUserById: async () => ({ data: { user: state.authUser }, error: null }),
      },
    },
    rpc: async (name: string, args: Row) => {
      if (name === 'apply_paid_order' || name === 'apply_annual_order') {
        state.applied.push({ name, ...args })
        const key = `${args.p_provider}:${args.p_provider_event_id}`
        if (state.seenEvents.has(key)) return { data: 'duplicate', error: null }
        state.seenEvents.add(key)
        return { data: 'applied', error: null }
      }
      return { data: null, error: { message: `Unexpected rpc: ${name}` } }
    },
    from: () => builder(),
  }
}

vi.mock('@supabase/supabase-js', () => ({ createClient: () => fakeClient() }))

vi.mock('@/lib/server-auth', () => ({
  getAdminClient: () => fakeClient(),
  getAuthUser: async () => null,
}))

// Signature verification has its own test file; here it only needs to say yes so
// the rest of the handler runs.
vi.mock('@/lib/paddle', async (importOriginal) => {
  const actual = (await importOriginal()) as Record<string, unknown>
  return {
    ...actual,
    isValidPaddleSignature: () => true,
    webhookSecretConfigured: () => true,
  }
})

async function signup(): Promise<Response> {
  const { POST } = await import('@/app/api/auth/signup/route')
  return POST(
    new Request('http://localhost/api/auth/signup', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        userId: 'u1',
        email: 'trader@example.com',
        fullName: 'Jerry',
      }),
    })
  )
}

interface PaddleTransaction {
  event_id: string
  event_type: string
  data: {
    id: string
    status: string
    subscription_id: string
    custom_data: { userId: string; planId: string; interval: string }
    customer: { email: string }
    items: { price: { id: string } }[]
    details: { totals: { grand_total: number; currency_code: string } }
  }
}

function paddleEvent(
  planId: 'basic' | 'pro',
  interval: 'month' | 'year',
  eventId = 'evt-1'
): PaddleTransaction {
  const priceId =
    interval === 'year' ? `pri_${planId}_year` : `pri_${planId}`
  return {
    event_id: eventId,
    event_type: 'transaction.completed',
    data: {
      id: `txn_${eventId}`,
      status: 'completed',
      subscription_id: `sub_${eventId}`,
      custom_data: { userId: 'u1', planId, interval },
      customer: { email: 'trader@example.com' },
      items: [{ price: { id: priceId } }],
      details: { totals: { grand_total: 31320, currency_code: 'USD' } },
    },
  }
}

async function pay(event: unknown): Promise<Response> {
  const { POST } = await import('@/app/api/webhooks/paddle/route')
  return POST(
    new Request('http://localhost/api/webhooks/paddle', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'paddle-signature': 'ts=1;h1=stub' },
      body: JSON.stringify(event),
    })
  )
}

async function plans(): Promise<Row[]> {
  const { GET } = await import('@/app/api/plans/route')
  return (await (await GET()).json()) as Row[]
}

beforeEach(() => {
  state.authUser = { id: 'u1', email: 'trader@example.com' }
  state.users.clear()
  state.applied = []
  state.seenEvents = new Set()
  state.writes = []

  process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://example.supabase.co'
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'service'
  process.env.PADDLE_WEBHOOK_SECRET = 'whsec'
  process.env.PADDLE_API_KEY = 'pdl_test'
  process.env.PADDLE_PRICE_BASIC = 'pri_basic'
  process.env.PADDLE_PRICE_PRO = 'pri_pro'
  process.env.PADDLE_PRICE_BASIC_ANNUAL = 'pri_basic_year'
  process.env.PADDLE_PRICE_PRO_ANNUAL = 'pri_pro_year'
})

describe('critical path', () => {
  it('creates a trial profile that does not start half-configured', async () => {
    const res = await signup()
    expect(res.status).toBe(200)

    const row = state.users.get('u1')
    expect(row).toBeDefined()
    expect(row).toMatchObject({
      id: 'u1',
      email: 'trader@example.com',
      full_name: 'Jerry',
      subscription_tier: 'free',
      subscription_status: 'trial',
    })

    // A trial without an end date would never expire; one without a positive
    // allowance would be read-only before the first trade.
    expect(Date.parse(String(row?.trial_ends_at))).toBeGreaterThan(Date.now())
    expect(Number(row?.max_trades)).not.toBe(0)
  })

  it('refuses a profile for an email that is not the authenticated user', async () => {
    state.authUser = { id: 'u1', email: 'someone@example.com' }
    const res = await signup()
    expect(res.status).toBe(403)
    expect(state.users.size).toBe(0)
  })

  it('takes a monthly Pro payment and applies exactly the price the app sells', async () => {
    await signup()

    const res = await pay(paddleEvent('pro', 'month'))
    expect(res.status).toBe(200)
    expect(state.applied).toHaveLength(1)
    expect(state.applied[0]).toMatchObject({
      name: 'apply_paid_order',
      p_user_id: 'u1',
      p_provider: 'paddle',
      p_plan_id: 'pro',
    })

    // The number the customer is charged on the store page and the number the
    // database insists on must be the same one, or the payment is refused with
    // `amount_mismatch` while the webhook still answers 200.
    const pro = (await plans()).find((plan) => plan.id === 'pro')
    expect(pro?.price).toBe(29)
    expect(Number(state.applied[0].p_amount)).toBe(pro?.price)
    expect(Number(pro?.annual_price)).toBe(290)

    // The whole transaction total includes tax and must never be what is applied.
    expect(Number(state.applied[0].p_amount)).not.toBe(313.2)
  })

  it('routes a yearly purchase through the annual function at the yearly price', async () => {
    await signup()
    const res = await pay(paddleEvent('basic', 'year'))
    expect(res.status).toBe(200)

    const basic = (await plans()).find((plan) => plan.id === 'basic')
    expect(state.applied[0]).toMatchObject({
      name: 'apply_annual_order',
      p_plan_id: 'basic',
    })
    expect(Number(state.applied[0].p_amount)).toBe(basic?.annual_price)
    // A year is not twelve months at full price: the discount is the offer.
    expect(Number(basic?.annual_price)).toBeLessThan(Number(basic?.price) * 12)
  })

  it('does not grant access twice when the provider replays the same event', async () => {
    await signup()

    expect((await pay(paddleEvent('pro', 'month', 'evt-9'))).status).toBe(200)
    expect((await pay(paddleEvent('pro', 'month', 'evt-9'))).status).toBe(200)

    expect(state.applied).toHaveLength(2)
    expect(new Set(state.applied.map((call) => call.p_provider_event_id)).size).toBe(1)
  })

  it('ignores a payment that completes without a resolvable account', async () => {
    const orphan = paddleEvent('pro', 'month', 'evt-orphan')
    orphan.data.custom_data = { userId: '', planId: '', interval: 'month' }

    const res = await pay(orphan)
    expect(res.status).toBe(200)
    // Acknowledged, not applied: Paddle would otherwise retry it forever.
    expect(state.applied).toHaveLength(0)
  })
})
