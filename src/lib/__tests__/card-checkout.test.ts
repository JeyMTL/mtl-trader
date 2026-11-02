import { beforeEach, describe, expect, it, vi } from 'vitest'

/**
 * The phone app's pay button. It exists because the app once called a
 * processor-specific route directly, which answered 503 to every in-app payment
 * whenever the deployment used the other processor.
 */

const state = vi.hoisted(() => ({
  user: { id: 'u1', email: 'ann@example.com' } as { id: string; email: string | null } | null,
  configured: false,
  prices: {} as Record<string, string | null>,
  annualPrices: {} as Record<string, string | null>,
  lastCheckout: null as { planId: string; priceId: string; interval?: string } | null,
  account: null as Record<string, unknown> | null,
}))

vi.mock('@/lib/server-auth', () => ({
  getAuthUser: async () => state.user,
  getAdminClient: () => ({
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: async () => ({ data: state.account, error: null }),
        }),
      }),
    }),
  }),
}))

vi.mock('@/lib/paddle', () => ({
  paddleConfigured: () => state.configured,
  priceIdFor: (planId: string, interval: 'month' | 'year' = 'month') =>
    (interval === 'year' ? state.annualPrices[planId] : state.prices[planId]) ?? null,
  sellablePlanIds: (planIds: string[], interval: 'month' | 'year' = 'month') =>
    state.configured
      ? planIds.filter((planId) =>
          Boolean(
            (interval === 'year' ? state.annualPrices[planId] : state.prices[planId]) ?? null
          )
        )
      : [],
  createCheckoutTransaction: async (input: {
    planId: string
    priceId: string
    interval?: string
  }) => {
    state.lastCheckout = input
    return {
      url: `https://paddle/${input.planId}`,
      transactionId: 'txn_1',
    }
  },
}))

async function call(method: 'GET' | 'POST', body?: Record<string, unknown>) {
  const { GET, POST } = await import('@/app/api/checkout/card/route')
  const init: RequestInit =
    method === 'POST'
      ? { method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body ?? {}) }
      : { method }
  const res =
    method === 'GET'
      ? await GET()
      : await POST(new Request('http://localhost/api/checkout/card', init))
  return { res, body: (await res.json()) as Record<string, unknown> }
}

beforeEach(() => {
  state.user = { id: 'u1', email: 'ann@example.com' }
  state.configured = false
  state.prices = { basic: 'pri_basic', pro: 'pri_pro' }
  state.annualPrices = { basic: 'pri_basic_year', pro: 'pri_pro_year' }
  state.lastCheckout = null
  state.account = null
})

describe('POST /api/checkout/card', () => {
  it('rejects an anonymous caller', async () => {
    state.user = null
    state.configured = true
    const { res } = await call('POST', { planId: 'pro' })
    expect(res.status).toBe(401)
  })

  it('refuses to point the payment at another account', async () => {
    state.configured = true
    const { res } = await call('POST', { planId: 'pro', userId: 'someone-else' })
    expect(res.status).toBe(403)
  })

  it('creates a Paddle transaction and returns its checkout link', async () => {
    state.configured = true
    const { res, body } = await call('POST', { planId: 'pro' })
    expect(res.status).toBe(200)
    expect(body.provider).toBe('paddle')
    expect(body.url).toBe('https://paddle/pro')
    expect(body.transactionId).toBe('txn_1')
  })

  it('hides a plan that has no price id rather than 503-ing the whole set', async () => {
    state.configured = true
    state.prices = { basic: null, pro: 'pri_pro' }

    const list = await call('GET')
    expect(list.body.enabled).toBe(true)
    expect(list.body.plans).toEqual(['pro'])

    const checkout = await call('POST', { planId: 'basic' })
    expect(checkout.res.status).toBe(503)
  })

  it('answers 503 only when Paddle is not configured at all', async () => {
    const { res, body } = await call('POST', { planId: 'pro' })
    expect(res.status).toBe(503)
    expect(body.error).toContain('not configured')
  })

  it('rejects an unknown plan', async () => {
    state.configured = true
    const { res } = await call('POST', { planId: 'gold' })
    expect(res.status).toBe(400)
  })

  it('buys a year with the yearly price id and cadence', async () => {
    state.configured = true
    const { res } = await call('POST', { planId: 'basic', interval: 'year' })
    expect(res.status).toBe(200)
    expect(state.lastCheckout).toMatchObject({
      planId: 'basic',
      priceId: 'pri_basic_year',
      interval: 'year',
    })
  })

  it('refuses to charge a monthly subscriber for the same month twice', async () => {
    state.configured = true
    state.account = {
      subscription_tier: 'basic',
      subscription_status: 'active',
      current_period_end: new Date(Date.now() + 10 * 86_400_000).toISOString(),
      cancel_at_period_end: false,
    }

    const repeat = await call('POST', { planId: 'basic', interval: 'month' })
    expect(repeat.res.status).toBe(409)
    expect(repeat.body.error).toContain('already on Basic')
    expect(state.lastCheckout).toBeNull()

    // The upgrade path stays open and buys the yearly price.
    const upgrade = await call('POST', { planId: 'basic', interval: 'year' })
    expect(upgrade.res.status).toBe(200)
    expect(state.lastCheckout).toMatchObject({
      priceId: 'pri_basic_year',
      interval: 'year',
    })
  })

  it('treats an unknown cadence as monthly rather than failing', async () => {
    state.configured = true
    await call('POST', { planId: 'pro', interval: 'weekly' })
    expect(state.lastCheckout).toMatchObject({ priceId: 'pri_pro', interval: 'month' })
  })
})

describe('GET /api/checkout/card', () => {
  it('reports Paddle and its sellable plans', async () => {
    state.configured = true
    const { body } = await call('GET')
    expect(body).toEqual({
      enabled: true,
      provider: 'paddle',
      plans: ['basic', 'pro'],
      annual: ['basic', 'pro'],
    })
  })

  it('sells a year only for the plans that have a yearly price', async () => {
    state.configured = true
    state.annualPrices = { basic: null, pro: 'pri_pro_year' }

    const { body } = await call('GET')
    expect(body.annual).toEqual(['pro'])

    const yearly = await call('POST', { planId: 'basic', interval: 'year' })
    expect(yearly.res.status).toBe(503)
  })

  it('says nothing is available when Paddle is unconfigured', async () => {
    const { body } = await call('GET')
    expect(body).toEqual({ enabled: false, provider: null, plans: [], annual: [] })
  })
})
