import { beforeEach, describe, expect, it, vi } from 'vitest'

/**
 * The phone app's pay button. These cases exist because the app once called the
 * Flutterwave route directly, which 503s on a Paddle deployment — that is, every
 * mobile customer saw "Card payments are not configured yet." while the web took
 * payments fine.
 */

const state = vi.hoisted(() => ({
  user: { id: 'u1', email: 'ann@example.com', user_metadata: {} as Record<string, unknown> } as
    | { id: string; email: string | null; user_metadata: Record<string, unknown> }
    | null,
  paddle: false,
  paddlePrices: {} as Record<string, string | null>,
  flutterwave: false,
}))

vi.mock('@/lib/server-auth', () => ({
  getAuthUser: async () => state.user,
}))

vi.mock('@/lib/paddle', () => ({
  paddleConfigured: () => state.paddle,
  priceIdFor: (planId: string) => state.paddlePrices[planId] ?? null,
  createCheckoutTransaction: async (input: { planId: string; priceId: string }) => ({
    url: `https://paddle/${input.planId}`,
    transactionId: 'txn_1',
  }),
}))

vi.mock('@/lib/flutterwave', () => ({
  flutterwaveConfigured: () => state.flutterwave,
  isPaidPlanId: (planId: string) => planId === 'basic' || planId === 'pro',
  ensurePaymentPlan: async () => 'plan_remote',
  createCheckoutSession: async (input: { planId: string }) => ({
    url: `https://flutterwave/${input.planId}`,
    txRef: 'tx_1',
  }),
}))

async function call(method: 'GET' | 'POST', body?: Record<string, unknown>) {
  const { GET, POST } = await import('@/app/api/checkout/card/route')
  const init: RequestInit =
    method === 'POST'
      ? { method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body ?? {}) }
      : { method }
  const res = method === 'GET' ? await GET() : await POST(new Request('http://localhost/api/checkout/card', init))
  return { res, body: (await res.json()) as Record<string, unknown> }
}

beforeEach(() => {
  state.user = { id: 'u1', email: 'ann@example.com', user_metadata: {} }
  state.paddle = false
  state.paddlePrices = { basic: 'pri_basic', pro: 'pri_pro' }
  state.flutterwave = false
  process.env.NEXT_PUBLIC_APP_URL = 'https://app.example.com'
})

describe('POST /api/checkout/card', () => {
  it('rejects an anonymous caller', async () => {
    state.user = null
    state.paddle = true
    const { res } = await call('POST', { planId: 'pro' })
    expect(res.status).toBe(401)
  })

  it('refuses to point the payment at another account', async () => {
    state.paddle = true
    const { res } = await call('POST', { planId: 'pro', userId: 'someone-else' })
    expect(res.status).toBe(403)
  })

  it('uses Paddle when it is the configured processor', async () => {
    state.paddle = true
    state.flutterwave = true
    const { res, body } = await call('POST', { planId: 'pro' })
    expect(res.status).toBe(200)
    expect(body.provider).toBe('paddle')
    expect(body.url).toBe('https://paddle/pro')
  })

  it('falls back to Flutterwave instead of failing the way the app used to', async () => {
    state.flutterwave = true
    const { res, body } = await call('POST', { planId: 'basic' })
    expect(res.status).toBe(200)
    expect(body.provider).toBe('flutterwave')
    expect(body.url).toBe('https://flutterwave/basic')
  })

  it('hides a plan that has no Paddle price rather than 503-ing the whole set', async () => {
    state.paddle = true
    state.paddlePrices = { basic: null, pro: 'pri_pro' }
    const { body } = await call('GET')
    expect(body.enabled).toBe(true)
    expect(body.plans).toEqual(['pro'])

    const checkout = await call('POST', { planId: 'basic' })
    expect(checkout.res.status).toBe(503)
  })

  it('answers 503 only when no processor can take a card', async () => {
    const { res, body } = await call('POST', { planId: 'pro' })
    expect(res.status).toBe(503)
    expect(body.error).toContain('not configured')
  })

  it('rejects an unknown plan', async () => {
    state.paddle = true
    const { res } = await call('POST', { planId: 'gold' })
    expect(res.status).toBe(400)
  })
})

describe('GET /api/checkout/card', () => {
  it('reports the processor and its sellable plans', async () => {
    state.paddle = true
    const { body } = await call('GET')
    expect(body).toEqual({ enabled: true, provider: 'paddle', plans: ['basic', 'pro'] })
  })

  it('says nothing is available with no processor configured', async () => {
    const { body } = await call('GET')
    expect(body).toEqual({ enabled: false, provider: null, plans: [] })
  })
})
