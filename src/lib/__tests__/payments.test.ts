import { describe, it, expect } from 'vitest'
import { parseCustomId, PAID_PLAN_PRICES } from '@/lib/payments'
import { planRank, shouldApplyPlan } from '@/lib/subscription'

describe('PAID_PLAN_PRICES', () => {
  it('excludes the free plan and matches displayed prices', () => {
    expect(PAID_PLAN_PRICES).toEqual({ basic: '2.50', pro: '5.00' })
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
