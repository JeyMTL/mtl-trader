import { createHmac } from 'node:crypto'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  annualPriceCollisions,
  cancelPaddleSubscription,
  createCheckoutTransaction,
  isValidPaddleSignature,
  paddleBase,
  parseAdjustmentEvent,
  parsePaddleSignature,
  parseTransactionEvent,
  priceIdFor,
  sellablePlanIds,
} from '@/lib/paddle'

const SECRET = 'pdl_ntfset_test_secret'

function sign(body: string, ts: number, secret = SECRET): string {
  const digest = createHmac('sha256', secret).update(`${ts}:${body}`).digest('hex')
  return `ts=${ts};h1=${digest}`
}

function jsonResponse(payload: unknown, status = 200): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => payload,
    text: async () => JSON.stringify(payload),
  } as Response
}

beforeEach(() => {
  process.env.PADDLE_WEBHOOK_SECRET = SECRET
  process.env.PADDLE_API_KEY = 'pdl_sdbx_test'
  process.env.PADDLE_PRICE_BASIC = 'pri_basic'
  process.env.PADDLE_PRICE_PRO = 'pri_pro'
  process.env.PADDLE_PRICE_BASIC_ANNUAL = 'pri_basic_year'
  process.env.PADDLE_PRICE_PRO_ANNUAL = 'pri_pro_year'
  delete process.env.PADDLE_ENVIRONMENT
  delete process.env.PADDLE_API_BASE
  delete process.env.PADDLE_CURRENCY
})

afterEach(() => {
  vi.unstubAllGlobals()
  delete process.env.PADDLE_WEBHOOK_SECRET
  delete process.env.PADDLE_API_KEY
  delete process.env.PADDLE_PRICE_BASIC
  delete process.env.PADDLE_PRICE_PRO
  delete process.env.PADDLE_PRICE_BASIC_ANNUAL
  delete process.env.PADDLE_PRICE_PRO_ANNUAL
})

describe('paddle configuration', () => {
  it('defaults to the sandbox, and only goes live when asked', () => {
    expect(paddleBase()).toBe('https://sandbox-api.paddle.com')
    process.env.PADDLE_ENVIRONMENT = 'production'
    expect(paddleBase()).toBe('https://api.paddle.com')
    process.env.PADDLE_API_BASE = 'https://sandbox-api.paddle.com/'
    expect(paddleBase()).toBe('https://sandbox-api.paddle.com')
  })

  it('maps plans to their price ids at call time', () => {
    expect(priceIdFor('basic')).toBe('pri_basic')
    expect(priceIdFor('pro')).toBe('pri_pro')
    expect(priceIdFor('free')).toBeNull()

    delete process.env.PADDLE_PRICE_PRO
    expect(priceIdFor('pro')).toBeNull()
  })

  it('maps a yearly plan to its own catalogue id', () => {
    expect(priceIdFor('basic', 'year')).toBe('pri_basic_year')
    expect(priceIdFor('pro', 'year')).toBe('pri_pro_year')
    expect(priceIdFor('basic', 'month')).toBe('pri_basic')
  })

  it('sells each cadence independently', () => {
    delete process.env.PADDLE_PRICE_PRO_ANNUAL
    expect(sellablePlanIds(['basic', 'pro'], 'year')).toEqual(['basic'])
    expect(sellablePlanIds(['basic', 'pro'])).toEqual(['basic', 'pro'])
  })

  it('flags a yearly slot that was filled with a monthly price id', () => {
    expect(annualPriceCollisions(['basic', 'pro'])).toEqual([])

    // The expensive copy-paste: a $12 monthly id in the yearly slot. Paddle
    // would charge $12 and the webhook would refuse to grant a year.
    process.env.PADDLE_PRICE_PRO_ANNUAL = 'pri_pro'
    expect(annualPriceCollisions(['basic', 'pro'])).toEqual(['pro'])

    // A missing yearly id is not a collision — the cadence is simply not sold.
    delete process.env.PADDLE_PRICE_BASIC_ANNUAL
    expect(annualPriceCollisions(['basic', 'pro'])).toEqual(['pro'])
  })

  it('offers only plans that have a price id, and none without an API key', () => {
    expect(sellablePlanIds(['basic', 'pro'])).toEqual(['basic', 'pro'])
    delete process.env.PADDLE_PRICE_BASIC
    expect(sellablePlanIds(['basic', 'pro'])).toEqual(['pro'])
    delete process.env.PADDLE_API_KEY
    expect(sellablePlanIds(['basic', 'pro'])).toEqual([])
  })
})

describe('checkout', () => {
  it('creates a transaction with the price id and the account in custom data', async () => {
    const fetchImpl = vi.fn(async () =>
      jsonResponse({ data: { id: 'txn_1', checkout: { url: 'https://pay.paddle.io/x' } } }, 201)
    )

    const result = await createCheckoutTransaction(
      { planId: 'pro', priceId: 'pri_pro', userId: 'u1' },
      fetchImpl
    )

    expect(result).toEqual({ url: 'https://pay.paddle.io/x', transactionId: 'txn_1' })
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit]
    expect(url).toBe('https://sandbox-api.paddle.com/transactions')
    expect(init.method).toBe('POST')
    expect((init.headers as Record<string, string>).Authorization).toBe('Bearer pdl_sdbx_test')
    const body = JSON.parse(String(init.body))
    expect(body.items).toEqual([{ price_id: 'pri_pro', quantity: 1 }])
    expect(body.custom_data).toEqual({ userId: 'u1', planId: 'pro', interval: 'month' })
  })

  it('carries the yearly cadence into the transaction', async () => {
    const fetchImpl = vi.fn(async () =>
      jsonResponse({ data: { id: 'txn_2', checkout: { url: 'https://pay.paddle.io/y' } } }, 201)
    )

    await createCheckoutTransaction(
      { planId: 'basic', priceId: 'pri_basic_year', userId: 'u1', interval: 'year' },
      fetchImpl
    )

    const [, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit]
    const body = JSON.parse(String(init.body))
    expect(body.custom_data).toEqual({ userId: 'u1', planId: 'basic', interval: 'year' })
  })

  it('fails when Paddle returns no checkout url instead of redirecting nowhere', async () => {
    const fetchImpl = vi.fn(async () => jsonResponse({ data: { id: 'txn_1' } }, 201))
    await expect(
      createCheckoutTransaction({ planId: 'pro', priceId: 'pri_pro', userId: 'u1' }, fetchImpl)
    ).rejects.toThrow(/checkout url/i)
  })

  it('surfaces the provider message on an error response', async () => {
    const fetchImpl = vi.fn(async () =>
      jsonResponse({ error: { detail: 'price does not exist' } }, 400)
    )
    await expect(
      createCheckoutTransaction({ planId: 'pro', priceId: 'pri_x', userId: 'u1' }, fetchImpl)
    ).rejects.toThrow(/price does not exist/)
  })
})

describe('webhook signature', () => {
  const body = JSON.stringify({ event_type: 'transaction.completed' })

  it('accepts a correctly signed body', () => {
    const ts = Math.floor(Date.now() / 1000)
    expect(isValidPaddleSignature(sign(body, ts), body)).toBe(true)
  })

  it('rejects a tampered body', () => {
    const ts = Math.floor(Date.now() / 1000)
    expect(isValidPaddleSignature(sign(body, ts), `${body} `)).toBe(false)
  })

  it('rejects a signature made with another secret', () => {
    const ts = Math.floor(Date.now() / 1000)
    expect(isValidPaddleSignature(sign(body, ts, 'other'), body)).toBe(false)
  })

  it('rejects a stale signature, so a captured event cannot be replayed', () => {
    const old = Math.floor(Date.now() / 1000) - 3600
    expect(isValidPaddleSignature(sign(body, old), body)).toBe(false)
    expect(
      isValidPaddleSignature(sign(body, old), body, { toleranceSeconds: 7200 })
    ).toBe(true)
  })

  it('accepts any of several h1 values during a secret rotation', () => {
    const ts = Math.floor(Date.now() / 1000)
    const valid = createHmac('sha256', SECRET).update(`${ts}:${body}`).digest('hex')
    const header = `ts=${ts};h1=${'0'.repeat(64)};h1=${valid}`
    expect(isValidPaddleSignature(header, body)).toBe(true)
  })

  it('has no opinion when the secret or header is missing', () => {
    expect(isValidPaddleSignature(null, body)).toBe(false)
    expect(isValidPaddleSignature('garbage', body)).toBe(false)
    expect(isValidPaddleSignature(sign(body, 1), body, { secret: '' })).toBe(false)
    expect(parsePaddleSignature('ts=abc;h1=deadbeef')).toBeNull()
  })
})

describe('event parsing', () => {
  it('reads the transaction, price and custom data', () => {
    const parsed = parseTransactionEvent({
      id: 'txn_9',
      status: 'completed',
      subscription_id: 'sub_1',
      custom_data: { userId: 'u1', planId: 'pro' },
      customer: { email: 'Trader@Example.com' },
      items: [{ price: { id: 'pri_pro' }, quantity: 1 }],
      details: {
        totals: { grand_total: '5425', currency_code: 'USD' },
      },
    })

    expect(parsed).toMatchObject({
      transactionId: 'txn_9',
      status: 'completed',
      userId: 'u1',
      planId: 'pro',
      priceId: 'pri_pro',
      totalCents: 5425,
      currency: 'USD',
      subscriptionId: 'sub_1',
      customerEmail: 'trader@example.com',
    })
  })

  it('reads the cadence from custom data, defaulting to monthly', () => {
    expect(
      parseTransactionEvent({
        id: 'txn_2',
        custom_data: { userId: 'u1', planId: 'pro', interval: 'year' },
      })?.interval
    ).toBe('year')
    expect(
      parseTransactionEvent({
        id: 'txn_3',
        custom_data: { userId: 'u1', planId: 'pro' },
      })?.interval
    ).toBe('month')
  })

  it('returns null without an id, and tolerates missing fields', () => {
    expect(parseTransactionEvent({})).toBeNull()
    expect(parseTransactionEvent(null)).toBeNull()
    const sparse = parseTransactionEvent({ id: 'txn_1' })
    expect(sparse).toMatchObject({ userId: null, planId: null, totalCents: null })
  })

  it('reads a refund adjustment', () => {
    expect(
      parseAdjustmentEvent({
        id: 'adj_1',
        action: 'refund',
        transaction_id: 'txn_9',
        subscription_id: 'sub_1',
      })
    ).toEqual({
      adjustmentId: 'adj_1',
      action: 'refund',
      transactionId: 'txn_9',
      subscriptionId: 'sub_1',
    })
  })
})

describe('cancellation', () => {
  it('cancels at the end of the paid period', async () => {
    const fetchImpl = vi.fn(async () => jsonResponse({ data: {} }))
    await cancelPaddleSubscription('sub_1', fetchImpl)

    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit]
    expect(url).toBe('https://sandbox-api.paddle.com/subscriptions/sub_1/cancel')
    expect(JSON.parse(String(init.body))).toEqual({ effective_from: 'next_billing_period' })
  })

  it('does nothing when Paddle is not configured', async () => {
    delete process.env.PADDLE_API_KEY
    const fetchImpl = vi.fn()
    expect(await cancelPaddleSubscription('sub_1', fetchImpl)).toBe(false)
    expect(fetchImpl).not.toHaveBeenCalled()
  })
})
