import { describe, it, expect } from 'vitest'
import {
  UNLIMITED,
  maxTradesForPlan,
  isTrialActive,
  isSubscriptionActive,
  effectiveMaxTrades,
  monthlyRemaining,
  planFields,
  cancelAtPeriodEndFields,
  expiredFields,
  revokedFields,
  trialFields,
  trialEndsAtFrom,
  periodEndFrom,
  nextPeriodEnd,
  daysLeftInPeriod,
  subscriptionState,
  TRIAL_DAYS,
  PERIOD_DAYS,
} from '@/lib/subscription'

const NOW = new Date('2026-06-01T12:00:00.000Z')
const day = (n: number) => new Date(NOW.getTime() + n * 24 * 60 * 60 * 1000)
const iso = (d: Date) => d.toISOString()

describe('maxTradesForPlan', () => {
  it('maps each plan id to its allowance', () => {
    expect(maxTradesForPlan('free')).toBe(UNLIMITED)
    expect(maxTradesForPlan('basic')).toBe(50)
    expect(maxTradesForPlan('pro')).toBe(UNLIMITED)
  })

  it('gives unknown plans no allowance', () => {
    expect(maxTradesForPlan('enterprise')).toBe(0)
  })
})

describe('isTrialActive', () => {
  it('is true for an unexpired trial', () => {
    expect(isTrialActive({ subscription_status: 'trial', trial_ends_at: trialEndsAtFrom(NOW) }, NOW)).toBe(true)
  })

  it('is false once the trial end has passed', () => {
    expect(isTrialActive({ subscription_status: 'trial', trial_ends_at: '2026-05-31T00:00:00Z' }, NOW)).toBe(false)
  })

  it('is false when the status is not trial or the date is missing', () => {
    expect(isTrialActive({ subscription_status: 'active', trial_ends_at: trialEndsAtFrom(NOW) }, NOW)).toBe(false)
    expect(isTrialActive({ subscription_status: 'trial', trial_ends_at: null }, NOW)).toBe(false)
  })
})

describe('isSubscriptionActive', () => {
  const paid = (overrides: Record<string, unknown> = {}) => ({
    subscription_status: 'active',
    subscription_tier: 'pro',
    max_trades: UNLIMITED,
    current_period_end: iso(day(5)),
    ...overrides,
  })

  it('is true inside a paid period', () => {
    expect(isSubscriptionActive(paid(), NOW)).toBe(true)
  })

  it('is false once the period has ended', () => {
    expect(isSubscriptionActive(paid({ current_period_end: iso(day(-1)) }), NOW)).toBe(false)
  })

  it('never treats a missing period as lifetime access', () => {
    expect(isSubscriptionActive(paid({ current_period_end: null }), NOW)).toBe(false)
  })

  it('requires a paid tier and an active status', () => {
    expect(isSubscriptionActive(paid({ subscription_tier: 'free' }), NOW)).toBe(false)
    expect(isSubscriptionActive(paid({ subscription_status: 'cancelled' }), NOW)).toBe(false)
    expect(isSubscriptionActive(paid({ subscription_status: 'expired' }), NOW)).toBe(false)
  })
})

describe('effectiveMaxTrades', () => {
  it('treats an active trial as unlimited regardless of stored max', () => {
    expect(effectiveMaxTrades({ subscription_status: 'trial', trial_ends_at: trialEndsAtFrom(NOW), max_trades: 10 }, NOW)).toBe(UNLIMITED)
  })

  it('gives no allowance to an expired trial even if max_trades is set', () => {
    expect(effectiveMaxTrades({ subscription_status: 'trial', trial_ends_at: '2026-01-01T00:00:00Z', max_trades: 50 }, NOW)).toBe(0)
  })

  it('uses the stored max inside a paid period', () => {
    expect(effectiveMaxTrades({
      subscription_status: 'active',
      subscription_tier: 'basic',
      max_trades: 50,
      current_period_end: iso(day(10)),
    }, NOW)).toBe(50)
  })

  it('drops to zero when the paid period has lapsed', () => {
    expect(effectiveMaxTrades({
      subscription_status: 'active',
      subscription_tier: 'pro',
      max_trades: UNLIMITED,
      current_period_end: iso(day(-1)),
    }, NOW)).toBe(0)
  })

  it('defaults a missing max to zero', () => {
    expect(effectiveMaxTrades({
      subscription_status: 'active',
      subscription_tier: 'basic',
      max_trades: null,
      current_period_end: iso(day(3)),
    }, NOW)).toBe(0)
  })
})

describe('monthlyRemaining', () => {
  it('is unlimited during a trial', () => {
    expect(monthlyRemaining({ subscription_status: 'trial', trial_ends_at: trialEndsAtFrom(NOW), max_trades: 50 }, 999, NOW)).toBe(UNLIMITED)
  })

  it('subtracts trades used and never goes negative', () => {
    const account = {
      subscription_status: 'active',
      subscription_tier: 'basic',
      max_trades: 50,
      current_period_end: iso(day(10)),
    }
    expect(monthlyRemaining(account, 10, NOW)).toBe(40)
    expect(monthlyRemaining(account, 50, NOW)).toBe(0)
    expect(monthlyRemaining(account, 80, NOW)).toBe(0)
  })

  it('is zero once access has lapsed', () => {
    expect(monthlyRemaining({
      subscription_status: 'active',
      subscription_tier: 'pro',
      max_trades: UNLIMITED,
      current_period_end: iso(day(-2)),
    }, 0, NOW)).toBe(0)
  })
})

describe('billing periods', () => {
  it('starts a 30-day period', () => {
    expect(periodEndFrom(NOW)).toBe(iso(day(PERIOD_DAYS)))
  })

  it('stacks a renewal onto unexpired time', () => {
    expect(nextPeriodEnd({ current_period_end: iso(day(10)) }, NOW)).toBe(iso(day(40)))
  })

  it('starts a fresh period when the old one has lapsed', () => {
    expect(nextPeriodEnd({ current_period_end: iso(day(-10)) }, NOW)).toBe(iso(day(PERIOD_DAYS)))
  })

  it('reports the days left in the current period', () => {
    expect(daysLeftInPeriod({
      subscription_status: 'active',
      subscription_tier: 'pro',
      current_period_end: iso(day(12)),
    }, NOW)).toBe(12)
    expect(daysLeftInPeriod({
      subscription_status: 'active',
      subscription_tier: 'pro',
      current_period_end: iso(day(-1)),
    }, NOW)).toBe(0)
  })
})

describe('column value builders', () => {
  it('planFields activates a period of the right length', () => {
    const basic = planFields('basic', { now: NOW })
    expect(basic.subscription_tier).toBe('basic')
    expect(basic.subscription_status).toBe('active')
    expect(basic.max_trades).toBe(50)
    expect(basic.current_period_end).toBe(iso(day(PERIOD_DAYS)))
    expect(basic.cancel_at_period_end).toBe(false)
    expect(basic.last_payment_at).toBe(iso(NOW))

    const pro = planFields('pro', { now: NOW, currentPeriodEnd: iso(day(3)), periodActive: true })
    expect(pro.max_trades).toBe(UNLIMITED)
    expect(pro.current_period_end).toBe(iso(day(3 + PERIOD_DAYS)))
    expect(pro.current_period_start).toBeUndefined()
  })

  it('cancelling keeps access until the period ends', () => {
    expect(cancelAtPeriodEndFields()).toEqual({ cancel_at_period_end: true })
  })

  it('expiry and revocation remove access', () => {
    expect(expiredFields()).toEqual({
      subscription_tier: 'free',
      subscription_status: 'expired',
      max_trades: 0,
      trades_remaining: 0,
      cancel_at_period_end: false,
    })
    expect(revokedFields()).toEqual({
      subscription_tier: 'free',
      subscription_status: 'cancelled',
      max_trades: 0,
      trades_remaining: 0,
      cancel_at_period_end: false,
    })
  })

  it('trialFields starts a fresh 30-day unlimited trial', () => {
    const fields = trialFields(NOW)
    expect(fields.subscription_status).toBe('trial')
    expect(fields.max_trades).toBe(UNLIMITED)
    expect(fields.current_period_end).toBeNull()
    const days = (new Date(fields.trial_ends_at).getTime() - NOW.getTime()) / (24 * 60 * 60 * 1000)
    expect(days).toBe(TRIAL_DAYS)
  })
})

describe('subscriptionState', () => {
  it('resolves the stored status against the clock', () => {
    expect(subscriptionState({ subscription_status: 'trial', trial_ends_at: iso(day(2)) }, NOW)).toBe('trial')
    expect(subscriptionState({ subscription_status: 'trial', trial_ends_at: iso(day(-2)) }, NOW)).toBe('expired')
    expect(subscriptionState({
      subscription_status: 'active',
      subscription_tier: 'pro',
      current_period_end: iso(day(2)),
    }, NOW)).toBe('active')
    expect(subscriptionState({
      subscription_status: 'active',
      subscription_tier: 'pro',
      current_period_end: iso(day(-2)),
    }, NOW)).toBe('expired')
    expect(subscriptionState({ subscription_status: 'cancelled' }, NOW)).toBe('cancelled')
    expect(subscriptionState({ subscription_status: 'expired' }, NOW)).toBe('expired')
  })
})
