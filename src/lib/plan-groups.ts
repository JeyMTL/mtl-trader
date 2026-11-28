import type { SubscriptionPlan } from '@/types'

/**
 * Presentation-only grouping for the pricing cards.
 *
 * The indexes point into the canonical `PLANS[].features` list instead of
 * copying the strings, so a plan can never advertise a feature it does not
 * actually include. `plan-groups.test.ts` checks that every feature is shown
 * exactly once.
 */
export interface PlanFeatureGroup {
  title: string
  featureIndexes: number[]
}

export const PLAN_FEATURE_GROUPS: Record<string, PlanFeatureGroup[]> = {
  free: [
    { title: 'Trial & journal', featureIndexes: [0, 1, 3] },
    { title: 'Market & analysis', featureIndexes: [4, 5] },
    { title: 'Risk & import', featureIndexes: [2, 6] },
  ],
  basic: [
    { title: 'Journaling & sync', featureIndexes: [0, 1, 2, 9] },
    { title: 'Market & analytics', featureIndexes: [4, 5, 6, 7] },
    { title: 'Risk & data', featureIndexes: [3, 8] },
  ],
  pro: [
    { title: 'Journaling & AI', featureIndexes: [0, 2] },
    { title: 'Risk & alerts', featureIndexes: [1, 5] },
    { title: 'Analysis & support', featureIndexes: [3, 4, 6] },
  ],
}

export function groupsForPlan(plan: SubscriptionPlan): PlanFeatureGroup[] {
  return (
    PLAN_FEATURE_GROUPS[plan.id] ?? [
      {
        title: 'Includes',
        featureIndexes: plan.features.map((_, index) => index),
      },
    ]
  )
}
