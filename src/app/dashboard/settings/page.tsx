'use client'

import { useState, useEffect } from 'react'
import { User, CreditCard, Bell, Shield, Save, Wallet, Trash2, Palette, Loader2 } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { formatCurrency } from '@/lib/utils'
import { useTheme } from '@/lib/theme'

interface Deposit {
  id: string
  amount: number
  type: string
  description: string | null
  created_at: string
}

interface UserProfile {
  full_name: string
  email: string
  timezone: string
  currency: string
  notifications_email: boolean
  notifications_daily: boolean
  notifications_weekly: boolean
  notifications_marketing: boolean
}

export default function SettingsPage() {
  const { theme, toggle } = useTheme()
  const [activeTab, setActiveTab] = useState('profile')
  const [saved, setSaved] = useState(false)
  const [deposits, setDeposits] = useState<Deposit[]>([])
  const [depAmount, setDepAmount] = useState('')
  const [depType, setDepType] = useState('deposit')
  const [depDesc, setDepDesc] = useState('')
  const [depLoading, setDepLoading] = useState(false)
  const [checkoutLoading, setCheckoutLoading] = useState<string | null>(null)
  const [portalLoading, setPortalLoading] = useState(false)
  const [userPlan, setUserPlan] = useState({ tier: 'free', status: 'trial', stripeCustomerId: '' as string | null })
  const [userId, setUserId] = useState<string | null>(null)
  const [profile, setProfile] = useState<UserProfile>({
    full_name: '',
    email: '',
    timezone: 'UTC',
    currency: 'USD',
    notifications_email: true,
    notifications_daily: true,
    notifications_weekly: false,
    notifications_marketing: false,
  })
  const [profileLoading, setProfileLoading] = useState(true)
  const [passwords, setPasswords] = useState({ current: '', new: '', confirm: '' })
  const [passwordLoading, setPasswordLoading] = useState(false)
  const [passwordError, setPasswordError] = useState('')
  const [passwordSuccess, setPasswordSuccess] = useState(false)
  const [deleteLoading, setDeleteLoading] = useState(false)

  const tabs = [
    { id: 'profile', name: 'Profile', icon: User },
    { id: 'balance', name: 'Balance', icon: Wallet },
    { id: 'appearance', name: 'Appearance', icon: Palette },
    { id: 'subscription', name: 'Subscription', icon: CreditCard },
    { id: 'notifications', name: 'Notifications', icon: Bell },
    { id: 'security', name: 'Security', icon: Shield },
  ]

  const fetchData = async () => {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return
    setUserId(user.id)

    const { data: userData } = await supabase
      .from('users')
      .select('*')
      .eq('id', user.id)
      .single()
    if (userData) {
      setProfile({
        full_name: userData.full_name || '',
        email: userData.email || user.email || '',
        timezone: userData.timezone || 'UTC',
        currency: userData.currency || 'USD',
        notifications_email: userData.notifications_email ?? true,
        notifications_daily: userData.notifications_daily ?? true,
        notifications_weekly: userData.notifications_weekly ?? false,
        notifications_marketing: userData.notifications_marketing ?? false,
      })
      setUserPlan({
        tier: userData.subscription_tier || 'free',
        status: userData.subscription_status || 'trial',
        stripeCustomerId: userData.stripe_customer_id,
      })
    } else {
      setProfile(prev => ({ ...prev, email: user.email || '' }))
    }

    const { data: depData } = await supabase
      .from('deposits')
      .select('*')
      .eq('user_id', user.id)
      .order('created_at', { ascending: false })
    setDeposits(depData || [])
    setProfileLoading(false)
  }

  useEffect(() => {
    async function load() {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return
      setUserId(user.id)

      const { data: userData } = await supabase
        .from('users')
        .select('*')
        .eq('id', user.id)
        .single()
      if (userData) {
        setProfile({
          full_name: userData.full_name || '',
          email: userData.email || user.email || '',
          timezone: userData.timezone || 'UTC',
          currency: userData.currency || 'USD',
          notifications_email: userData.notifications_email ?? true,
          notifications_daily: userData.notifications_daily ?? true,
          notifications_weekly: userData.notifications_weekly ?? false,
          notifications_marketing: userData.notifications_marketing ?? false,
        })
        setUserPlan({
          tier: userData.subscription_tier || 'free',
          status: userData.subscription_status || 'trial',
          stripeCustomerId: userData.stripe_customer_id,
        })
      } else {
        setProfile(prev => ({ ...prev, email: user.email || '' }))
      }

      const { data: depData } = await supabase
        .from('deposits')
        .select('*')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })
      setDeposits(depData || [])
      setProfileLoading(false)
    }
    load()
  }, [])

  const handleSaveProfile = async () => {
    if (!userId) return
    setSaved(true)
    const { error } = await supabase
      .from('users')
      .update({
        full_name: profile.full_name,
        timezone: profile.timezone,
        currency: profile.currency,
      })
      .eq('id', userId)
    if (error) {
      alert('Error saving profile: ' + error.message)
    }
    setTimeout(() => setSaved(false), 2000)
  }

  const handleSaveNotifications = async () => {
    if (!userId) return
    setSaved(true)
    const { error } = await supabase
      .from('users')
      .update({
        notifications_email: profile.notifications_email,
        notifications_daily: profile.notifications_daily,
        notifications_weekly: profile.notifications_weekly,
        notifications_marketing: profile.notifications_marketing,
      })
      .eq('id', userId)
    if (error) {
      alert('Error saving notifications: ' + error.message)
    }
    setTimeout(() => setSaved(false), 2000)
  }

  const handleChangePassword = async () => {
    setPasswordError('')
    setPasswordSuccess(false)

    if (!passwords.current || !passwords.new || !passwords.confirm) {
      setPasswordError('All fields are required')
      return
    }
    if (passwords.new.length < 6) {
      setPasswordError('New password must be at least 6 characters')
      return
    }
    if (passwords.new !== passwords.confirm) {
      setPasswordError('New passwords do not match')
      return
    }

    setPasswordLoading(true)

    const { data: { user } } = await supabase.auth.getUser()
    if (!user || !user.email) {
      setPasswordError('Not authenticated')
      setPasswordLoading(false)
      return
    }

    const { error: signInError } = await supabase.auth.signInWithPassword({
      email: user.email,
      password: passwords.current,
    })
    if (signInError) {
      setPasswordError('Current password is incorrect')
      setPasswordLoading(false)
      return
    }

    const { error } = await supabase.auth.updateUser({ password: passwords.new })
    if (error) {
      setPasswordError(error.message)
    } else {
      setPasswordSuccess(true)
      setPasswords({ current: '', new: '', confirm: '' })
    }
    setPasswordLoading(false)
  }

  const handleDeleteAccount = async () => {
    if (!confirm('Are you sure you want to delete your account? This cannot be undone.')) return
    if (!confirm('This will permanently delete all your trades, deposits, and account data. Continue?')) return
    setDeleteLoading(true)
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return

    await supabase.from('trades').delete().eq('user_id', user.id)
    await supabase.from('deposits').delete().eq('user_id', user.id)
    await supabase.from('users').delete().eq('id', user.id)
    await supabase.auth.signOut()
    window.location.href = '/'
  }

  const handleAddDeposit = async () => {
    const amount = parseFloat(depAmount)
    if (isNaN(amount) || amount === 0) return
    if (!userId) return
    setDepLoading(true)
    const { error } = await supabase.from('deposits').insert({
      user_id: userId,
      amount: depType === 'withdrawal' ? -Math.abs(amount) : Math.abs(amount),
      type: depType,
      description: depDesc || null,
    })
    if (error) {
      alert('Error adding deposit: ' + error.message)
      setDepLoading(false)
      return
    }
    setDepAmount('')
    setDepDesc('')
    await fetchData()
    setDepLoading(false)
  }

  const handleDeleteDeposit = async (id: string) => {
    if (!confirm('Delete this deposit/withdrawal?')) return
    await supabase.from('deposits').delete().eq('id', id)
    await fetchData()
  }

  const totalBalance = deposits.reduce((acc, d) => acc + d.amount, 0)

  const handleCheckout = async (planId: string) => {
    setCheckoutLoading(planId)
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return
    try {
      const res = await fetch('/api/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ planId, userId: user.id, email: user.email }),
      })
      const data = await res.json()
      if (data.url) {
        window.location.href = data.url
      } else {
        alert('Error: ' + (data.error || 'Something went wrong'))
      }
    } catch {
      alert('Failed to start checkout')
    }
    setCheckoutLoading(null)
  }

  const handleCancelSubscription = async () => {
    if (!confirm('Are you sure you want to cancel your subscription? You will lose access to premium features.')) return
    setPortalLoading(true)
    try {
      const res = await fetch('/api/subscription/cancel', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ userId }),
      })
      const data = await res.json()
      if (data.success) {
        alert('Subscription cancelled successfully')
        fetchData()
      } else {
        alert('Error: ' + (data.error || 'Failed to cancel'))
      }
    } catch {
      alert('Failed to cancel subscription')
    }
    setPortalLoading(false)
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-white">Settings</h1>
        <p className="text-gray-400 text-sm mt-1">Manage your account preferences</p>
      </div>

      <div className="flex flex-col lg:flex-row gap-6">
        {/* Sidebar */}
        <div className="lg:w-64">
          <nav className="bg-surface border border-border rounded-xl p-2 space-y-1">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
                  activeTab === tab.id
                    ? 'bg-primary/10 text-primary'
                    : 'text-gray-400 hover:text-white hover:bg-surface-light'
                }`}
              >
                <tab.icon className="w-5 h-5" />
                {tab.name}
              </button>
            ))}
          </nav>
        </div>

        {/* Content */}
        <div className="flex-1">
          {activeTab === 'profile' && (
            <div className="bg-surface border border-border rounded-xl p-6 space-y-6">
              <h2 className="text-lg font-semibold text-white">Profile Settings</h2>
              
              {profileLoading ? (
                <p className="text-gray-400">Loading profile...</p>
              ) : (
                <div className="grid sm:grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-gray-300 mb-2">Full Name</label>
                    <input
                      type="text"
                      value={profile.full_name}
                      onChange={(e) => setProfile(p => ({ ...p, full_name: e.target.value }))}
                      className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-300 mb-2">Email</label>
                    <input
                      type="email"
                      value={profile.email}
                      disabled
                      className="w-full bg-background border border-border rounded-lg px-4 py-2 text-gray-500 cursor-not-allowed"
                    />
                    <p className="text-xs text-gray-500 mt-1">Email cannot be changed</p>
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-300 mb-2">Timezone</label>
                    <select
                      value={profile.timezone}
                      onChange={(e) => setProfile(p => ({ ...p, timezone: e.target.value }))}
                      className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
                    >
                      <option>UTC</option>
                      <option>EST</option>
                      <option>PST</option>
                      <option>GMT</option>
                      <option>CET</option>
                      <option>JST</option>
                      <option>AEST</option>
                    </select>
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-300 mb-2">Currency</label>
                    <select
                      value={profile.currency}
                      onChange={(e) => setProfile(p => ({ ...p, currency: e.target.value }))}
                      className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
                    >
                      <option>USD</option>
                      <option>EUR</option>
                      <option>GBP</option>
                      <option>JPY</option>
                      <option>AUD</option>
                      <option>CAD</option>
                    </select>
                  </div>
                </div>
              )}

              <button
                onClick={handleSaveProfile}
                disabled={profileLoading}
                className="flex items-center gap-2 px-4 py-2 bg-primary hover:bg-primary-dark text-white rounded-lg transition-colors disabled:opacity-50"
              >
                <Save className="w-4 h-4" />
                {saved ? 'Saved!' : 'Save Changes'}
              </button>
            </div>
          )}

          {activeTab === 'balance' && (
            <div className="space-y-6">
              <div className="bg-surface border border-border rounded-xl p-6">
                <h2 className="text-lg font-semibold text-white mb-4">Account Balance</h2>
                <div className="bg-surface-light border border-border rounded-xl p-4 mb-6">
                  <p className="text-sm text-gray-400 mb-1">Total Balance</p>
                  <p className={`text-3xl font-bold ${totalBalance >= 0 ? 'text-success' : 'text-danger'}`}>
                    {formatCurrency(totalBalance)}
                  </p>
                </div>

                <div className="grid sm:grid-cols-4 gap-3 mb-6">
                  <div>
                    <label className="block text-xs text-gray-400 mb-1">Type</label>
                    <select
                      value={depType}
                      onChange={(e) => setDepType(e.target.value)}
                      className="w-full bg-background border border-border rounded-lg px-3 py-2 text-white text-sm focus:outline-none focus:border-primary"
                    >
                      <option value="deposit">Deposit</option>
                      <option value="withdrawal">Withdrawal</option>
                    </select>
                  </div>
                  <div>
                    <label className="block text-xs text-gray-400 mb-1">Amount ($)</label>
                    <input
                      type="number"
                      value={depAmount}
                      onChange={(e) => setDepAmount(e.target.value)}
                      placeholder="0.00"
                      className="w-full bg-background border border-border rounded-lg px-3 py-2 text-white text-sm focus:outline-none focus:border-primary"
                    />
                  </div>
                  <div>
                    <label className="block text-xs text-gray-400 mb-1">Description</label>
                    <input
                      type="text"
                      value={depDesc}
                      onChange={(e) => setDepDesc(e.target.value)}
                      placeholder="e.g. Initial deposit"
                      className="w-full bg-background border border-border rounded-lg px-3 py-2 text-white text-sm focus:outline-none focus:border-primary"
                    />
                  </div>
                  <div className="flex items-end">
                    <button
                      onClick={handleAddDeposit}
                      disabled={depLoading || !depAmount}
                      className="w-full px-4 py-2 bg-primary hover:bg-primary-dark disabled:opacity-50 text-white rounded-lg transition-colors text-sm font-medium"
                    >
                      {depLoading ? 'Adding...' : 'Add'}
                    </button>
                  </div>
                </div>

                {deposits.length > 0 ? (
                  <div className="space-y-2">
                    {deposits.map((d) => (
                      <div key={d.id} className="flex items-center justify-between py-3 px-4 bg-surface-light rounded-lg">
                        <div className="flex items-center gap-3">
                          <div className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold ${d.amount >= 0 ? 'bg-success/20 text-success' : 'bg-danger/20 text-danger'}`}>
                            {d.amount >= 0 ? '+' : '-'}
                          </div>
                          <div>
                            <p className="text-sm text-white font-medium">
                              {d.amount >= 0 ? 'Deposit' : 'Withdrawal'}: {formatCurrency(Math.abs(d.amount))}
                            </p>
                            <p className="text-xs text-gray-500">
                              {d.description || 'No description'} — {new Date(d.created_at).toLocaleDateString()}
                            </p>
                          </div>
                        </div>
                        <button
                          onClick={() => handleDeleteDeposit(d.id)}
                          className="text-gray-500 hover:text-danger transition-colors"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </div>
                    ))}
                  </div>
                ) : (
                  <p className="text-gray-500 text-sm">No deposits yet. Add your first deposit above.</p>
                )}
              </div>
            </div>
          )}

          {activeTab === 'appearance' && (
            <div className="bg-surface border border-border rounded-xl p-6 space-y-6">
              <h2 className="text-lg font-semibold text-white">Appearance</h2>
              
              <div className="space-y-4">
                <div className="flex items-center justify-between py-4 border-b border-border">
                  <div>
                    <p className="text-sm font-medium text-white">Theme</p>
                    <p className="text-xs text-gray-400">Switch between dark and light mode</p>
                  </div>
                  <button
                    onClick={toggle}
                    className={`relative inline-flex h-8 w-14 items-center rounded-full transition-colors ${
                      theme === 'dark' ? 'bg-primary' : 'bg-gray-300'
                    }`}
                  >
                    <span
                      className={`inline-block h-6 w-6 transform rounded-full bg-white transition-transform ${
                        theme === 'dark' ? 'translate-x-7' : 'translate-x-1'
                      }`}
                    />
                  </button>
                </div>
                <p className="text-xs text-gray-500">
                  Current: {theme === 'dark' ? 'Dark' : 'Light'} mode
                </p>
              </div>
            </div>
          )}

          {activeTab === 'subscription' && (
            <div className="bg-surface border border-border rounded-xl p-6 space-y-6">
              <h2 className="text-lg font-semibold text-white">Subscription</h2>
              
              <div className={`border rounded-xl p-4 ${
                userPlan.tier !== 'free' ? 'bg-surface-light border-primary' : 'bg-surface-light border-border'
              }`}>
                <div className="flex items-center justify-between">
                  <div>
                    <h3 className="font-semibold text-white">
                      {userPlan.tier === 'pro' ? 'Pro Plan' : userPlan.tier === 'basic' ? 'Basic Plan' : 'Free Trial'}
                    </h3>
                    <p className="text-sm text-gray-400">
                      {userPlan.tier === 'free' ? '10 trades per month' :
                       userPlan.tier === 'basic' ? '50 trades per month' : 'Unlimited trades'}
                    </p>
                  </div>
                  <span className={`px-3 py-1 rounded-full text-sm font-medium ${
                    userPlan.status === 'active'
                      ? 'bg-success/20 text-success'
                      : userPlan.status === 'trial'
                      ? 'bg-primary/20 text-primary'
                      : 'bg-danger/20 text-danger'
                  }`}>
                    {userPlan.status === 'active' ? 'Active' :
                     userPlan.status === 'trial' ? 'Trial' :
                     userPlan.status === 'cancelled' ? 'Cancelled' : 'Expired'}
                  </span>
                </div>
              </div>

              {userPlan.tier !== 'free' && (
                <button
                  onClick={handleCancelSubscription}
                  disabled={portalLoading}
                  className="flex items-center gap-2 px-4 py-2 border border-danger text-danger rounded-lg hover:bg-danger/10 transition-colors disabled:opacity-50"
                >
                  {portalLoading ? <><Loader2 className="w-4 h-4 animate-spin" /> Loading...</> : 'Cancel Subscription'}
                </button>
              )}

              <div className="grid sm:grid-cols-2 gap-4">
                <div className={`bg-surface-light border rounded-xl p-4 ${
                  userPlan.tier === 'basic' ? 'border-primary' : 'border-border'
                }`}>
                  <h3 className="font-semibold text-white mb-2">Basic Plan</h3>
                  <p className="text-2xl font-bold text-white mb-2">$9.99<span className="text-sm text-gray-400">/mo</span></p>
                  <p className="text-sm text-gray-400 mb-4">50 trades per month</p>
                  <div className="space-y-2">
                    <button
                      onClick={() => handleCheckout('basic')}
                      disabled={checkoutLoading === 'basic' || userPlan.tier === 'basic'}
                      className="w-full py-2 bg-primary hover:bg-primary-dark text-white rounded-lg transition-colors disabled:opacity-50 flex items-center justify-center gap-2"
                    >
                      {checkoutLoading === 'basic' ? <><Loader2 className="w-4 h-4 animate-spin" /> Loading...</> :
                       userPlan.tier === 'basic' ? 'Current Plan' : 'Pay with PayPal'}
                    </button>
                    <button
                      onClick={() => window.location.href = '/dashboard/payment?plan=basic'}
                      disabled={userPlan.tier === 'basic'}
                      className="w-full py-2 border border-border rounded-lg text-gray-400 hover:text-white hover:border-primary transition-colors disabled:opacity-50 flex items-center justify-center gap-2 text-sm"
                    >
                      Bank Transfer
                    </button>
                  </div>
                </div>
                <div className={`bg-surface-light border rounded-xl p-4 ${
                  userPlan.tier === 'pro' ? 'border-primary' : 'border-primary/50'
                }`}>
                  {userPlan.tier !== 'pro' && <div className="text-primary text-xs font-semibold mb-2">MOST POPULAR</div>}
                  <h3 className="font-semibold text-white mb-2">Pro Plan</h3>
                  <p className="text-2xl font-bold text-white mb-2">$29.99<span className="text-sm text-gray-400">/mo</span></p>
                  <p className="text-sm text-gray-400 mb-4">Unlimited trades</p>
                  <div className="space-y-2">
                    <button
                      onClick={() => handleCheckout('pro')}
                      disabled={checkoutLoading === 'pro' || userPlan.tier === 'pro'}
                      className="w-full py-2 bg-primary hover:bg-primary-dark text-white rounded-lg transition-colors disabled:opacity-50 flex items-center justify-center gap-2"
                    >
                      {checkoutLoading === 'pro' ? <><Loader2 className="w-4 h-4 animate-spin" /> Loading...</> :
                       userPlan.tier === 'pro' ? 'Current Plan' : 'Pay with PayPal'}
                    </button>
                    <button
                      onClick={() => window.location.href = '/dashboard/payment?plan=pro'}
                      disabled={userPlan.tier === 'pro'}
                      className="w-full py-2 border border-border rounded-lg text-gray-400 hover:text-white hover:border-primary transition-colors disabled:opacity-50 flex items-center justify-center gap-2 text-sm"
                    >
                      Bank Transfer
                    </button>
                  </div>
                </div>
              </div>
            </div>
          )}

          {activeTab === 'notifications' && (
            <div className="bg-surface border border-border rounded-xl p-6 space-y-6">
              <h2 className="text-lg font-semibold text-white">Notifications</h2>
              
              <div className="space-y-4">
                {[
                  { key: 'notifications_email' as const, label: 'Email notifications', description: 'Receive email updates about your trades' },
                  { key: 'notifications_daily' as const, label: 'Daily summary', description: 'Get a daily summary of your trading performance' },
                  { key: 'notifications_weekly' as const, label: 'Weekly report', description: 'Receive a weekly performance report' },
                  { key: 'notifications_marketing' as const, label: 'Marketing emails', description: 'Receive tips and product updates' },
                ].map((item) => (
                  <div key={item.key} className="flex items-center justify-between py-3 border-b border-border last:border-0">
                    <div>
                      <p className="text-sm font-medium text-white">{item.label}</p>
                      <p className="text-xs text-gray-400">{item.description}</p>
                    </div>
                    <label className="relative inline-flex items-center cursor-pointer">
                      <input
                        type="checkbox"
                        checked={profile[item.key]}
                        onChange={(e) => setProfile(p => ({ ...p, [item.key]: e.target.checked }))}
                        className="sr-only peer"
                      />
                      <div className="w-11 h-6 bg-gray-600 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-primary"></div>
                    </label>
                  </div>
                ))}
              </div>

              <button
                onClick={handleSaveNotifications}
                className="flex items-center gap-2 px-4 py-2 bg-primary hover:bg-primary-dark text-white rounded-lg transition-colors"
              >
                <Save className="w-4 h-4" />
                {saved ? 'Saved!' : 'Save Changes'}
              </button>
            </div>
          )}

          {activeTab === 'security' && (
            <div className="bg-surface border border-border rounded-xl p-6 space-y-6">
              <h2 className="text-lg font-semibold text-white">Security</h2>
              
              <div className="space-y-4">
                {passwordError && (
                  <div className="bg-danger/10 border border-danger/30 text-danger px-4 py-3 rounded-lg text-sm">
                    {passwordError}
                  </div>
                )}
                {passwordSuccess && (
                  <div className="bg-success/10 border border-success/30 text-success px-4 py-3 rounded-lg text-sm">
                    Password updated successfully
                  </div>
                )}
                <div>
                  <label className="block text-sm font-medium text-gray-300 mb-2">Current Password</label>
                  <input
                    type="password"
                    value={passwords.current}
                    onChange={(e) => setPasswords(p => ({ ...p, current: e.target.value }))}
                    className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-300 mb-2">New Password</label>
                  <input
                    type="password"
                    value={passwords.new}
                    onChange={(e) => setPasswords(p => ({ ...p, new: e.target.value }))}
                    className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-300 mb-2">Confirm New Password</label>
                  <input
                    type="password"
                    value={passwords.confirm}
                    onChange={(e) => setPasswords(p => ({ ...p, confirm: e.target.value }))}
                    className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
                  />
                </div>
                <button
                  onClick={handleChangePassword}
                  disabled={passwordLoading}
                  className="flex items-center gap-2 px-4 py-2 bg-primary hover:bg-primary-dark text-white rounded-lg transition-colors disabled:opacity-50"
                >
                  {passwordLoading ? <><Loader2 className="w-4 h-4 animate-spin" /> Updating...</> : <><Save className="w-4 h-4" /> Update Password</>}
                </button>
              </div>

              <div className="pt-4 border-t border-border">
                <h3 className="text-sm font-medium text-danger mb-2">Danger Zone</h3>
                <p className="text-sm text-gray-400 mb-4">Permanently delete your account and all data</p>
                <button
                  onClick={handleDeleteAccount}
                  disabled={deleteLoading}
                  className="flex items-center gap-2 px-4 py-2 border border-danger text-danger rounded-lg hover:bg-danger/10 transition-colors disabled:opacity-50"
                >
                  {deleteLoading ? <><Loader2 className="w-4 h-4 animate-spin" /> Deleting...</> : 'Delete Account'}
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
