import { beforeEach, describe, it, expect, vi } from 'vitest'
import {
  applyPaidOrder,
  parseCustomId,
  PAID_PLAN_PRICES,
  ANNUAL_PLAN_PRICES,
  priceForPlan,
} from '@/lib/payments'
import { isDuplicatePurchase, planRank, shouldApplyPlan } from '@/lib/subscription'

/** Records which billing function a paid order would call. */
const db = vi.hoisted(() => ({
  calls: [] as { name: string; args: Record<string, unknown> }[],
}))

vi.mock('@/lib/server-auth', () => ({
  getAdminClient: () => ({
    rpc: async (name: string, args: Record<string, unknown>) => {
      db.calls.push({ name, args })
      return { data: 'applied', error: null }
    },
  }),
}))

describe('PAID_PLAN_PRICES', () => {
  it('excludes the free plan and matches displayed prices', () => {
    expect(PAID_PLAN_PRICES).toEqual({ basic: '12.00', pro: '29.00' })
  })
})

describe('ANNUAL_PLAN_PRICES', () => {
  it('prices a year at ten months, and is chosen by interval', () => {
    expect(ANNUAL_PLAN_PRICES).toEqual({ basic: '120.00', pro: '290.00' })
    expect(priceForPlan('basic', 'year')).toBe('120.00')
    expect(priceForPlan('pro', 'year')).toBe('290.00')
    expect(priceForPlan('pro')).toBe('29.00')
    // A free plan has no yearly price, so an annual payment cannot apply one.
    expect(priceForPlan('free', 'year')).toBeUndefined()
  })
})

describe('parseCustomId', () => {
  it('parses valid order metadata', () => {
    expect(parseCustomId(JSON.stringify({ userId: 'u1', planId: 'pro' }))).toEqual({ userId: 'u1', planId: 'pro' })
  })

  it('rejects malformed or incomplete metadata', () => {
    expect(parseCustomId(null)).toBeNull()
    expect(parseCustomId(undefined)).toBeNull()
    expect(parseCustomId('')).toBeNull()
    expect(parseCustomId('not json')).toBeNull()
    expect(parseCustomId(JSON.stringify({ userId: 'u1' }))).toBeNull()
    expect(parseCustomId(JSON.stringify({ planId: 'pro' }))).toBeNull()
    expect(parseCustomId({ userId: 'u1', planId: 'pro' })).toBeNull()
  })
})

describe('planRank', () => {
  it('orders plans from free to pro', () => {
    expect(planRank('free')).toBe(0)
    expect(planRank('basic')).toBe(1)
    expect(planRank('pro')).toBe(2)
    expect(planRank(null)).toBe(0)
    expect(planRank(undefined)).toBe(0)
  })
})

describe('shouldApplyPlan', () => {
  const NOW = new Date('2026-06-01T12:00:00.000Z')
  const active = (tier: string) => ({
    subscription_tier: tier,
    subscription_status: 'active',
    max_trades: 50,
    trial_ends_at: null,
    current_period_end: new Date(NOW.getTime() + 7 * 24 * 60 * 60 * 1000).toISOString(),
  })

  it('applies paid plans to trials, cancelled accounts and upgrades', () => {
    expect(shouldApplyPlan({ subscription_status: 'trial', subscription_tier: 'free' }, 'pro')).toBe(true)
    expect(shouldApplyPlan({ subscription_status: 'cancelled', subscription_tier: 'free' }, 'basic')).toBe(true)
    expect(shouldApplyPlan(active('basic'), 'pro')).toBe(true)
    expect(shouldApplyPlan(active('basic'), 'basic')).toBe(true)
  })

  it('never downgrades an active higher plan', () => {
    expect(shouldApplyPlan(active('pro'), 'basic', NOW)).toBe(false)
  })

  it('allows any plan once the higher paid period has lapsed', () => {
    const lapsed = { ...active('pro'), current_period_end: '2026-05-01T00:00:00.000Z' }
    expect(shouldApplyPlan(lapsed, 'basic', NOW)).toBe(true)
  })

  it('ignores unknown or free plan ids', () => {
    expect(shouldApplyPlan({ subscription_status: 'trial', subscription_tier: 'free' }, 'enterprise')).toBe(false)
    expect(shouldApplyPlan({ subscription_status: 'trial', subscription_tier: 'free' }, 'free')).toBe(false)
  })
})

describe('isDuplicatePurchase', () => {
  const NOW = new Date('2026-06-01T12:00:00.000Z')
  const activeBasic = {
    subscription_tier: 'basic',
    subscription_status: 'active',
    max_trades: 50,
    current_period_end: '2026-06-20T00:00:00.000Z',
    cancel_at_period_end: false,
  }

  it('refuses a second month of the plan that is already running', () => {
    expect(isDuplicatePurchase(activeBasic, 'basic', 'month', NOW)).toBe(true)
  })

  it('lets a monthly customer switch to annual', () => {
    // The whole point of the exception: the yearly price stacks 365 days onto
    // whatever is left, so nobody pays twice for the same month.
    expect(isDuplicatePurchase(activeBasic, 'basic', 'year', NOW)).toBe(false)
  })

  it('allows an upgrade, a lapsed period and a cancelled renewal', () => {
    expect(isDuplicatePurchase(activeBasic, 'pro', 'month', NOW)).toBe(false)
    expect(
      isDuplicatePurchase({ ...activeBasic, current_period_end: '2026-05-01T00:00:00.000Z' }, 'basic', 'month', NOW)
    ).toBe(false)
    expect(
      isDuplicatePurchase({ ...activeBasic, cancel_at_period_end: true }, 'basic', 'month', NOW)
    ).toBe(false)
    expect(
      isDuplicatePurchase({ subscription_status: 'trial', subscription_tier: 'free' }, 'basic', 'month', NOW)
    ).toBe(false)
  })
})

describe('applyPaidOrder cadence', () => {
  beforeEach(() => {
    db.calls = []
  })

  it('grants a year through apply_annual_order', async () => {
    const result = await applyPaidOrder({
      userId: 'u1',
      planId: 'basic',
      amount: '120.00',
      provider: 'paddle',
      providerEventId: 'paddle:txn:1',
      interval: 'year',
    })

    expect(result).toEqual({ applied: true, reason: 'applied' })
    expect(db.calls).toHaveLength(1)
    expect(db.calls[0].name).toBe('apply_annual_order')
    expect(db.calls[0].args).toMatchObject({ p_plan_id: 'basic', p_amount: 120 })
  })

  it('grants a month through apply_paid_order', async () => {
    await applyPaidOrder({
      userId: 'u1',
      planId: 'pro',
      amount: '29.00',
      provider: 'paddle',
      providerEventId: 'paddle:txn:2',
    })

    expect(db.calls[0].name).toBe('apply_paid_order')
  })

  it('refuses a monthly amount for a yearly order without charging the database', async () => {
    // What a monthly price id pasted into an _ANNUAL slot would produce: the
    // customer pays $12 and nothing is granted, rather than $12 buying a year.
    const result = await applyPaidOrder({
      userId: 'u1',
      planId: 'basic',
      amount: '12.00',
      provider: 'paddle',
      providerEventId: 'paddle:txn:3',
      interval: 'year',
    })

    expect(result).toEqual({ applied: false, reason: 'amount_mismatch' })
    expect(db.calls).toHaveLength(0)
  })
})
