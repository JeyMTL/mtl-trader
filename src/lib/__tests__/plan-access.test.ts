import { describe, expect, it } from 'vitest'
import {
  AI_REVIEW_QUOTA,
  TRIAL_DAILY_LIMITS,
  TRIAL_DAYS,
  aiReviewQuota,
  canUseFeature,
  hasProTools,
  isProTimeframe,
  trialDailyLimit,
  type AccountState,
} from '@/lib/subscription'

const PRO_FEATURES = [
  'ai_review',
  'replay',
  'backtest',
  'fast_timeframes',
  'push_alerts',
  'hard_lock',
] as const

/** A paid account with 20 days left. */
function paid(tier: 'basic' | 'pro'): AccountState {
  return {
    subscription_tier: tier,
    subscription_status: 'active',
    trial_ends_at: null,
    max_trades: -1,
    current_period_end: new Date(Date.now() + 20 * 86_400_000).toISOString(),
    cancel_at_period_end: false,
  }
}

const TRIAL: AccountState = {
  subscription_tier: 'free',
  subscription_status: 'trial',
  trial_ends_at: new Date(Date.now() + 10 * 86_400_000).toISOString(),
  max_trades: -1,
  current_period_end: null,
  cancel_at_period_end: false,
}

const EXPIRED: AccountState = {
  subscription_tier: 'pro',
  subscription_status: 'active',
  trial_ends_at: null,
  max_trades: -1,
  current_period_end: new Date(Date.now() - 60_000).toISOString(),
  cancel_at_period_end: false,
}

const LAPSED_TRIAL: AccountState = {
  subscription_tier: 'free',
  subscription_status: 'trial',
  trial_ends_at: new Date(Date.now() - 60_000).toISOString(),
  max_trades: -1,
  current_period_end: null,
  cancel_at_period_end: false,
}

describe('canUseFeature', () => {
  it('lets a trial use every feature, including Pro-only ones', () => {
    for (const feature of [...PRO_FEATURES, 'sync'] as const) {
      expect(canUseFeature(TRIAL, feature)).toEqual({ allowed: true, reason: 'trial' })
    }
  })

  it('lets Pro use everything', () => {
    for (const feature of [...PRO_FEATURES, 'sync'] as const) {
      expect(canUseFeature(paid('pro'), feature).allowed, feature).toBe(true)
    }
  })

  it('keeps sync on Basic, withholding every Pro tool', () => {
    // Autosync is the reason Basic is worth paying for; gating it at Pro left
    // Basic customers hand-entering every fill.
    expect(canUseFeature(paid('basic'), 'sync')).toEqual({ allowed: true, reason: 'ok' })
    for (const feature of PRO_FEATURES) {
      expect(canUseFeature(paid('basic'), feature), feature).toEqual({
        allowed: false,
        reason: 'pro_required',
      })
    }
  })

  it('refuses a lapsed period even when the tier still says pro', () => {
    expect(canUseFeature(EXPIRED, 'ai_review')).toEqual({
      allowed: false,
      reason: 'subscription_required',
    })
  })

  it('refuses an expired trial', () => {
    expect(canUseFeature(LAPSED_TRIAL, 'replay')).toEqual({
      allowed: false,
      reason: 'subscription_required',
    })
  })

  it('refuses an account with no subscription at all', () => {
    expect(canUseFeature({}, 'ai_review').allowed).toBe(false)
  })
})

describe('trialDailyLimit', () => {
  it('caps the AI review and the backtester at one a day during the trial', () => {
    expect(trialDailyLimit('ai_review', TRIAL)).toBe(1)
    expect(trialDailyLimit('backtest', TRIAL)).toBe(1)
  })

  it('leaves the rest of the trial open', () => {
    for (const feature of ['replay', 'hard_lock', 'fast_timeframes', 'push_alerts'] as const) {
      expect(trialDailyLimit(feature, TRIAL)).toBeNull()
    }
  })

  it('applies to nobody but a running trial', () => {
    expect(trialDailyLimit('ai_review', paid('pro'))).toBeNull()
    expect(trialDailyLimit('ai_review', paid('basic'))).toBeNull()
    expect(trialDailyLimit('backtest', EXPIRED)).toBeNull()
    expect(trialDailyLimit('backtest', LAPSED_TRIAL)).toBeNull()
  })
})

describe('aiReviewQuota', () => {
  it('gives the trial one a day for each of its days', () => {
    expect(aiReviewQuota(TRIAL)).toBe(TRIAL_DAYS * (TRIAL_DAILY_LIMITS.ai_review ?? 0))
    expect(aiReviewQuota(TRIAL)).toBe(3)
  })

  it('gives Basic none and Pro forty, because the AI review is sold with Pro', () => {
    expect(aiReviewQuota(paid('basic'))).toBe(0)
    expect(aiReviewQuota(paid('pro'))).toBe(40)
  })

  it('gives nothing once the period ends', () => {
    expect(aiReviewQuota(EXPIRED)).toBe(0)
    expect(aiReviewQuota(LAPSED_TRIAL)).toBe(0)
  })

  it('never returns a negative or unknown allowance', () => {
    expect(aiReviewQuota({ subscription_tier: 'mystery', subscription_status: 'active', current_period_end: new Date(Date.now() + 86_400_000).toISOString() })).toBe(0)
    for (const value of Object.values(AI_REVIEW_QUOTA)) expect(value).toBeGreaterThanOrEqual(0)
  })
})

describe('hasProTools', () => {
  it('counts a live trial and an active Pro period, and nothing else', () => {
    expect(hasProTools(TRIAL)).toBe(true)
    expect(hasProTools(paid('pro'))).toBe(true)
    expect(hasProTools(paid('basic'))).toBe(false)
    expect(hasProTools(EXPIRED)).toBe(false)
    expect(hasProTools(LAPSED_TRIAL)).toBe(false)
    expect(hasProTools({})).toBe(false)
  })
})

describe('isProTimeframe', () => {
  it('withholds 5s, 10s and 15s only', () => {
    for (const key of ['5s', '10s', '15s']) expect(isProTimeframe(key), key).toBe(true)
    for (const key of ['30s', '45s', '1m', '5m', '1h', '1d']) {
      expect(isProTimeframe(key), key).toBe(false)
    }
  })
})
