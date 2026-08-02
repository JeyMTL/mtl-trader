'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { ArrowLeft, Upload, CheckCircle, Clock, XCircle, Loader2, Copy } from 'lucide-react'
import { supabase } from '@/lib/supabase'

interface PaymentRequest {
  id: string
  plan_id: string
  amount: number
  status: string
  reference: string
  created_at: string
}

const BANK_DETAILS = {
  bank_name: 'Access Bank',
  account_name: 'Jeremiah Chipeta',
  account_number: '0416486191025',
  branch: 'Lundazi',
}

const PLAN_PRICES: Record<string, { name: string; amount: number }> = {
  basic: { name: 'Basic Plan', amount: 9.99 },
  pro: { name: 'Pro Plan', amount: 29.99 },
}

export default function PaymentPage() {
  const router = useRouter()
  const [selectedPlan, setSelectedPlan] = useState('')
  const [reference, setReference] = useState('')
  const [loading, setLoading] = useState(false)
  const [submitted, setSubmitted] = useState(false)
  const [requests, setRequests] = useState<PaymentRequest[]>([])
  const [userId, setUserId] = useState<string | null>(null)

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
    }
    load()
  }, [router])

  const handleSubmit = async () => {
    if (!selectedPlan || !reference.trim() || !userId) return
    setLoading(true)

    const { error } = await supabase.from('payment_requests').insert({
      user_id: userId,
      plan_id: selectedPlan,
      amount: PLAN_PRICES[selectedPlan].amount,
      reference: reference.trim(),
      status: 'pending',
    })

    if (error) {
      alert('Error: ' + error.message)
      setLoading(false)
      return
    }

    setSubmitted(true)
    setLoading(false)

    const { data } = await supabase
      .from('payment_requests')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
    setRequests(data || [])
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
            <h2 className="text-lg font-semibold text-white mb-4">1. Select Plan</h2>
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
                  <div className="text-2xl font-bold text-white mt-1">${plan.amount}/mo</div>
                </button>
              ))}
            </div>
          </div>

          {selectedPlan && (
            <div className="bg-surface border border-border rounded-xl p-6">
              <h2 className="text-lg font-semibold text-white mb-4">2. Bank Transfer Details</h2>
              <div className="bg-surface-light rounded-lg p-4 space-y-3">
                <div className="flex justify-between">
                  <span className="text-gray-400">Bank</span>
                  <span className="text-white font-medium">{BANK_DETAILS.bank_name}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-400">Account Name</span>
                  <span className="text-white font-medium">{BANK_DETAILS.account_name}</span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-gray-400">Account Number</span>
                  <div className="flex items-center gap-2">
                    <span className="text-white font-medium font-mono">{BANK_DETAILS.account_number}</span>
                    <button onClick={() => copyToClipboard(BANK_DETAILS.account_number)} className="text-primary hover:text-primary-light">
                      <Copy className="w-4 h-4" />
                    </button>
                  </div>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-400">Branch</span>
                  <span className="text-white font-medium">{BANK_DETAILS.branch}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-400">Amount</span>
                  <span className="text-success font-bold text-lg">${PLAN_PRICES[selectedPlan].amount}</span>
                </div>
              </div>
              <div className="mt-4 bg-warning/10 border border-warning/30 rounded-lg p-3">
                <p className="text-warning text-xs font-medium">
                  Important: Use your email as the payment reference when making the transfer.
                </p>
              </div>
            </div>
          )}

          {selectedPlan && (
            <div className="bg-surface border border-border rounded-xl p-6">
              <h2 className="text-lg font-semibold text-white mb-4">3. Submit Payment Reference</h2>
              <p className="text-gray-400 text-sm mb-4">
                After making the bank transfer, enter the transaction reference or your email used for payment.
              </p>
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-300 mb-2">Payment Reference</label>
                  <input
                    type="text"
                    value={reference}
                    onChange={(e) => setReference(e.target.value)}
                    placeholder="e.g. Your email or transaction ID"
                    className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
                  />
                </div>
                <button
                  onClick={handleSubmit}
                  disabled={loading || !reference.trim()}
                  className="flex items-center gap-2 px-6 py-2 bg-primary hover:bg-primary-dark disabled:opacity-50 text-white rounded-lg transition-colors font-medium"
                >
                  {loading ? <><Loader2 className="w-4 h-4 animate-spin" /> Submitting...</> : <><Upload className="w-4 h-4" /> Submit Payment</>}
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
