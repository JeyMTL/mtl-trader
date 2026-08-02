'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { CheckCircle, XCircle, Clock, Loader2, Shield } from 'lucide-react'
import { supabase } from '@/lib/supabase'

interface PaymentRequest {
  id: string
  user_id: string
  plan_id: string
  amount: number
  reference: string
  status: string
  created_at: string
  users: { id: string; email: string; full_name: string }
}

export default function AdminPage() {
  const router = useRouter()
  const [requests, setRequests] = useState<PaymentRequest[]>([])
  const [loading, setLoading] = useState(true)
  const [processingId, setProcessingId] = useState<string | null>(null)
  const [isAdmin, setIsAdmin] = useState(false)
  const [filter, setFilter] = useState('pending')

  const fetchRequests = async () => {
    setLoading(true)
    const { data } = await supabase
      .from('payment_requests')
      .select('*, users!inner(id, email, full_name)')
      .order('created_at', { ascending: false })
    setRequests(data || [])
    setLoading(false)
  }

  useEffect(() => {
    async function load() {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        router.push('/auth/login')
        return
      }

      const { data: userData } = await supabase
        .from('users')
        .select('subscription_tier')
        .eq('id', user.id)
        .single()

      if (userData?.subscription_tier !== 'pro') {
        router.push('/dashboard')
        return
      }

      setIsAdmin(true)
      await fetchRequests()
    }
    load()
  }, [router])

  const handleAction = async (requestId: string, action: 'approve' | 'reject') => {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return

    setProcessingId(requestId)
    const res = await fetch('/api/admin/payments', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ requestId, action, adminId: user.id }),
    })
    const data = await res.json()

    if (data.success) {
      await fetchRequests()
    } else {
      alert('Error: ' + (data.error || 'Failed'))
    }
    setProcessingId(null)
  }

  if (!isAdmin) return null

  const filtered = requests.filter(r => filter === 'all' || r.status === filter)
  const pendingCount = requests.filter(r => r.status === 'pending').length

  return (
    <div className="space-y-6">
      <div>
        <div className="flex items-center gap-2 mb-1">
          <Shield className="w-6 h-6 text-primary" />
          <h1 className="text-2xl font-bold text-white">Admin Panel</h1>
        </div>
        <p className="text-gray-400 text-sm">Review and manage payment requests</p>
      </div>

      <div className="flex gap-2">
        {['pending', 'approved', 'rejected', 'all'].map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
              filter === f
                ? 'bg-primary text-white'
                : 'bg-surface border border-border text-gray-400 hover:text-white'
            }`}
          >
            {f.charAt(0).toUpperCase() + f.slice(1)}
            {f === 'pending' && pendingCount > 0 && (
              <span className="ml-2 bg-danger text-white text-xs rounded-full px-2 py-0.5">{pendingCount}</span>
            )}
          </button>
        ))}
      </div>

      <div className="bg-surface border border-border rounded-xl overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-gray-500">Loading...</div>
        ) : filtered.length === 0 ? (
          <div className="p-8 text-center text-gray-500">No {filter} requests</div>
        ) : (
          <div className="divide-y divide-border">
            {filtered.map((req) => (
              <div key={req.id} className="p-4 flex items-center justify-between">
                <div className="flex items-center gap-4">
                  <div className={`w-10 h-10 rounded-full flex items-center justify-center ${
                    req.status === 'approved' ? 'bg-success/20 text-success' :
                    req.status === 'rejected' ? 'bg-danger/20 text-danger' :
                    'bg-warning/20 text-warning'
                  }`}>
                    {req.status === 'approved' ? <CheckCircle className="w-5 h-5" /> :
                     req.status === 'rejected' ? <XCircle className="w-5 h-5" /> :
                     <Clock className="w-5 h-5" />}
                  </div>
                  <div>
                    <p className="text-sm font-medium text-white">
                      {req.users?.full_name || 'Unknown'} ({req.users?.email})
                    </p>
                    <p className="text-xs text-gray-400">
                      {req.plan_id === 'basic' ? 'Basic Plan' : 'Pro Plan'} — ${req.amount} — Ref: {req.reference}
                    </p>
                    <p className="text-xs text-gray-500">
                      {new Date(req.created_at).toLocaleString()}
                    </p>
                  </div>
                </div>

                {req.status === 'pending' && (
                  <div className="flex gap-2">
                    <button
                      onClick={() => handleAction(req.id, 'approve')}
                      disabled={processingId === req.id}
                      className="flex items-center gap-1 px-3 py-1.5 bg-success/20 text-success rounded-lg hover:bg-success/30 transition-colors text-sm font-medium disabled:opacity-50"
                    >
                      {processingId === req.id ? <Loader2 className="w-4 h-4 animate-spin" /> : <CheckCircle className="w-4 h-4" />}
                      Approve
                    </button>
                    <button
                      onClick={() => handleAction(req.id, 'reject')}
                      disabled={processingId === req.id}
                      className="flex items-center gap-1 px-3 py-1.5 bg-danger/20 text-danger rounded-lg hover:bg-danger/30 transition-colors text-sm font-medium disabled:opacity-50"
                    >
                      <XCircle className="w-4 h-4" />
                      Reject
                    </button>
                  </div>
                )}

                {req.status !== 'pending' && (
                  <span className={`px-3 py-1 rounded-full text-xs font-medium ${
                    req.status === 'approved' ? 'bg-success/20 text-success' : 'bg-danger/20 text-danger'
                  }`}>
                    {req.status.charAt(0).toUpperCase() + req.status.slice(1)}
                  </span>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
