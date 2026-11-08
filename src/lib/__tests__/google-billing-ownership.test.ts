import { beforeEach, describe, expect, it, vi } from 'vitest'

type Row = Record<string, unknown>

const state = vi.hoisted(() => ({
  /** Accounts the mocked table says already store this purchase token. */
  owners: [] as string[],
  applyCalls: [] as Row[],
  claimError: null as { code?: string; message: string } | null,
  price: '29.00' as string | null,
  acknowledgeCalls: 0,
  subscription: {
    planId: 'pro',
    productId: 'pro_month',
    interval: 'month',
    active: true,
    acknowledged: true,
    expiryTime: '2027-01-01T00:00:00.000Z',
    state: 'SUBSCRIPTION_STATE_ACTIVE',
  } as Row,
}))

vi.mock('@/lib/server-auth', () => ({
  getAdminClient: () => ({
    from: (table: string) => {
      const result =
        table === 'google_play_subscriptions'
          ? { data: state.owners.map((user_id) => ({ user_id })), error: null }
          : { data: null, error: null }

      const chain: Record<string, unknown> = {
        select: () => chain,
        eq: () => chain,
        update: () => ({ eq: async () => ({ error: null }) }),
        upsert: async () => ({ error: state.claimError }),
        then: (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve),
      }
      return chain
    },
  }),
}))

vi.mock('@/lib/google-play', () => ({
  verifyPlaySubscription: async () => state.subscription,
  acknowledgeSubscription: async () => {
    state.acknowledgeCalls += 1
    return true
  },
}))

vi.mock('@/lib/payments', () => ({
  priceForPlan: () => state.price,
  applyPaidOrder: async (order: Row) => {
    state.applyCalls.push(order)
    return { applied: true, reason: 'applied' }
  },
}))

const { syncGoogleSubscription } = await import('@/lib/google-billing')

beforeEach(() => {
  state.owners = []
  state.applyCalls = []
  state.claimError = null
  state.price = '29.00'
  state.acknowledgeCalls = 0
  state.subscription = {
    planId: 'pro',
    productId: 'pro_month',
    interval: 'month',
    active: true,
    acknowledged: true,
    expiryTime: '2027-01-01T00:00:00.000Z',
    state: 'SUBSCRIPTION_STATE_ACTIVE',
  }
})

describe('Google Play ownership', () => {
  it('refuses a token already stored by a different account', async () => {
    state.owners = ['someone-else']

    const result = await syncGoogleSubscription({
      userId: 'u1',
      purchaseToken: 'tok-shared',
    })

    expect(result).toMatchObject({ status: 'ignored', conflict: true, applied: false })
    expect(state.applyCalls).toHaveLength(0)
  })

  it('applies a token the account already owns, so renewals still work', async () => {
    state.owners = ['u1']

    const result = await syncGoogleSubscription({
      userId: 'u1',
      purchaseToken: 'tok-mine',
    })

    expect(result).toMatchObject({ status: 'active', applied: true })
    expect(state.applyCalls).toHaveLength(1)
  })

  it('does not grant access when the database claim loses a race', async () => {
    // The pre-check saw no owner, but another request claimed the token first.
    state.claimError = { code: '23505', message: 'duplicate key value violates unique constraint' }

    const result = await syncGoogleSubscription({
      userId: 'u1',
      purchaseToken: 'tok-raced',
    })

    expect(result).toMatchObject({ status: 'ignored', conflict: true, applied: false })
    expect(state.applyCalls).toHaveLength(0)
  })

  it('applies a token no account has claimed yet', async () => {
    const result = await syncGoogleSubscription({
      userId: 'u1',
      purchaseToken: 'tok-new',
    })

    expect(result.applied).toBe(true)
    expect(state.applyCalls).toHaveLength(1)
  })

  it('does not acknowledge a purchase it could not price or grant', async () => {
    state.price = null
    state.subscription.acknowledged = false

    const result = await syncGoogleSubscription({
      userId: 'u1',
      purchaseToken: 'tok-unpriced',
    })

    expect(result.applied).toBe(false)
    expect(state.acknowledgeCalls).toBe(0)
  })
})
