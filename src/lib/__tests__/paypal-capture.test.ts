import { beforeEach, describe, expect, it, vi } from 'vitest'

type Row = Record<string, unknown>

const state = vi.hoisted(() => ({
  order: {} as Row,
  capture: {} as Row,
  applyCalls: [] as Row[],
  fetchCalls: [] as string[],
}))

vi.mock('@/lib/server-auth', () => ({
  getAuthUser: async () => ({ id: 'u1', email: 'trader@example.com' }),
}))

vi.mock('@/lib/rate-limit', () => ({
  rateLimit: async () => ({ ok: true, remaining: 99, retryAfterMs: 0 }),
}))

vi.mock('@/lib/payments', async (importOriginal) => {
  const actual = (await importOriginal()) as Record<string, unknown>
  return {
    ...actual,
    getPayPalAccessToken: async () => 'test-token',
    applyPaidOrder: async (order: Row) => {
      state.applyCalls.push(order)
      return { applied: true, reason: 'applied' }
    },
  }
})

function jsonResponse(payload: unknown, status = 200): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => payload,
  } as Response
}

function orderFor(userId: string, status: string, over: Row = {}): Row {
  return {
    status,
    purchase_units: [
      {
        custom_id: JSON.stringify({ userId, planId: 'pro' }),
        amount: { value: '29.00', currency_code: 'USD' },
        ...over,
      },
    ],
  }
}

async function capture(orderId = 'ORDER-1'): Promise<Response> {
  const { POST } = await import('@/app/api/paypal/capture/route')
  return POST(
    new Request('http://localhost/api/paypal/capture', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ orderId }),
    })
  )
}

beforeEach(() => {
  state.order = orderFor('u1', 'APPROVED')
  state.capture = {}
  state.applyCalls = []
  state.fetchCalls = []

  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: string | URL) => {
      const url = String(input)
      state.fetchCalls.push(url)
      if (url.endsWith('/capture')) return jsonResponse(state.capture)
      return jsonResponse(state.order)
    })
  )
})

describe('paypal capture ownership', () => {
  it('refuses another account order without capturing it', async () => {
    state.order = orderFor('someone-else', 'APPROVED')

    const res = await capture()

    expect(res.status).toBe(403)
    expect(state.applyCalls).toHaveLength(0)
    expect(state.fetchCalls).toHaveLength(1)
    expect(state.fetchCalls.some((url) => url.endsWith('/capture'))).toBe(false)
  })

  it('reuses an already completed order instead of capturing twice', async () => {
    state.order = orderFor('u1', 'COMPLETED', {
      payments: { captures: [{ id: 'CAP-1' }] },
    })

    const res = await capture()
    expect(res.status).toBe(200)
    expect(state.fetchCalls).toHaveLength(1)
    expect(state.applyCalls[0]).toMatchObject({
      userId: 'u1',
      planId: 'pro',
      providerEventId: 'paypal:capture:CAP-1',
    })
  })

  it('refuses a capture whose amount differs from the order', async () => {
    state.capture = orderFor('u1', 'COMPLETED', {
      payments: {
        captures: [
          { id: 'CAP-3', amount: { value: '1.00', currency_code: 'USD' } },
        ],
      },
    })

    const res = await capture()
    expect(res.status).toBe(400)
    expect(state.applyCalls).toHaveLength(0)
  })

  it('captures an approved order owned by the caller', async () => {
    state.capture = orderFor('u1', 'COMPLETED', {
      payments: { captures: [{ id: 'CAP-2' }] },
    })

    const res = await capture()
    expect(res.status).toBe(200)
    expect(state.fetchCalls).toHaveLength(2)
    expect(state.applyCalls).toHaveLength(1)
    expect(state.applyCalls[0]).toMatchObject({ providerEventId: 'paypal:capture:CAP-2' })
  })
})
