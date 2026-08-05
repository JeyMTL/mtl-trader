'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { Download, RefreshCw, Key, Server, CheckCircle, XCircle, Loader2, Copy, Check } from 'lucide-react'
import { supabase } from '@/lib/supabase'

export default function SyncPage() {
  const router = useRouter()
  const [user, setUser] = useState<{ id: string; email: string } | null>(null)
  const [token, setToken] = useState('')
  const [loading, setLoading] = useState(true)
  const [copied, setCopied] = useState(false)
  const [brokerName, setBrokerName] = useState('')
  const [server, setServer] = useState('')
  const [login, setLogin] = useState('')
  const [password, setPassword] = useState('')

  useEffect(() => {
    async function loadUser() {
      const { data: { user: authUser } } = await supabase.auth.getUser()
      if (!authUser) {
        router.push('/auth/login')
        return
      }
      setUser({ id: authUser.id, email: authUser.email! })

      const response = await fetch(`/api/sync?userId=${authUser.id}`)
      const data = await response.json()
      if (data.token) {
        setToken(data.token)
      }
      setLoading(false)
    }
    loadUser()
  }, [router])

  const copyCommand = () => {
    const cmd = `python mt5_agent.py ${user?.id} ${token} "${brokerName}" "${server}" "${login}" "${password}"`
    navigator.clipboard.writeText(cmd)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[400px]">
        <Loader2 className="w-8 h-8 animate-spin text-primary" />
      </div>
    )
  }

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-white">MT5 Auto Sync</h1>
        <p className="text-gray-400 mt-1">Connect your MT5 account to automatically sync trades</p>
      </div>

      <div className="bg-surface rounded-xl border border-border p-6">
        <div className="flex items-center gap-3 mb-4">
          <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
            <Key className="w-5 h-5 text-primary" />
          </div>
          <div>
            <h2 className="text-lg font-semibold text-white">Your Sync Token</h2>
            <p className="text-sm text-gray-400">This token authenticates your MT5 agent</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <code className="flex-1 bg-background px-4 py-3 rounded-lg text-sm text-gray-300 font-mono">
            {token}
          </code>
          <button
            onClick={() => { navigator.clipboard.writeText(token); setCopied(true); setTimeout(() => setCopied(false), 2000) }}
            className="px-4 py-3 bg-surface-light rounded-lg hover:bg-surface transition-colors"
          >
            {copied ? <Check className="w-5 h-5 text-green-400" /> : <Copy className="w-5 h-5 text-gray-400" />}
          </button>
        </div>
      </div>

      <div className="bg-surface rounded-xl border border-border p-6">
        <div className="flex items-center gap-3 mb-4">
          <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
            <Server className="w-5 h-5 text-primary" />
          </div>
          <div>
            <h2 className="text-lg font-semibold text-white">MT5 Connection Details</h2>
            <p className="text-sm text-gray-400">Enter your MT5 broker details</p>
          </div>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-400 mb-2">Broker Name</label>
            <input
              type="text"
              value={brokerName}
              onChange={(e) => setBrokerName(e.target.value)}
              placeholder="e.g., MetaQuotes"
              className="w-full bg-background border border-border rounded-lg px-4 py-2.5 text-white placeholder-gray-500 focus:outline-none focus:border-primary"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-400 mb-2">Server</label>
            <input
              type="text"
              value={server}
              onChange={(e) => setServer(e.target.value)}
              placeholder="e.g., MetaQuotes-Demo"
              className="w-full bg-background border border-border rounded-lg px-4 py-2.5 text-white placeholder-gray-500 focus:outline-none focus:border-primary"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-400 mb-2">Login (Account Number)</label>
            <input
              type="text"
              value={login}
              onChange={(e) => setLogin(e.target.value)}
              placeholder="e.g., 12345678"
              className="w-full bg-background border border-border rounded-lg px-4 py-2.5 text-white placeholder-gray-500 focus:outline-none focus:border-primary"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-400 mb-2">Password</label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Your MT5 password"
              className="w-full bg-background border border-border rounded-lg px-4 py-2.5 text-white placeholder-gray-500 focus:outline-none focus:border-primary"
            />
          </div>
        </div>
      </div>

      <div className="bg-surface rounded-xl border border-border p-6">
        <div className="flex items-center gap-3 mb-4">
          <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
            <Download className="w-5 h-5 text-primary" />
          </div>
          <div>
            <h2 className="text-lg font-semibold text-white">Setup Instructions</h2>
            <p className="text-sm text-gray-400">Follow these steps to sync your trades</p>
          </div>
        </div>
        
        <div className="space-y-4">
          <div className="flex items-start gap-3">
            <div className="w-6 h-6 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0 mt-0.5">
              <span className="text-xs font-bold text-primary">1</span>
            </div>
            <div>
              <p className="text-white font-medium">Install Python dependencies</p>
              <code className="block mt-1 bg-background px-3 py-2 rounded text-sm text-gray-300">
                pip install MetaTrader5 requests
              </code>
            </div>
          </div>

          <div className="flex items-start gap-3">
            <div className="w-6 h-6 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0 mt-0.5">
              <span className="text-xs font-bold text-primary">2</span>
            </div>
            <div>
              <p className="text-white font-medium">Download the sync agent</p>
              <a
                href="/mt5_agent.py"
                download
                className="inline-flex items-center gap-2 mt-1 text-primary hover:text-primary-dark transition-colors"
              >
                <Download className="w-4 h-4" />
                Download mt5_agent.py
              </a>
            </div>
          </div>

          <div className="flex items-start gap-3">
            <div className="w-6 h-6 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0 mt-0.5">
              <span className="text-xs font-bold text-primary">3</span>
            </div>
            <div>
              <p className="text-white font-medium">Run the agent with this command</p>
              <div className="mt-2 flex items-center gap-2">
                <code className="flex-1 bg-background px-3 py-2 rounded text-sm text-gray-300 overflow-x-auto">
                  {`python mt5_agent.py ${user?.id} ${token} "${brokerName || 'YOUR_BROKER'}" "${server || 'YOUR_SERVER'}" "${login || 'YOUR_LOGIN'}" "${password || 'YOUR_PASSWORD'}"`}
                </code>
                <button
                  onClick={copyCommand}
                  className="px-3 py-2 bg-primary hover:bg-primary-dark rounded-lg transition-colors flex-shrink-0"
                >
                  {copied ? <Check className="w-4 h-4 text-white" /> : <Copy className="w-4 h-4 text-white" />}
                </button>
              </div>
            </div>
          </div>

          <div className="flex items-start gap-3">
            <div className="w-6 h-6 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0 mt-0.5">
              <span className="text-xs font-bold text-primary">4</span>
            </div>
            <div>
              <p className="text-white font-medium">Keep MT5 running</p>
              <p className="text-gray-400 text-sm mt-1">The agent syncs every 60 seconds while running. Keep MT5 open.</p>
            </div>
          </div>
        </div>
      </div>

      <div className="bg-yellow-500/10 border border-yellow-500/20 rounded-xl p-4">
        <div className="flex items-start gap-3">
          <XCircle className="w-5 h-5 text-yellow-400 flex-shrink-0 mt-0.5" />
          <div>
            <p className="text-yellow-400 font-medium">Important Notes</p>
            <ul className="mt-2 text-sm text-gray-400 space-y-1">
              <li>• MT5 terminal must be running on your computer</li>
              <li>• The agent only works while your computer is on</li>
              <li>• Your credentials are never stored on our servers</li>
              <li>• All data is encrypted during transfer</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  )
}
