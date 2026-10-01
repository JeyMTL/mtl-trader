import { describe, it, expect } from 'vitest'
import {
  UNLIMITED,
  maxTradesForPlan,
  isTrialActive,
  effectiveMaxTrades,
  monthlyRemaining,
  planFields,
  cancelledFields,
  trialFields,
  trialEndsAtFrom,
  TRIAL_DAYS,
} from '@/lib/subscription'

const NOW = new Date('2026-06-01T12:00:00.000Z')

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

describe('effectiveMaxTrades', () => {
  it('treats an active trial as unlimited regardless of stored max', () => {
    expect(effectiveMaxTrades({ subscription_status: 'trial', trial_ends_at: trialEndsAtFrom(NOW), max_trades: 10 }, NOW)).toBe(UNLIMITED)
  })

  it('uses the stored max once the trial is over', () => {
    expect(effectiveMaxTrades({ subscription_status: 'trial', trial_ends_at: '2026-01-01T00:00:00Z', max_trades: 50 }, NOW)).toBe(50)
  })

  it('defaults a missing max to zero', () => {
    expect(effectiveMaxTrades({ subscription_status: 'active', trial_ends_at: null, max_trades: null }, NOW)).toBe(0)
  })
})

describe('monthlyRemaining', () => {
  it('is unlimited during a trial', () => {
    expect(monthlyRemaining({ subscription_status: 'trial', trial_ends_at: trialEndsAtFrom(NOW), max_trades: 50 }, 999, NOW)).toBe(UNLIMITED)
  })

  it('subtracts trades used and never goes negative', () => {
    const account = { subscription_status: 'active', trial_ends_at: null, max_trades: 50 }
    expect(monthlyRemaining(account, 10, NOW)).toBe(40)
    expect(monthlyRemaining(account, 50, NOW)).toBe(0)
    expect(monthlyRemaining(account, 80, NOW)).toBe(0)
  })
})

describe('column value builders', () => {
  it('planFields reflects the plan allowance', () => {
    expect(planFields('basic')).toEqual({ subscription_tier: 'basic', subscription_status: 'active', max_trades: 50, trades_remaining: 50 })
    expect(planFields('pro')).toEqual({ subscription_tier: 'pro', subscription_status: 'active', max_trades: UNLIMITED, trades_remaining: UNLIMITED })
  })

  it('cancelledFields revokes access', () => {
    expect(cancelledFields()).toEqual({ subscription_tier: 'free', subscription_status: 'cancelled', max_trades: 0, trades_remaining: 0 })
  })

  it('trialFields starts a fresh 30-day unlimited trial', () => {
    const fields = trialFields(NOW)
    expect(fields.subscription_status).toBe('trial')
    expect(fields.max_trades).toBe(UNLIMITED)
    const days = (new Date(fields.trial_ends_at).getTime() - NOW.getTime()) / (24 * 60 * 60 * 1000)
    expect(days).toBe(TRIAL_DAYS)
  })
})
