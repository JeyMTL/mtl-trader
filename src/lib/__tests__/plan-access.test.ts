import { describe, expect, it } from 'vitest'
import {
  AI_REVIEW_QUOTA,
  aiReviewQuota,
  canUseFeature,
  type AccountState,
} from '@/lib/subscription'

/** A paid account with 20 days left. */
function paid(tier: 'basic' | 'pro'): AccountState {
  return {
    subscription_tier: tier,
    subscription_status: 'active',
    trial_ends_at: null,
    max_trades: tier === 'pro' ? -1 : 50,
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
    for (const feature of ['ai_review', 'replay', 'backtest', 'sync'] as const) {
      expect(canUseFeature(TRIAL, feature)).toEqual({ allowed: true, reason: 'trial' })
    }
  })

  it('lets Pro use everything', () => {
    for (const feature of ['ai_review', 'replay', 'backtest', 'sync'] as const) {
      expect(canUseFeature(paid('pro'), feature).allowed, feature).toBe(true)
    }
  })

  it('keeps sync and the AI review on Basic, withholding the analysis tools', () => {
    expect(canUseFeature(paid('basic'), 'ai_review')).toEqual({ allowed: true, reason: 'ok' })
    // Autosync is the reason Basic is worth paying for; gating it at Pro left
    // Basic customers hand-entering every fill.
    expect(canUseFeature(paid('basic'), 'sync')).toEqual({ allowed: true, reason: 'ok' })
    for (const feature of ['replay', 'backtest'] as const) {
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

describe('aiReviewQuota', () => {
  it('gives the trial a Pro allowance', () => {
    expect(aiReviewQuota(TRIAL)).toBe(AI_REVIEW_QUOTA.pro)
  })

  it('gives Basic a review a day and Pro the full monthly allowance', () => {
    expect(aiReviewQuota(paid('basic'))).toBe(30)
    expect(aiReviewQuota(paid('pro'))).toBe(200)
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
