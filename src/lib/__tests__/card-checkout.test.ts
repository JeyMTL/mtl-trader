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
}))

vi.mock('@/lib/server-auth', () => ({
  getAuthUser: async () => state.user,
}))

vi.mock('@/lib/paddle', () => ({
  paddleConfigured: () => state.configured,
  priceIdFor: (planId: string) => state.prices[planId] ?? null,
  createCheckoutTransaction: async (input: { planId: string; priceId: string }) => ({
    url: `https://paddle/${input.planId}`,
    transactionId: 'txn_1',
  }),
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
})

describe('GET /api/checkout/card', () => {
  it('reports Paddle and its sellable plans', async () => {
    state.configured = true
    const { body } = await call('GET')
    expect(body).toEqual({ enabled: true, provider: 'paddle', plans: ['basic', 'pro'] })
  })

  it('says nothing is available when Paddle is unconfigured', async () => {
    const { body } = await call('GET')
    expect(body).toEqual({ enabled: false, provider: null, plans: [] })
  })
})
