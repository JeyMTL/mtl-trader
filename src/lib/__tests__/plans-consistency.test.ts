import { describe, expect, it } from 'vitest'
import { PLANS } from '@/lib/plans'
import { PAID_PLAN_PRICES } from '@/lib/payments'

/**
 * The plan catalogue is read by the pricing page, the settings page, the PayPal
 * checkout, the Paddle checkout and `apply_paid_order`. These guards catch the
 * drift that used to let the UI advertise a price the server would reject.
 */
describe('plan catalogue', () => {
  it('lists every plan once', () => {
    const ids = PLANS.map((plan) => plan.id)
    expect(new Set(ids).size).toBe(ids.length)
    expect(ids).toContain('free')
  })

  it('prices each paid plan exactly as the checkout charges it', () => {
    const paid = PLANS.filter((plan) => plan.price > 0)
    expect(paid.map((plan) => plan.id).sort()).toEqual(Object.keys(PAID_PLAN_PRICES).sort())
    for (const plan of paid) {
      expect(PAID_PLAN_PRICES[plan.id]).toBe(plan.price.toFixed(2))
    }
  })

  it('only treats priced plans as purchasable', () => {
    for (const plan of PLANS) {
      expect(Boolean(PAID_PLAN_PRICES[plan.id])).toBe(plan.price > 0)
    }
  })

  it('sells a year for ten months and never for more than twelve', () => {
    for (const plan of PLANS.filter((p) => typeof p.annual_price === 'number')) {
      expect(plan.annual_price).toBe(plan.price * 10)
      expect(plan.annual_price!).toBeLessThan(plan.price * 12)
    }
    expect(PLANS.filter((p) => p.annual_price).map((p) => p.id).sort()).toEqual(['basic', 'pro'])
  })

  it('uses -1 only for the unlimited plans', () => {
    // Volume is not a differentiator: every plan, paid or not, is unlimited. A
    // cap on Basic is the one thing that made paying worse than the trial.
    expect(PLANS.filter((plan) => plan.max_trades === -1).map((plan) => plan.id).sort()).toEqual([
      'basic',
      'free',
      'pro',
    ])
    for (const plan of PLANS.filter((p) => p.max_trades !== -1)) {
      expect(plan.max_trades).toBeGreaterThan(0)
    }
  })
})
