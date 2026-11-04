import { describe, expect, it } from 'vitest'
import { PLAY_PRODUCTS, parsePlaySubscription } from '../google-play'

describe('parsePlaySubscription', () => {
  const active = {
    subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
    acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
    lineItems: [
      {
        productId: 'pro_year',
        expiryTime: '2027-01-01T00:00:00Z',
        offerDetails: { basePlanId: 'pro-year' },
      },
    ],
  }

  it('maps a live subscription onto a plan and its cadence', () => {
    const parsed = parsePlaySubscription(active, new Date('2026-11-03T00:00:00Z'))
    expect(parsed).not.toBeNull()
    expect(parsed?.planId).toBe('pro')
    expect(parsed?.interval).toBe('year')
    expect(parsed?.active).toBe(true)
    expect(parsed?.acknowledged).toBe(true)
    expect(parsed?.expiryTime).toBe('2027-01-01T00:00:00Z')
  })

  it('treats a canceled subscription as paid until its expiry', () => {
    const parsed = parsePlaySubscription(
      { ...active, subscriptionState: 'SUBSCRIPTION_STATE_CANCELED' },
      new Date('2026-11-03T00:00:00Z')
    )
    expect(parsed?.active).toBe(true)
  })

  it('does not grant access once the period has passed, whatever the state says', () => {
    const parsed = parsePlaySubscription(active, new Date('2027-02-01T00:00:00Z'))
    expect(parsed?.active).toBe(false)
  })

  it('refuses to grant access on hold or pending', () => {
    for (const state of ['SUBSCRIPTION_STATE_ON_HOLD', 'SUBSCRIPTION_STATE_PENDING']) {
      const parsed = parsePlaySubscription(
        { ...active, subscriptionState: state },
        new Date('2026-11-03T00:00:00Z')
      )
      expect(parsed?.active).toBe(false)
    }
  })

  it('leaves an unknown product without a plan instead of guessing one', () => {
    const parsed = parsePlaySubscription(
      { ...active, lineItems: [{ productId: 'someone_elses_sku' }] },
      new Date('2026-11-03T00:00:00Z')
    )
    expect(parsed?.planId).toBeNull()
  })

  it('returns null for a payload that is not a subscription', () => {
    expect(parsePlaySubscription(null)).toBeNull()
    expect(parsePlaySubscription([])).toBeNull()
  })
})

describe('PLAY_PRODUCTS', () => {
  it('covers both plans on both cadences', () => {
    expect(Object.keys(PLAY_PRODUCTS).sort()).toEqual([
      'basic_month',
      'basic_year',
      'pro_month',
      'pro_year',
    ])
  })
})
