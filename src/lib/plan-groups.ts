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
    { title: 'Charting & analysis', featureIndexes: [4, 5] },
    { title: 'Risk & import', featureIndexes: [2, 6] },
  ],
  basic: [
    { title: 'Journaling & sync', featureIndexes: [0, 1, 2, 9, 10, 11] },
    { title: 'Charting & analysis', featureIndexes: [4, 5, 6, 7, 8] },
    { title: 'Risk & execution', featureIndexes: [3] },
  ],
  pro: [
    { title: 'Journaling & AI', featureIndexes: [0, 2] },
    { title: 'Risk & execution', featureIndexes: [1, 6, 8] },
    { title: 'Charting & replay', featureIndexes: [3, 4, 5, 7] },
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
