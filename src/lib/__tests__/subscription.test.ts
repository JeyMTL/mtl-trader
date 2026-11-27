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
  formatTrialRemaining,
  trialRemaining,
  subscriptionState,
  hasPaidPlan,
  isTimeframeOpen,
  TRIAL_DAYS,
  PERIOD_DAYS,
} from '@/lib/subscription'

const NOW = new Date('2026-06-01T12:00:00.000Z')
const day = (n: number) => new Date(NOW.getTime() + n * 24 * 60 * 60 * 1000)
const iso = (d: Date) => d.toISOString()

describe('chart candle sizes by plan', () => {
  const active = (tier: string) => ({
    subscription_status: 'active',
    subscription_tier: tier,
    current_period_end: iso(day(9)),
  })

  it('keeps the free chart from a minute up', () => {
    const access = { pro: false, paid: false }
    expect(isTimeframeOpen('30s', access)).toBe(false)
    expect(isTimeframeOpen('45s', access)).toBe(false)
    expect(isTimeframeOpen('1m', access)).toBe(true)
    expect(isTimeframeOpen('1d', access)).toBe(true)
  })

  it('sells 30s and 45s with Basic and the seconds sizes with Pro', () => {
    const basic = { pro: false, paid: true }
    expect(isTimeframeOpen('30s', basic)).toBe(true)
    expect(isTimeframeOpen('15s', basic)).toBe(false)
    expect(isTimeframeOpen('15s', { pro: true, paid: true })).toBe(true)
  })

  it('counts a live trial as paid, and a lapsed plan as not', () => {
    expect(hasPaidPlan({ subscription_status: 'trial', trial_ends_at: iso(day(2)) }, NOW)).toBe(true)
    expect(hasPaidPlan(active('basic'), NOW)).toBe(true)
    // The stored tier can still say pro long after the period ended.
    expect(
      hasPaidPlan({ ...active('pro'), current_period_end: iso(day(-1)) }, NOW)
    ).toBe(false)
  })
})

describe('maxTradesForPlan', () => {
  it('maps each plan id to its allowance', () => {
    // The free tier is a real tier: 30 a month, with the prop-firm simulator.
    expect(maxTradesForPlan('free')).toBe(30)
    // Unlimited on Basic too: a cap there made paying worse than the trial.
    expect(maxTradesForPlan('basic')).toBe(UNLIMITED)
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

  it('falls back to the free allowance once a trial has expired', () => {
    expect(effectiveMaxTrades({ subscription_status: 'trial', trial_ends_at: '2026-01-01T00:00:00Z', max_trades: 50 }, NOW)).toBe(30)
  })

  it('uses the stored max inside a paid period', () => {
    expect(effectiveMaxTrades({
      subscription_status: 'active',
      subscription_tier: 'basic',
      max_trades: 50,
      current_period_end: iso(day(10)),
    }, NOW)).toBe(50)
  })

  it('drops to the free allowance when the paid period has lapsed', () => {
    expect(effectiveMaxTrades({
      subscription_status: 'active',
      subscription_tier: 'pro',
      max_trades: UNLIMITED,
      current_period_end: iso(day(-1)),
    }, NOW)).toBe(30)
  })

  it('treats a missing max inside a paid period as unlimited, like the trigger', () => {
    expect(effectiveMaxTrades({
      subscription_status: 'active',
      subscription_tier: 'basic',
      max_trades: null,
      current_period_end: iso(day(3)),
    }, NOW)).toBe(UNLIMITED)
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

  it('is the free allowance once access has lapsed', () => {
    expect(monthlyRemaining({
      subscription_status: 'active',
      subscription_tier: 'pro',
      max_trades: UNLIMITED,
      current_period_end: iso(day(-2)),
    }, 0, NOW)).toBe(30)
    expect(monthlyRemaining({
      subscription_status: 'active',
      subscription_tier: 'pro',
      max_trades: UNLIMITED,
      current_period_end: iso(day(-2)),
    }, 12, NOW)).toBe(18)
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
    expect(basic.max_trades).toBe(UNLIMITED)
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

  it('expiry and revocation fall back to the free allowance', () => {
    expect(expiredFields()).toEqual({
      subscription_tier: 'free',
      subscription_status: 'expired',
      max_trades: 30,
      trades_remaining: 30,
      cancel_at_period_end: false,
    })
    expect(revokedFields()).toEqual({
      subscription_tier: 'free',
      subscription_status: 'cancelled',
      max_trades: 30,
      trades_remaining: 30,
      cancel_at_period_end: false,
    })
  })

  it('trialFields starts a fresh 3-day unlimited trial', () => {
    const fields = trialFields(NOW)
    expect(fields.subscription_status).toBe('trial')
    expect(fields.max_trades).toBe(UNLIMITED)
    expect(fields.current_period_end).toBeNull()
    const days = (new Date(fields.trial_ends_at).getTime() - NOW.getTime()) / (24 * 60 * 60 * 1000)
    expect(days).toBe(TRIAL_DAYS)
    expect(TRIAL_DAYS).toBe(3)
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

describe('trial countdown', () => {
  const start = new Date('2026-11-22T12:00:00Z')
  const inSevenDays = new Date(start.getTime() + 7 * 86_400_000).toISOString()

  it('counts from the trial end and not from app usage', () => {
    expect(trialRemaining(inSevenDays, start)).toEqual({
      expired: false,
      days: 7,
      hours: 0,
      minutes: 0,
    })

    // One day later, with the same end instant, there is a day less left.
    const tomorrow = new Date(start.getTime() + 86_400_000)
    expect(trialRemaining(inSevenDays, tomorrow)).toMatchObject({ days: 6, hours: 0 })
  })

  it('shows days and hours, then hours and minutes, then minutes', () => {
    expect(formatTrialRemaining(inSevenDays, start)).toBe('7d 0h left')

    const sixDaysElevenHours = new Date(start.getTime() + 6 * 86_400_000 + 11 * 3_600_000)
    expect(formatTrialRemaining(inSevenDays, sixDaysElevenHours)).toBe('13h 0m left')

    const elevenHoursForty = new Date(new Date(inSevenDays).getTime() - 23 * 3_600_000 - 40 * 60_000)
    expect(formatTrialRemaining(inSevenDays, elevenHoursForty)).toBe('23h 40m left')

    const sevenMinutes = new Date(new Date(inSevenDays).getTime() - 7 * 60_000)
    expect(formatTrialRemaining(inSevenDays, sevenMinutes)).toBe('7m left')
  })

  it('says the trial ended instead of counting past zero', () => {
    const after = new Date(new Date(inSevenDays).getTime() + 60_000)
    expect(trialRemaining(inSevenDays, after)?.expired).toBe(true)
    expect(formatTrialRemaining(inSevenDays, after)).toBe('Trial ended')
  })

  it('returns nothing when there is no trial date to count', () => {
    expect(trialRemaining(null, start)).toBeNull()
    expect(trialRemaining('not a date', start)).toBeNull()
    expect(formatTrialRemaining(null, start)).toBe('')
  })
})
