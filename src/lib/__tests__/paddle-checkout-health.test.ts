import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { GET } from '@/app/api/health/paddle-checkout/route'

const SECRET = 'health-secret'

function jsonResponse(payload: unknown, status = 200): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => payload,
    text: async () => JSON.stringify(payload),
  } as Response
}

function check(headers: Record<string, string> = {}): Promise<Response> {
  return GET(
    new Request('http://localhost/api/health/paddle-checkout', {
      headers: { authorization: `Bearer ${SECRET}`, ...headers },
    })
  )
}

beforeEach(() => {
  process.env.CRON_SECRET = SECRET
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
  delete process.env.CRON_SECRET
  delete process.env.PADDLE_API_KEY
  delete process.env.PADDLE_PRICE_BASIC
  delete process.env.PADDLE_PRICE_PRO
  delete process.env.PADDLE_PRICE_BASIC_ANNUAL
  delete process.env.PADDLE_PRICE_PRO_ANNUAL
})

describe('Paddle checkout health check', () => {
  it('requires the cron secret', async () => {
    expect((await check({ authorization: '' })).status).toBe(401)
    expect((await check({ authorization: 'Bearer wrong' })).status).toBe(401)
  })

  it('creates and cancels one probe transaction', async () => {
    const fetchMock = vi.fn(async (url: string) =>
      url.endsWith('/transactions')
        ? jsonResponse({ data: { id: 'txn_probe' } }, 201)
        : jsonResponse({ data: { status: 'canceled' } })
    )
    vi.stubGlobal('fetch', fetchMock)

    const response = await check()
    const body = (await response.json()) as Record<string, unknown>

    expect(response.status).toBe(200)
    expect(body).toMatchObject({
      status: 'ok',
      environment: 'sandbox',
      plan: 'basic',
      interval: 'month',
      transactionCreated: true,
      discarded: true,
      transactionId: 'txn_probe',
      detail: null,
    })
    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(fetchMock.mock.calls[0][0]).toBe('https://sandbox-api.paddle.com/transactions')
    expect(fetchMock.mock.calls[1][0]).toBe(
      'https://sandbox-api.paddle.com/transactions/txn_probe'
    )
  })

  it('fails closed when the API key is missing', async () => {
    delete process.env.PADDLE_API_KEY
    const response = await check()
    const body = (await response.json()) as Record<string, unknown>

    expect(response.status).toBe(503)
    expect(body.status).toBe('not_configured')
  })

  it('falls back to the first configured cadence', async () => {
    delete process.env.PADDLE_PRICE_BASIC
    const fetchMock = vi.fn(async (url: string) =>
      url.endsWith('/transactions')
        ? jsonResponse({ data: { id: 'txn_probe' } }, 201)
        : jsonResponse({ data: { status: 'canceled' } })
    )
    vi.stubGlobal('fetch', fetchMock)

    const body = (await (await check()).json()) as Record<string, unknown>
    expect(body).toMatchObject({ status: 'ok', plan: 'pro', interval: 'month' })
  })

  it('returns 503 with the provider reason when creation fails', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => jsonResponse({ error: { detail: 'price does not exist' } }, 403))
    )

    const response = await check()
    const body = (await response.json()) as Record<string, unknown>

    expect(response.status).toBe(503)
    expect(body).toMatchObject({
      status: 'failed',
      transactionCreated: false,
      discarded: false,
      transactionId: null,
    })
    expect(String(body.detail)).toContain('price does not exist')
  })

  it('reports a probe that was created but not discarded', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) =>
        url.endsWith('/transactions')
          ? jsonResponse({ data: { id: 'txn_probe' } }, 201)
          : jsonResponse({ error: { detail: 'cannot cancel this transaction' } }, 500)
      )
    )

    const response = await check()
    const body = (await response.json()) as Record<string, unknown>

    expect(response.status).toBe(503)
    expect(body).toMatchObject({
      status: 'failed',
      transactionCreated: true,
      discarded: false,
      transactionId: 'txn_probe',
    })
    expect(String(body.detail)).toContain('cannot cancel')
  })
})
