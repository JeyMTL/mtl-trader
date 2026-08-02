'use client'

import Link from 'next/link'
import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { Check, CreditCard, Loader2 } from 'lucide-react'
import { PLANS } from '@/lib/plans'
import { formatCurrency } from '@/lib/utils'
import { supabase } from '@/lib/supabase'
import { Logo } from '@/components/logo'

export default function PricingPage() {
  const router = useRouter()
  const [loading, setLoading] = useState<string | null>(null)
  const [redirectUrl, setRedirectUrl] = useState<string | null>(null)

  useEffect(() => {
    if (redirectUrl) window.location.href = redirectUrl
  }, [redirectUrl])

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
        alert('Error: ' + (data.error || 'Something went wrong'))
      }
    } catch {
      alert('Failed to start checkout')
    }
    setLoading(null)
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
            <h1 className="text-4xl font-bold text-white mb-4">Simple, Transparent Pricing</h1>
            <p className="text-gray-400 text-lg">Start free, upgrade when you need more</p>
          </div>

          <div className="grid md:grid-cols-3 gap-8 max-w-5xl mx-auto">
            {PLANS.map((plan) => (
              <div
                key={plan.id}
                className={`bg-surface border rounded-2xl p-8 ${
                  plan.popular ? 'border-primary shadow-lg shadow-primary/20' : 'border-border'
                }`}
              >
                {plan.popular && (
                  <div className="text-primary text-sm font-semibold mb-2">MOST POPULAR</div>
                )}
                <h3 className="text-2xl font-bold text-white mb-2">{plan.name}</h3>
                <div className="mb-6">
                  <span className="text-4xl font-bold text-white">
                    {plan.price === 0 ? 'Free' : formatCurrency(plan.price)}
                  </span>
                  {plan.price > 0 && <span className="text-gray-400">/month</span>}
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
                    <button
                      onClick={() => handleCheckout(plan.id)}
                      disabled={loading === plan.id}
                      className={`w-full py-3 rounded-lg font-semibold transition-colors flex items-center justify-center gap-2 ${
                        plan.popular
                          ? 'bg-primary hover:bg-primary-dark text-white'
                          : 'border border-border hover:border-primary text-gray-300 hover:text-white'
                      } disabled:opacity-50`}
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
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}
