import { describe, expect, it } from 'vitest'

import { PLAN_TAGLINES, PLANS } from '@/lib/plans'
import { groupsForPlan } from '@/lib/plan-groups'

describe('plan feature groups', () => {
  for (const plan of PLANS) {
    it(`${plan.id} shows every feature exactly once`, () => {
      const groups = groupsForPlan(plan)
      const indexes = groups.flatMap((group) => group.featureIndexes)

      expect(groups.length).toBeGreaterThan(0)
      expect(groups.every((group) => group.featureIndexes.length > 0)).toBe(true)
      expect(new Set(indexes).size).toBe(indexes.length)
      expect([...indexes].sort((a, b) => a - b)).toEqual(
        plan.features.map((_, index) => index)
      )
    })

    it(`${plan.id} has a pricing-card tagline`, () => {
      expect(PLAN_TAGLINES[plan.id]).toBeTruthy()
    })
  }
})
