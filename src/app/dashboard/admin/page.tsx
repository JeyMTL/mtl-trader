'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { CheckCircle, XCircle, Clock, Loader2, Shield, Users, RefreshCw } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { authedFetch } from '@/lib/api'

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

interface AdminUser {
  id: string
  email: string
  full_name: string
  subscription_tier: string
  subscription_status: string
  created_at: string
  last_sign_in_at: string | null
  email_confirmed_at: string | null
}

export default function AdminPage() {
  const router = useRouter()
  const [requests, setRequests] = useState<PaymentRequest[]>([])
  const [loading, setLoading] = useState(true)
  const [processingId, setProcessingId] = useState<string | null>(null)
  const [isAdmin, setIsAdmin] = useState(false)
  const [filter, setFilter] = useState('pending')
  const [users, setUsers] = useState<AdminUser[]>([])
  const [usersLoading, setUsersLoading] = useState(true)
  const [errorMessage, setErrorMessage] = useState('')

  const fetchRequests = async () => {
    setLoading(true)
    setErrorMessage('')
    try {
      const res = await authedFetch('/api/admin/payments')
      const data = await res.json()
      if (res.ok) {
        setRequests(data.requests || [])
      } else {
        setErrorMessage(data.error || 'Failed to load payment requests')
      }
    } catch {
      setErrorMessage('Failed to load payment requests. Check your connection and try again.')
    }
    setLoading(false)
  }

  const fetchUsers = async () => {
    setUsersLoading(true)
    setErrorMessage('')
    try {
      const res = await authedFetch('/api/admin/users')
      const data = await res.json()
      if (res.ok) {
        setUsers(data.users || [])
      } else {
        setErrorMessage(data.error || 'Failed to load users')
      }
    } catch {
      setErrorMessage('Failed to load users. Check your connection and try again.')
    }
    setUsersLoading(false)
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
        .select('is_admin')
        .eq('id', user.id)
        .single()

      if (userData?.is_admin !== true) {
        router.push('/dashboard')
        return
      }

      setIsAdmin(true)
      await Promise.all([fetchRequests(), fetchUsers()])
    }
    load()
  }, [router])

  const handleAction = async (requestId: string, action: 'approve' | 'reject') => {
    setProcessingId(requestId)
    setErrorMessage('')
    try {
      const res = await authedFetch('/api/admin/payments', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ requestId, action }),
      })
      const data = await res.json()

      if (data.success) {
        await fetchRequests()
      } else {
        setErrorMessage(data.error || 'Could not update payment request')
      }
    } catch {
      setErrorMessage('Could not update payment request. Check your connection and try again.')
    } finally {
      setProcessingId(null)
    }
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

      {errorMessage && (
        <div className="bg-danger/10 border border-danger/30 text-danger px-4 py-3 rounded-lg text-sm flex items-center justify-between gap-4">
          <span>{errorMessage}</span>
          <button onClick={() => setErrorMessage('')} className="text-danger hover:text-white" aria-label="Dismiss error">Dismiss</button>
        </div>
      )}

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
              <div key={req.id} className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
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

      <div className="bg-surface border border-border rounded-xl overflow-hidden">
        <div className="p-4 sm:p-6 border-b border-border flex items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <Users className="w-5 h-5 text-primary" />
            <div>
              <h2 className="text-lg font-semibold text-white">Journal Users</h2>
              <p className="text-sm text-gray-400">{users.length} registered account{users.length === 1 ? '' : 's'}</p>
            </div>
          </div>
          <button
            onClick={fetchUsers}
            disabled={usersLoading}
            title="Refresh users"
            className="p-2 text-gray-400 hover:text-white hover:bg-surface-light rounded-lg transition-colors disabled:opacity-50"
          >
            <RefreshCw className={`w-4 h-4 ${usersLoading ? 'animate-spin' : ''}`} />
          </button>
        </div>

        {usersLoading ? (
          <div className="p-8 text-center text-gray-500">Loading users...</div>
        ) : users.length === 0 ? (
          <div className="p-8 text-center text-gray-500">No users found</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[760px]">
              <thead>
                <tr className="border-b border-border">
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">User</th>
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Subscription</th>
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Verification</th>
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Last login</th>
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Joined</th>
                </tr>
              </thead>
              <tbody>
                {users.map((account) => (
                  <tr key={account.id} className="border-b border-border last:border-0 hover:bg-surface-light transition-colors">
                    <td className="px-4 py-3">
                      <p className="text-sm font-medium text-white">{account.full_name || 'Unnamed user'}</p>
                      <p className="text-xs text-gray-400">{account.email}</p>
                    </td>
                    <td className="px-4 py-3">
                      <p className="text-sm font-medium text-white capitalize">{account.subscription_tier}</p>
                      <p className="text-xs text-gray-400 capitalize">{account.subscription_status}</p>
                    </td>
                    <td className="px-4 py-3">
                      <span className={`inline-flex px-2 py-1 rounded-full text-xs font-medium ${
                        account.email_confirmed_at ? 'bg-success/20 text-success' : 'bg-warning/20 text-warning'
                      }`}>
                        {account.email_confirmed_at ? 'Verified' : 'Pending'}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-300">
                      {account.last_sign_in_at ? new Date(account.last_sign_in_at).toLocaleString() : 'Never'}
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-400">
                      {new Date(account.created_at).toLocaleDateString()}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}
