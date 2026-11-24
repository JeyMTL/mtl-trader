'use client'

import { useState, useEffect, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import { ArrowLeft, Loader2 } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { PLANS } from '@/lib/plans'
import { authedFetch } from '@/lib/api'
import { useToast } from '@/components/toast'
import type { BillingInterval } from '@/types'

const PLAN_PRICES: Record<string, { name: string; amount: number }> = Object.fromEntries(
  PLANS.filter(p => p.price > 0).map(p => [p.id, { name: `${p.name} Plan`, amount: p.price }])
)

/** A year bought up front; only the plans that actually have a yearly price. */
const PLAN_ANNUAL_PRICES: Record<string, number> = Object.fromEntries(
  PLANS.filter(p => typeof p.annual_price === 'number' && p.annual_price > 0)
    .map(p => [p.id, p.annual_price as number])
)

/**
 * Card checkout for one plan.
 *
 * Paddle hosts the card form, so no card detail reaches this app; the webhook is
 * what grants the period, never the redirect back. Each cadence is a separate
 * Paddle price, so the buttons appear only when this deployment sells it — the
 * alternative is a button that fails after the customer has decided to pay.
 */
export default function PaymentPage() {
  const { toast } = useToast()
  const router = useRouter()
  const [selectedPlan, setSelectedPlan] = useState('')
  const [billing, setBilling] = useState<BillingInterval>('month')
  const [userId, setUserId] = useState<string | null>(null)
  const [monthlyPlans, setMonthlyPlans] = useState<string[]>([])
  const [annualPlans, setAnnualPlans] = useState<string[]>([])
  const [cardEnabled, setCardEnabled] = useState(false)
  const [cardLoading, setCardLoading] = useState(false)

  useEffect(() => {
    async function load() {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        router.push('/auth/login')
        return
      }
      setUserId(user.id)

      const urlPlan = new URLSearchParams(window.location.search).get('plan')
      if (urlPlan && PLAN_PRICES[urlPlan]) {
        setSelectedPlan(urlPlan)
      }

      try {
        const res = await fetch('/api/paddle/checkout')
        const data = await res.json().catch(() => null)
        setCardEnabled(Boolean(data?.enabled))
        setMonthlyPlans(Array.isArray(data?.plans) ? data.plans : [])
        setAnnualPlans(Array.isArray(data?.annual) ? data.annual : [])
      } catch {
        setCardEnabled(false)
      }
    }
    load()
  }, [router])

  const available = useCallback(
    (planId: string) =>
      cardEnabled && (billing === 'year' ? annualPlans : monthlyPlans).includes(planId),
    [cardEnabled, billing, annualPlans, monthlyPlans]
  )

  const handleCheckout = async () => {
    if (!selectedPlan || !userId || cardLoading || !available(selectedPlan)) return
    setCardLoading(true)

    try {
      const response = await authedFetch('/api/paddle/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ planId: selectedPlan, userId, interval: billing }),
      })
      const result = await response.json().catch(() => null)
      if (result?.url) {
        window.location.assign(result.url)
        return
      }
      toast(result?.error || 'Could not start the card checkout.', { tone: 'error' })
    } catch {
      toast('Could not start the card checkout. Check your connection and try again.', { tone: 'error' })
    }
    setCardLoading(false)
  }

  const price = billing === 'year' ? PLAN_ANNUAL_PRICES[selectedPlan] : PLAN_PRICES[selectedPlan]?.amount

  return (
    <div className="space-y-6 max-w-2xl">
      <div>
        <button onClick={() => router.back()} className="flex items-center gap-2 text-gray-400 hover:text-white mb-4 transition-colors">
          <ArrowLeft className="w-4 h-4" />
          Back
        </button>
        <h1 className="text-2xl font-bold text-white">Upgrade Plan</h1>
        <p className="text-gray-400 text-sm mt-1">Pay by card through Paddle, our merchant of record</p>
      </div>

      <div className="space-y-6">
        <div className="bg-surface border border-border rounded-xl p-6">
          <h2 className="text-lg font-semibold text-white mb-2">1. Select Plan</h2>
          <div className="mb-4 inline-flex rounded-full border border-border bg-background p-1">
            {(['month', 'year'] as const).map((option) => (
              <button
                key={option}
                onClick={() => setBilling(option)}
                aria-pressed={billing === option}
                className={`rounded-full px-3 py-1 text-xs font-medium transition-colors ${
                  billing === option ? 'bg-primary text-white' : 'text-gray-400 hover:text-white'
                }`}
              >
                {option === 'month' ? 'Monthly' : 'Annual · 2 months free'}
              </button>
            ))}
          </div>
          <div className="grid sm:grid-cols-2 gap-3">
            {Object.entries(PLAN_PRICES).map(([id, plan]) => (
              <button
                key={id}
                onClick={() => setSelectedPlan(id)}
                className={`p-4 rounded-lg border text-left transition-colors ${
                  selectedPlan === id
                    ? 'border-primary bg-primary/10'
                    : 'border-border hover:border-primary/50'
                }`}
              >
                <div className="font-medium text-white">{plan.name}</div>
                <div className="text-2xl font-bold text-white mt-1">
                  ${billing === 'year' ? PLAN_ANNUAL_PRICES[id] : plan.amount}
                  {billing === 'year' ? '/yr' : '/mo'}
                </div>
                {billing === 'year' && PLAN_ANNUAL_PRICES[id] && (
                  <div className="text-xs text-gray-500 mt-1">
                    ${(PLAN_ANNUAL_PRICES[id] / 12).toFixed(2)}/mo · two months free
                  </div>
                )}
              </button>
            ))}
          </div>
        </div>

        {selectedPlan && (
          <div className="bg-surface border border-border rounded-xl p-6">
            <h2 className="text-lg font-semibold text-white mb-4">2. Pay by card</h2>
            <p className="text-gray-400 text-sm mb-4">
              {billing === 'year'
                ? 'A single card payment covers 365 days from the moment Paddle confirms it.'
                : 'A monthly card subscription that renews automatically and can be stopped from Settings at any time.'}
            </p>
            <div className="bg-surface-light rounded-lg p-4 flex flex-wrap items-center justify-between gap-3">
              <span className="text-gray-400">Total</span>
              <span className="text-success font-bold text-lg">
                ${price}{billing === 'year' ? '/year' : '/month'}
              </span>
            </div>
            {available(selectedPlan) ? (
              <button
                onClick={handleCheckout}
                disabled={cardLoading}
                className="mt-4 flex items-center gap-2 px-6 py-2 bg-primary hover:bg-primary-dark disabled:opacity-50 text-white rounded-lg transition-colors font-medium"
              >
                {cardLoading
                  ? <><Loader2 className="w-4 h-4 animate-spin" /> Opening checkout...</>
                  : `Pay $${price} by card`}
              </button>
            ) : (
              <p className="mt-4 text-warning bg-warning/10 border border-warning/30 rounded-lg p-3 text-sm">
                Card payments for this plan are not available right now. Choose the other billing
                period, or try again later.
              </p>
            )}
          </div>
        )}
      </div>
    </div>
  )
}
