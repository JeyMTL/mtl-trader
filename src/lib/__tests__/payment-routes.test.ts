import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'

type Row = Record<string, unknown>

const state = vi.hoisted(() => ({
  revokeCalls: [] as Row[],
  applyCalls: [] as Row[],
  deleteCalls: [] as string[],
  deleteAccountCalls: [] as string[],
  eventLookup: null as Row | null,
  revokeResult: 'revoked',
  applyResult: 'applied',
  deleteAccountResult: 'deleted',
  authDeleteError: null as { message: string } | null,
  verified: 'SUCCESS',
  authUser: { id: 'u1', email: 'trader@example.com', email_confirmed_at: '2026-01-01T00:00:00Z' } as Row | null,
}))

vi.mock('@/lib/server-auth', () => {
  const client = {
    rpc: async (name: string, args: Row) => {
      if (name === 'apply_paid_order') {
        state.applyCalls.push(args)
        return { data: state.applyResult, error: null }
      }
      if (name === 'revoke_paid_order') {
        state.revokeCalls.push(args)
        return { data: state.revokeResult, error: null }
      }
      if (name === 'delete_account_data') {
        state.deleteAccountCalls.push(String(args.p_user_id))
        return { data: state.deleteAccountResult, error: null }
      }
      return { data: null, error: { message: `Unexpected rpc: ${name}` } }
    },
    from: (table: string) => {
      if (table !== 'payment_events') throw new Error(`Unexpected table: ${table}`)
      const chain = {
        select: () => chain,
        eq: () => chain,
        maybeSingle: async () => ({ data: state.eventLookup, error: null }),
      }
      return chain
    },
    auth: {
      admin: {
        deleteUser: async (id: string) => {
          state.deleteCalls.push(id)
          return { data: null, error: state.authDeleteError }
        },
        getUser: async () => ({ data: { user: state.authUser }, error: null }),
      },
    },
  }
  return {
    getAdminClient: () => client,
    getAuthUser: async () => (state.authUser as unknown) ?? null,
  }
})

vi.mock('@/lib/payments', async (importOriginal) => {
  const actual = (await importOriginal()) as Record<string, unknown>
  return { ...actual, getPayPalAccessToken: async () => 'test-token' }
})

const WEBHOOK_HEADERS = {
  'paypal-transmission-id': 'tid',
  'paypal-transmission-time': '2026-06-01T00:00:00Z',
  'paypal-cert-url': 'https://api-m.paypal.com/cert',
  'paypal-auth-algo': 'SHA256withRSA',
  'paypal-transmission-sig': 'sig',
  'content-type': 'application/json',
}

function webhookRequest(event: Row): Request {
  return new Request('http://localhost/api/webhooks/paypal', {
    method: 'POST',
    headers: WEBHOOK_HEADERS,
    body: JSON.stringify(event),
  })
}

async function withWebhook<T>(event: Row, run: (res: Response) => Promise<T>): Promise<T> {
  const { POST } = await import('@/app/api/webhooks/paypal/route')
  const res = await POST(webhookRequest(event))
  return run(res)
}

beforeEach(() => {
  state.revokeCalls = []
  state.applyCalls = []
  state.deleteCalls = []
  state.deleteAccountCalls = []
  state.eventLookup = null
  state.revokeResult = 'revoked'
  state.applyResult = 'applied'
  state.deleteAccountResult = 'deleted'
  state.authDeleteError = null
  state.verified = 'SUCCESS'
  state.authUser = { id: 'u1', email: 'trader@example.com', email_confirmed_at: '2026-01-01T00:00:00Z' }

  process.env.PAYPAL_WEBHOOK_ID = 'wh-1'
  process.env.PAYPAL_CLIENT_ID = 'client'
  process.env.PAYPAL_CLIENT_SECRET = 'secret'

  vi.stubGlobal('fetch', vi.fn(async () => ({
    ok: true,
    status: 200,
    json: async () => ({ verification_status: state.verified }),
  })))
})

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('paypal webhook', () => {
  it('applies a completed capture exactly once', async () => {
    await withWebhook({
      id: 'evt-1',
      event_type: 'PAYMENT.CAPTURE.COMPLETED',
      resource: {
        id: 'CAP-1',
        custom_id: JSON.stringify({ userId: 'u1', planId: 'pro' }),
        amount: { value: '5.00' },
      },
    }, async (res) => {
      expect(res.status).toBe(200)
      expect(state.applyCalls).toHaveLength(1)
      expect(state.applyCalls[0]).toMatchObject({
        p_user_id: 'u1',
        p_plan_id: 'pro',
        p_provider_event_id: 'paypal:capture:CAP-1',
      })
    })
  })

  it('revokes access on a refund that carries order metadata', async () => {
    await withWebhook({
      id: 'evt-2',
      event_type: 'PAYMENT.CAPTURE.REFUNDED',
      resource: {
        id: 'REF-1',
        custom_id: JSON.stringify({ userId: 'u1', planId: 'pro' }),
        amount: { value: '5.00' },
      },
    }, async (res) => {
      expect(res.status).toBe(200)
      expect(state.revokeCalls).toHaveLength(1)
      expect(state.revokeCalls[0]).toMatchObject({
        p_user_id: 'u1',
        p_provider_event_id: 'paypal:refund:REF-1',
        p_amount: 5,
      })
    })
  })

  it('finds the order through the capture link when the refund has no metadata', async () => {
    state.eventLookup = { user_id: 'u9', plan_id: 'basic', amount: 2.5 }

    await withWebhook({
      id: 'evt-3',
      event_type: 'PAYMENT.CAPTURE.REVERSED',
      resource: {
        id: 'REF-2',
        amount: { value: '2.50' },
        links: [
          { rel: 'up', href: 'https://api-m.paypal.com/v2/payments/captures/CAP-9' },
        ],
      },
    }, async (res) => {
      expect(res.status).toBe(200)
      expect(state.revokeCalls[0]).toMatchObject({ p_user_id: 'u9', p_plan_id: 'basic' })
    })
  })

  it('reports a replayed refund as a duplicate without erroring', async () => {
    state.revokeResult = 'duplicate'

    await withWebhook({
      id: 'evt-4',
      event_type: 'PAYMENT.CAPTURE.REFUNDED',
      resource: {
        id: 'REF-1',
        custom_id: JSON.stringify({ userId: 'u1', planId: 'pro' }),
        amount: { value: '5.00' },
      },
    }, async (res) => {
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body.revoked).toBe('duplicate')
    })
  })

  it('acknowledges an unresolvable refund instead of retrying forever', async () => {
    await withWebhook({
      id: 'evt-5',
      event_type: 'PAYMENT.CAPTURE.REFUNDED',
      resource: { id: 'REF-3', amount: { value: '5.00' } },
    }, async (res) => {
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body.ignored).toBe('unresolved_refund')
      expect(state.revokeCalls).toHaveLength(0)
    })
  })

  it('rejects an unverified signature', async () => {
    state.verified = 'FAILURE'

    await withWebhook({
      id: 'evt-6',
      event_type: 'PAYMENT.CAPTURE.COMPLETED',
      resource: {
        id: 'CAP-2',
        custom_id: JSON.stringify({ userId: 'u1', planId: 'pro' }),
        amount: { value: '5.00' },
      },
    }, async (res) => {
      expect(res.status).toBe(400)
      expect(state.applyCalls).toHaveLength(0)
    })
  })
})

describe('account deletion', () => {
  async function deleteAccount(body: unknown): Promise<Response> {
    const { POST } = await import('@/app/api/account/delete/route')
    return POST(new Request('http://localhost/api/account/delete', {
      method: 'POST',
      headers: { authorization: 'Bearer token', 'content-type': 'application/json' },
      body: JSON.stringify(body),
    }))
  }

  it('requires the account email as confirmation', async () => {
    const res = await deleteAccount({})
    expect(res.status).toBe(400)
    expect(state.deleteAccountCalls).toHaveLength(0)

    const wrong = await deleteAccount({ confirmEmail: 'someone@example.com' })
    expect(wrong.status).toBe(400)
    expect(state.deleteAccountCalls).toHaveLength(0)
  })

  it('deletes data atomically and then the auth identity', async () => {
    const res = await deleteAccount({ confirmEmail: 'trader@example.com' })
    expect(res.status).toBe(200)
    expect(state.deleteAccountCalls).toEqual(['u1'])
    expect(state.deleteCalls).toEqual(['u1'])
  })

  it('reports a retryable failure when the identity cannot be removed', async () => {
    state.authDeleteError = { message: 'boom' }

    const res = await deleteAccount({ confirmEmail: 'trader@example.com' })
    expect(res.status).toBe(500)
    // Data removal already happened; the response must not claim success.
    expect(state.deleteAccountCalls).toEqual(['u1'])
  })
})
