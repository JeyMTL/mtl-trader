'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { ArrowLeft, Upload, CheckCircle, Clock, XCircle, Loader2, Copy } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { PLANS } from '@/lib/plans'
import { authedFetch } from '@/lib/api'
import { useToast } from '@/components/toast'
import type { BillingInterval } from '@/types'

interface PaymentRequest {
  id: string
  plan_id: string
  amount: number
  status: string
  reference: string
  created_at: string
}

interface BankDetails {
  bank_name: string
  account_name: string
  account_number: string
  branch: string
}

// Derived from PLANS so the bank-transfer page can never drift from the displayed prices.
const PLAN_PRICES: Record<string, { name: string; amount: number }> = Object.fromEntries(
  PLANS.filter(p => p.price > 0).map(p => [p.id, { name: `${p.name} Plan`, amount: p.price }])
)

/** A year bought up front; only the plans that actually have a yearly price. */
const PLAN_ANNUAL_PRICES: Record<string, number> = Object.fromEntries(
  PLANS.filter(p => typeof p.annual_price === 'number' && p.annual_price > 0)
    .map(p => [p.id, p.annual_price as number])
)

export default function PaymentPage() {
  const { toast } = useToast()
  const router = useRouter()
  const [selectedPlan, setSelectedPlan] = useState('')
  const [reference, setReference] = useState('')
  const [referenceLoading, setReferenceLoading] = useState(false)
  const [submitted, setSubmitted] = useState(false)
  const [requests, setRequests] = useState<PaymentRequest[]>([])
  const [userId, setUserId] = useState<string | null>(null)
  const [bank, setBank] = useState<BankDetails | null>(null)
  const [bankError, setBankError] = useState('')
  const [billing, setBilling] = useState<BillingInterval>('month')
  const [annualPlans, setAnnualPlans] = useState<string[]>([])
  const [cardLoading, setCardLoading] = useState(false)

  useEffect(() => {
    async function load() {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        router.push('/auth/login')
        return
      }
      setUserId(user.id)

      const { data } = await supabase
        .from('payment_requests')
        .select('*')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })
      setRequests(data || [])

      const urlPlan = new URLSearchParams(window.location.search).get('plan')
      if (urlPlan && PLAN_PRICES[urlPlan]) {
        setSelectedPlan(urlPlan)
      }

      // Which plans this deployment can actually sell a year of. Bank transfer
      // is a 30-day payment, so a yearly plan is card-only by construction.
      const cardRes = await fetch('/api/paddle/checkout')
      if (cardRes.ok) {
        const cardData = await cardRes.json().catch(() => null)
        setAnnualPlans(Array.isArray(cardData?.annual) ? cardData.annual : [])
      }

      const bankRes = await authedFetch('/api/bank-details')
      if (bankRes.ok) {
        const bankData = await bankRes.json()
        setBank(bankData.bank || null)
      } else {
        const bankData = await bankRes.json().catch(() => null)
        setBankError(bankData?.error || 'Bank transfer is not available right now.')
      }
    }
    load()
  }, [router])

  const handleGenerateReference = async () => {
    if (!selectedPlan || !userId) return
    setReferenceLoading(true)

    const response = await authedFetch('/api/payment-requests', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        planId: selectedPlan,
      }),
    })
    const result = await response.json()

    if (!response.ok) {
      toast(result.error || 'Could not submit the payment request.', { tone: 'error' })
      setReferenceLoading(false)
      return
    }

    setReference(result.reference)
    setReferenceLoading(false)

    const { data } = await supabase
      .from('payment_requests')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
    setRequests(data || [])
  }

  const handleSubmit = () => {
    if (reference) setSubmitted(true)
  }

  /**
   * Yearly plan: Paddle hosts the card form, so no card detail reaches this app.
   * The webhook is what grants the 365 days — never the redirect back.
   */
  const handleAnnualCheckout = async () => {
    if (!selectedPlan || !userId || cardLoading) return
    setCardLoading(true)

    try {
      const response = await authedFetch('/api/paddle/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ planId: selectedPlan, userId, interval: 'year' }),
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

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text)
  }

  return (
    <div className="space-y-6 max-w-2xl">
      <div>
        <button onClick={() => router.back()} className="flex items-center gap-2 text-gray-400 hover:text-white mb-4 transition-colors">
          <ArrowLeft className="w-4 h-4" />
          Back
        </button>
        <h1 className="text-2xl font-bold text-white">Upgrade Plan</h1>
        <p className="text-gray-400 text-sm mt-1">Pay via bank transfer and submit your payment reference</p>
      </div>

      {submitted ? (
        <div className="bg-surface border border-border rounded-xl p-8 text-center">
          <CheckCircle className="w-16 h-16 text-success mx-auto mb-4" />
          <h2 className="text-xl font-bold text-white mb-2">Payment Request Submitted!</h2>
          <p className="text-gray-400 mb-6">
            Your payment is being reviewed. You&apos;ll be upgraded within 24 hours after verification.
          </p>
          <button
            onClick={() => { setSubmitted(false); setSelectedPlan(''); setReference('') }}
            className="px-6 py-2 bg-primary hover:bg-primary-dark text-white rounded-lg transition-colors"
          >
            Submit Another
          </button>
        </div>
      ) : (
        <div className="space-y-6">
          <div className="bg-surface border border-border rounded-xl p-6">
            <h2 className="text-lg font-semibold text-white mb-2">1. Select Plan</h2>
            <div className="mb-4 inline-flex rounded-full border border-border bg-background p-1">
              {(['month', 'year'] as const).map((option) => (
                <button
                  key={option}
                  onClick={() => { setBilling(option); setReference('') }}
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
                  onClick={() => { setSelectedPlan(id); setReference('') }}
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
                  {billing === 'year' && (
                    <div className="text-xs text-gray-500 mt-1">
                      ${(PLAN_ANNUAL_PRICES[id] / 12).toFixed(2)}/mo · two months free
                    </div>
                  )}
                </button>
              ))}
            </div>
          </div>

          {selectedPlan && billing === 'year' && (
            <div className="bg-surface border border-border rounded-xl p-6">
              <h2 className="text-lg font-semibold text-white mb-4">2. Pay by card</h2>
              <p className="text-gray-400 text-sm mb-4">
                A yearly plan is a single card payment through Paddle, our merchant of record.
                It renews once a year and covers 365 days from the moment it is confirmed.
              </p>
              <div className="bg-surface-light rounded-lg p-4 flex flex-wrap items-center justify-between gap-3">
                <span className="text-gray-400">Total</span>
                <span className="text-success font-bold text-lg">${PLAN_ANNUAL_PRICES[selectedPlan]}/year</span>
              </div>
              {annualPlans.includes(selectedPlan) ? (
                <button
                  onClick={handleAnnualCheckout}
                  disabled={cardLoading}
                  className="mt-4 flex items-center gap-2 px-6 py-2 bg-primary hover:bg-primary-dark disabled:opacity-50 text-white rounded-lg transition-colors font-medium"
                >
                  {cardLoading
                    ? <><Loader2 className="w-4 h-4 animate-spin" /> Opening checkout...</>
                    : `Pay $${PLAN_ANNUAL_PRICES[selectedPlan]} by card`}
                </button>
              ) : (
                <p className="mt-4 text-warning bg-warning/10 border border-warning/30 rounded-lg p-3 text-sm">
                  Yearly card payments are not available right now. Choose monthly, or pay monthly by
                  bank transfer.
                </p>
              )}
            </div>
          )}

          {selectedPlan && billing === 'month' && (
            <div className="bg-surface border border-border rounded-xl p-6">
              <h2 className="text-lg font-semibold text-white mb-4">2. Bank Transfer Details</h2>
              {bankError && (
                <p className="text-warning bg-warning/10 border border-warning/30 rounded-lg p-3 text-sm mb-4">{bankError}</p>
              )}
              <div className="bg-surface-light rounded-lg p-4 space-y-3">
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <span className="text-gray-400">Bank</span>
                  <span className="text-white font-medium">{bank?.bank_name}</span>
                </div>
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <span className="text-gray-400">Account Name</span>
                  <span className="text-white font-medium">{bank?.account_name}</span>
                </div>
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <span className="text-gray-400">Account Number</span>
                  <div className="flex items-center gap-2">
                    <span className="text-white font-medium font-mono">{bank?.account_number}</span>
                    <button onClick={() => copyToClipboard(bank?.account_number || '')} className="text-primary hover:text-primary-light">
                      <Copy className="w-4 h-4" />
                    </button>
                  </div>
                </div>
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <span className="text-gray-400">Branch</span>
                  <span className="text-white font-medium">{bank?.branch}</span>
                </div>
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <span className="text-gray-400">Amount</span>
                  <span className="text-success font-bold text-lg">${PLAN_PRICES[selectedPlan].amount}</span>
                </div>
              </div>
              <div className="mt-4 bg-warning/10 border border-warning/30 rounded-lg p-3">
                <p className="text-warning text-xs font-medium">
                  Generate your unique reference below and include it with the bank transfer.
                </p>
              </div>
              {!reference && bank && (
                <button
                  onClick={handleGenerateReference}
                  disabled={referenceLoading}
                  className="mt-4 flex items-center gap-2 px-5 py-2 bg-primary hover:bg-primary-dark disabled:opacity-50 text-white rounded-lg transition-colors font-medium"
                >
                  {referenceLoading ? <><Loader2 className="w-4 h-4 animate-spin" /> Preparing...</> : 'Continue to payment details'}
                </button>
              )}
            </div>
          )}

          {selectedPlan && billing === 'month' && reference && (
            <div className="bg-surface border border-border rounded-xl p-6">
              <h2 className="text-lg font-semibold text-white mb-4">3. Make the transfer</h2>
              <p className="text-gray-400 text-sm mb-4">
                Include this exact reference in your bank transfer. After sending the money, confirm below so your request is ready for payment review.
              </p>
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-300 mb-2">Payment Reference</label>
                  <div className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white font-mono tracking-wide">{reference}</div>
                </div>
                <button
                  onClick={handleSubmit}
                  className="flex items-center gap-2 px-6 py-2 bg-primary hover:bg-primary-dark disabled:opacity-50 text-white rounded-lg transition-colors font-medium"
                >
                  <Upload className="w-4 h-4" /> I&apos;ve made the transfer
                </button>
              </div>
            </div>
          )}
        </div>
      )}

      {requests.length > 0 && (
        <div className="bg-surface border border-border rounded-xl p-6">
          <h2 className="text-lg font-semibold text-white mb-4">Payment History</h2>
          <div className="space-y-3">
            {requests.map((req) => (
              <div key={req.id} className="flex items-center justify-between py-3 px-4 bg-surface-light rounded-lg">
                <div className="flex items-center gap-3">
                  <div className={`w-8 h-8 rounded-full flex items-center justify-center ${
                    req.status === 'approved' ? 'bg-success/20 text-success' :
                    req.status === 'rejected' ? 'bg-danger/20 text-danger' :
                    'bg-warning/20 text-warning'
                  }`}>
                    {req.status === 'approved' ? <CheckCircle className="w-4 h-4" /> :
                     req.status === 'rejected' ? <XCircle className="w-4 h-4" /> :
                     <Clock className="w-4 h-4" />}
                  </div>
                  <div>
                    <p className="text-sm text-white font-medium">
                      {PLAN_PRICES[req.plan_id]?.name || req.plan_id} - ${req.amount}
                    </p>
                    <p className="text-xs text-gray-500">
                      Ref: {req.reference} — {new Date(req.created_at).toLocaleDateString()}
                    </p>
                  </div>
                </div>
                <span className={`px-3 py-1 rounded-full text-xs font-medium ${
                  req.status === 'approved' ? 'bg-success/20 text-success' :
                  req.status === 'rejected' ? 'bg-danger/20 text-danger' :
                  'bg-warning/20 text-warning'
                }`}>
                  {req.status.charAt(0).toUpperCase() + req.status.slice(1)}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
