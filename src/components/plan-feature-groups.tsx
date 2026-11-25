import { Check } from 'lucide-react'

import { groupsForPlan } from '@/lib/plan-groups'
import type { SubscriptionPlan } from '@/types'

interface PlanFeatureGroupsProps {
  plan: SubscriptionPlan
  /** Show only the first N features in each group, for the landing page. */
  perGroup?: number
}

export function PlanFeatureGroups({ plan, perGroup }: PlanFeatureGroupsProps) {
  const groups = groupsForPlan(plan)

  return (
    <div className="space-y-5">
      {groups.map((group) => {
        const indexes = perGroup
          ? group.featureIndexes.slice(0, perGroup)
          : group.featureIndexes
        return (
          <div key={group.title}>
            <p className="mb-2.5 text-[11px] font-semibold uppercase tracking-[0.12em] text-gray-500">
              {group.title}
            </p>
            <ul className="space-y-2.5">
              {indexes.map((index) => (
                <li
                  key={`${group.title}-${index}`}
                  className="flex items-start gap-2.5 text-sm leading-relaxed text-gray-300"
                >
                  <Check className="mt-0.5 h-4 w-4 shrink-0 text-success" />
                  <span>{plan.features[index]}</span>
                </li>
              ))}
            </ul>
          </div>
        )
      })}
    </div>
  )
}
