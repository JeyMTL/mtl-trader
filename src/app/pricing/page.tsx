'use client'

import Link from 'next/link'
import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { Check, CreditCard, Loader2, RefreshCw } from 'lucide-react'
import { PLANS } from '@/lib/plans'
import { formatCurrency } from '@/lib/utils'
import { supabase } from '@/lib/supabase'
import { Logo } from '@/components/logo'
import { useToast } from '@/components/toast'
import type { BillingInterval } from '@/types'

/**
 * Card subscriptions run through Paddle, the merchant of record. Whether the
 * option appears is decided by the server: `GET /api/paddle/checkout` reports
 * which plans actually have a configured Paddle price id. A misconfigured
 * deployment therefore shows no button, instead of a button that invites the
 * customer to commit and then fails.
 */
interface CardStatus {
  enabled: boolean
  plans: string[]
  annual: string[]
}

export default function PricingPage() {
  const router = useRouter()
  const { toast } = useToast()
  const [loading, setLoading] = useState<string | null>(null)
  const [cardLoading, setCardLoading] = useState<string | null>(null)
  const [redirectUrl, setRedirectUrl] = useState<string | null>(null)
  const [cardStatus, setCardStatus] = useState<CardStatus>({ enabled: false, plans: [], annual: [] })
  const [billing, setBilling] = useState<BillingInterval>('month')

  useEffect(() => {
    if (redirectUrl) window.location.href = redirectUrl
  }, [redirectUrl])

  // Ask the server which paid plans are actually purchasable. A missing key or
  // price id hides the card option rather than promising a checkout that fails.
  useEffect(() => {
    let cancelled = false
    void (async () => {
      try {
        const res = await fetch('/api/paddle/checkout')
        const data = (await res.json()) as { enabled?: boolean; plans?: string[]; annual?: string[] }
        if (cancelled) return
        setCardStatus({
          enabled: Boolean(data.enabled),
          plans: Array.isArray(data.plans) ? data.plans : [],
          annual: Array.isArray(data.annual) ? data.annual : [],
        })
      } catch {
        // Leave the card option hidden; PayPal and bank transfer still work.
      }
    })()
    return () => {
      cancelled = true
    }
  }, [])

  // A yearly price is a separate Paddle catalogue entry, so each cadence is
  // offered only when this deployment actually configured it.
  const cardAvailable = (planId: string, interval: BillingInterval) =>
    cardStatus.enabled &&
    (interval === 'year' ? cardStatus.annual : cardStatus.plans).includes(planId)

  const handleCheckout = async (planId: string) => {
    setLoading(planId)
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) {
      router.push('/auth/signup')
      return
    }

    try {
      const res = await fetch('/api/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ planId, userId: user.id, email: user.email }),
      })
      const data = await res.json()
      if (data.url) {
        setRedirectUrl(data.url)
      } else {
        toast(data.error || 'Could not start checkout.', { tone: 'error' })
      }
    } catch {
      toast('Could not start checkout. Check your connection and try again.', { tone: 'error' })
    }
    setLoading(null)
  }

  /**
   * Card subscription: Paddle creates the transaction and hosts the checkout, so
   * the card details never touch this app. `custom_data` carries the user id and
   * plan, and the webhook is what grants access — never the redirect back.
   */
  const handleCardSubscription = async (planId: string, interval: BillingInterval) => {
    setCardLoading(planId)
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) {
      router.push('/auth/signup')
      return
    }

    try {
      const res = await fetch('/api/paddle/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ planId, userId: user.id, interval }),
      })
      const data = await res.json()
      if (data.url) {
        // `assign` rather than a `location.href` write: the write is flagged by
        // react-hooks/immutability, and both navigate identically.
        window.location.assign(data.url)
      } else {
        toast(data.error || 'Could not start the card checkout.', { tone: 'error' })
      }
    } catch {
      toast('Could not start the card checkout. Check your connection and try again.', { tone: 'error' })
    }
    setCardLoading(null)
  }

  const handleBankTransfer = (planId: string) => {
    router.push('/dashboard/payment?plan=' + planId)
  }

  return (
    <div className="min-h-screen bg-background">
      <nav className="border-b border-border bg-surface/50 backdrop-blur-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center h-16">
            <Link href="/" className="flex items-center gap-2">
              <Logo size="sm" />
            </Link>
            <div className="flex items-center gap-4">
              <Link href="/auth/login" className="text-gray-300 hover:text-white transition-colors">
                Login
              </Link>
              <Link href="/auth/signup" className="bg-primary hover:bg-primary-dark text-white px-4 py-2 rounded-lg transition-colors">
                Get Started
              </Link>
            </div>
          </div>
        </div>
      </nav>

      <div className="py-20 px-4">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-12">
            <h1 className="text-4xl font-bold text-white mb-4">
              Simple, <span className="text-gradient">Transparent</span> Pricing
            </h1>
            <p className="text-gray-400 text-lg">Start free, upgrade when you need more</p>
            <div className="mt-8 inline-flex rounded-full border border-border bg-surface p-1">
              {(['month', 'year'] as const).map((option) => (
                <button
                  key={option}
                  onClick={() => setBilling(option)}
                  aria-pressed={billing === option}
                  className={`rounded-full px-4 py-1.5 text-sm font-medium transition-colors ${
                    billing === option ? 'bg-primary text-white' : 'text-gray-400 hover:text-white'
                  }`}
                >
                  {option === 'month' ? 'Monthly' : 'Annual · 2 months free'}
                </button>
              ))}
            </div>
          </div>

          <div className="grid md:grid-cols-3 gap-8 max-w-5xl mx-auto">
            {PLANS.map((plan) => (
              <div
                key={plan.id}
                className={`card-hover bg-surface border rounded-2xl p-8 ${
                  plan.popular ? 'border-primary glow-primary' : 'border-border'
                }`}
              >
                {plan.popular && (
                  <div className="badge-pill mb-3">MOST POPULAR</div>
                )}
                <h3 className="text-2xl font-bold text-white mb-2">{plan.name}</h3>
                <div className="mb-6">
                  {plan.price === 0 ? (
                    <span className="text-4xl font-bold text-white">Free</span>
                  ) : billing === 'year' && plan.annual_price ? (
                    <>
                      <span className="text-4xl font-bold text-white">
                        {formatCurrency(plan.annual_price)}
                      </span>
                      <span className="text-gray-400">/year</span>
                      <p className="mt-1 text-xs text-success">
                        {formatCurrency(plan.annual_price / 12)}/month · two months free
                      </p>
                    </>
                  ) : (
                    <>
                      <span className="text-4xl font-bold text-white">{formatCurrency(plan.price)}</span>
                      <span className="text-gray-400">/month</span>
                    </>
                  )}
                </div>
                <ul className="space-y-3 mb-8">
                  {plan.features.map((feature) => (
                    <li key={feature} className="flex items-center gap-2 text-gray-300 text-sm">
                      <Check className="w-4 h-4 text-success flex-shrink-0" />
                      {feature}
                    </li>
                  ))}
                </ul>
                {plan.price === 0 ? (
                  <Link
                    href="/auth/signup"
                    className="block w-full text-center py-3 rounded-lg font-semibold transition-colors border border-border hover:border-primary text-gray-300 hover:text-white"
                  >
                    Start Free Trial
                  </Link>
                ) : (
                  <div className="space-y-2">
                    {cardAvailable(plan.id, billing) && (
                    <button
                      onClick={() => handleCardSubscription(plan.id, billing)}
                      disabled={cardLoading === plan.id}
                      className={`w-full py-3 rounded-xl font-semibold transition-colors flex items-center justify-center gap-2 ${
                        plan.popular
                          ? 'btn-gradient text-white'
                          : 'border border-border hover:border-primary text-gray-300 hover:text-white'
                      } disabled:opacity-50`}
                    >
                      {cardLoading === plan.id ? (
                        <><Loader2 className="w-4 h-4 animate-spin" /> Loading...</>
                      ) : (
                        <><RefreshCw className="w-4 h-4" /> Subscribe with card</>
                      )}
                    </button>
                    )}
                    {cardAvailable(plan.id, billing) && (
                    <p className="text-xs text-gray-500 text-center">
                      {billing === 'year'
                        ? 'Auto-renews yearly · cancel any time'
                        : 'Auto-renews monthly · cancel any time'}
                    </p>
                    )}
                    {billing === 'month' ? (
                      <>
                        <button
                          onClick={() => handleCheckout(plan.id)}
                          disabled={loading === plan.id}
                          className="w-full py-3 rounded-lg font-semibold transition-colors flex items-center justify-center gap-2 border border-border hover:border-primary text-gray-300 hover:text-white disabled:opacity-50"
                        >
                          {loading === plan.id ? (
                            <><Loader2 className="w-4 h-4 animate-spin" /> Loading...</>
                          ) : (
                            <><CreditCard className="w-4 h-4" /> Pay with PayPal</>
                          )}
                        </button>
                        <button
                          onClick={() => handleBankTransfer(plan.id)}
                          className="w-full py-3 rounded-lg font-semibold transition-colors flex items-center justify-center gap-2 border border-border hover:border-primary text-gray-300 hover:text-white"
                        >
                          Bank Transfer
                        </button>
                      </>
                    ) : (
                      <p className="text-xs text-gray-500 text-center">
                        Annual plans are card only. PayPal and bank transfer buy one 30-day period.
                      </p>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>

          <p className="mx-auto mt-10 max-w-2xl text-center text-xs text-gray-500">
            A yearly payment buys 365 days; PayPal is a one-time 30-day payment, and bank
            transfers are approved manually.
            {cardStatus.enabled
              ? ' Card payments are processed by Paddle, renew automatically, and can be stopped from Settings at any time; access continues until the paid period ends.'
              : ''}
          </p>
        </div>
      </div>

      <footer className="border-t border-border py-8">
        <div className="mx-auto flex max-w-7xl flex-col items-center justify-between gap-3 px-4 text-xs text-gray-500 sm:flex-row">
          <p>&copy; 2026 MTL Trader. All rights reserved.</p>
          <div className="flex gap-4">
            <Link href="/terms" className="transition-colors hover:text-white">Terms</Link>
            <Link href="/privacy" className="transition-colors hover:text-white">Privacy</Link>
            <Link href="/refunds" className="transition-colors hover:text-white">Refunds</Link>
          </div>
        </div>
      </footer>
    </div>
  )
}
