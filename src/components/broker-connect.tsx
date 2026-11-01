'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import {
  CheckCircle2,
  Loader2,
  Plug,
  RefreshCw,
  ShieldCheck,
  Unplug,
  XCircle,
} from 'lucide-react'
import { authedFetch } from '@/lib/api'
import { useToast } from '@/components/toast'

/**
 * Automatic MT5 connection, the phone-first path.
 *
 * A phone can't run an Expert Advisor, so the customer hands over their
 * **investor** (read-only) password once and our own host connects instead. This
 * card is the whole setup: broker, server, account number, investor password.
 *
 * The password is posted once and never read back — the API only ever returns
 * status — so there is nothing to re-display or leak after the fact.
 */

type Status = 'none' | 'pending' | 'connecting' | 'connected' | 'failed' | 'disconnected'

interface Connection {
  connected: boolean
  status: Status
  broker?: string
  server?: string
  account?: string
  lastSyncAt?: string | null
  lastError?: string | null
}

const LABEL: Record<Status, string> = {
  none: 'Not connected',
  pending: 'Connecting…',
  connecting: 'Connecting…',
  connected: 'Connected',
  failed: 'Connection failed',
  disconnected: 'Disconnected',
}

function since(iso?: string | null): string {
  if (!iso) return 'not yet'
  const elapsed = Date.now() - new Date(iso).getTime()
  if (!Number.isFinite(elapsed) || elapsed < 1000) return 'just now'
  const seconds = Math.round(elapsed / 1000)
  if (seconds < 60) return `${seconds}s ago`
  const minutes = Math.round(seconds / 60)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.round(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  return `${Math.round(hours / 24)}d ago`
}

export default function BrokerConnect() {
  const { toast } = useToast()
  const [connection, setConnection] = useState<Connection | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [broker, setBroker] = useState('')
  const [server, setServer] = useState('')
  const [login, setLogin] = useState('')
  const [password, setPassword] = useState('')
  const [problem, setProblem] = useState('')
  const [stalled, setStalled] = useState(false)
  const pollTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const pendingSince = useRef<number | null>(null)

  const load = useCallback(async () => {
    try {
      const res = await authedFetch('/api/broker/connection')
      const data = await res.json()
      if (res.ok) setConnection(data as Connection)
    } catch {
      // Falls through to the form: a status read failure must not block setup.
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    load()
  }, [load])

  // While a supervisor is picking the connection up, refresh so the customer
  // sees it go live without reloading the page. After two minutes, stop: a row
  // that never leaves `pending` is a stuck session, not a slow one, and an
  // endlessly spinning card tells the customer nothing.
  useEffect(() => {
    const status = connection?.status
    if (status !== 'pending' && status !== 'connecting') {
      pendingSince.current = null
      setStalled(false)
      return
    }
    pendingSince.current ??= Date.now()
    if (Date.now() - pendingSince.current > 120000) {
      setStalled(true)
      return
    }
    pollTimer.current = setTimeout(load, 6000)
    return () => {
      if (pollTimer.current) clearTimeout(pollTimer.current)
    }
  }, [connection, load])

  const submit = async (event: React.FormEvent) => {
    event.preventDefault()
    if (saving) return
    setSaving(true)
    setProblem('')
    try {
      const res = await authedFetch('/api/broker/connection', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ broker, server, login, investorPassword: password }),
      })
      const data = await res.json()
      if (res.ok) {
        setConnection(data as Connection)
        setPassword('')
        toast('Connection saved. We are connecting to your account now.', { tone: 'success' })
      } else {
        setProblem(data.error || 'Could not save the connection.')
      }
    } catch {
      setProblem('Could not reach the server. Check your connection and try again.')
    } finally {
      setSaving(false)
    }
  }

  const disconnect = async () => {
    if (!confirm('Disconnect this account? We will delete the stored password and stop syncing.')) {
      return
    }
    try {
      const res = await authedFetch('/api/broker/connection', { method: 'DELETE' })
      const data = await res.json()
      if (res.ok) {
        setConnection(data as Connection)
        toast('Account disconnected and the stored password was deleted.', { tone: 'success' })
      } else {
        toast(data.error || 'Could not disconnect the account.', { tone: 'error' })
      }
    } catch {
      toast('Could not disconnect the account. Check your connection and try again.', { tone: 'error' })
    }
  }

  const status = connection?.status ?? 'none'
  const active = status === 'connected' || status === 'pending' || status === 'connecting'

  return (
    <div className="bg-surface rounded-xl border border-border p-6">
      <div className="flex items-start gap-3 mb-4">
        <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center flex-shrink-0">
          <Plug className="w-5 h-5 text-primary" />
        </div>
        <div className="min-w-0">
          <h2 className="text-lg font-semibold text-white">Connect automatically</h2>
          <p className="text-sm text-gray-400">
            Works from your phone — no PC, no Python, nothing to keep running.
          </p>
        </div>
        <button
          onClick={load}
          className="ml-auto p-2 rounded-lg hover:bg-surface-light transition-colors flex-shrink-0"
          title="Refresh status"
        >
          {loading ? (
            <Loader2 className="w-4 h-4 text-gray-400 animate-spin" />
          ) : (
            <RefreshCw className="w-4 h-4 text-gray-400" />
          )}
        </button>
      </div>

      {active ? (
        <div className="space-y-3">
          <div className="flex items-center gap-2">
            {status === 'connected' ? (
              <CheckCircle2 className="w-4 h-4 text-green-400" />
            ) : (
              <Loader2 className="w-4 h-4 text-yellow-400 animate-spin" />
            )}
            <span className="text-sm font-medium text-white">{LABEL[status]}</span>
            {connection?.lastSyncAt && (
              <span className="text-xs text-gray-500">
                · last trade {since(connection.lastSyncAt)}
              </span>
            )}
          </div>
          <dl className="grid grid-cols-1 sm:grid-cols-3 gap-2 text-sm">
            <div>
              <dt className="text-xs text-gray-500">Broker</dt>
              <dd className="text-gray-300 truncate">{connection?.broker || '—'}</dd>
            </div>
            <div>
              <dt className="text-xs text-gray-500">Server</dt>
              <dd className="text-gray-300 truncate">{connection?.server || '—'}</dd>
            </div>
            <div>
              <dt className="text-xs text-gray-500">Account</dt>
              <dd className="text-gray-300 font-mono">{connection?.account || '—'}</dd>
            </div>
          </dl>
          {status !== 'connected' &&
            (stalled ? (
              <div className="flex items-start gap-2 rounded-lg border border-yellow-500/20 bg-yellow-500/10 p-3">
                <XCircle className="w-4 h-4 text-yellow-400 flex-shrink-0 mt-0.5" />
                <div className="text-xs text-yellow-200/90 space-y-1">
                  <p>
                    Still not connected after two minutes. That normally means the account number,
                    server or investor password was rejected — or no sync session is available yet.
                  </p>
                  <p className="text-yellow-200/70">
                    Disconnect below and enter the details again, or use the read-only investor
                    password from MT5 → Settings → your account.
                  </p>
                </div>
              </div>
            ) : (
              <p className="text-xs text-gray-500">
                This usually takes under a minute. If it stays here, check that the account number
                and investor password are correct, then disconnect and connect again.
              </p>
            ))}
          <button
            onClick={disconnect}
            className="flex items-center gap-2 px-4 py-2 rounded-lg border border-border hover:border-red-500/50 text-sm text-gray-300 hover:text-white transition-colors"
          >
            <Unplug className="w-4 h-4" />
            Disconnect and delete password
          </button>
        </div>
      ) : (
        <form onSubmit={submit} className="space-y-4">
          {status === 'failed' && connection?.lastError && (
            <div className="flex items-start gap-2 rounded-lg border border-yellow-500/20 bg-yellow-500/10 p-3">
              <XCircle className="w-4 h-4 text-yellow-400 flex-shrink-0 mt-0.5" />
              <p className="text-xs text-yellow-200/90">{connection.lastError}</p>
            </div>
          )}

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-400 mb-2">Broker</label>
              <input
                type="text"
                value={broker}
                onChange={(event) => setBroker(event.target.value)}
                placeholder="e.g., IC Markets"
                autoComplete="organization"
                className="w-full bg-background border border-border rounded-lg px-4 py-2.5 text-white placeholder-gray-500 focus:outline-none focus:border-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-400 mb-2">Server</label>
              <input
                type="text"
                value={server}
                onChange={(event) => setServer(event.target.value)}
                placeholder="e.g., ICMarketsSC-Live12"
                className="w-full bg-background border border-border rounded-lg px-4 py-2.5 text-white placeholder-gray-500 focus:outline-none focus:border-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-400 mb-2">Account number</label>
              <input
                type="text"
                inputMode="numeric"
                value={login}
                onChange={(event) => setLogin(event.target.value)}
                placeholder="e.g., 12345678"
                autoComplete="off"
                className="w-full bg-background border border-border rounded-lg px-4 py-2.5 text-white placeholder-gray-500 focus:outline-none focus:border-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-400 mb-2">
                Investor (read-only) password
              </label>
              <input
                type="password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                autoComplete="new-password"
                className="w-full bg-background border border-border rounded-lg px-4 py-2.5 text-white placeholder-gray-500 focus:outline-none focus:border-primary"
              />
            </div>
          </div>

          {problem && (
            <p className="text-sm text-red-400" role="alert">
              {problem}
            </p>
          )}

          <div className="flex items-start gap-2 rounded-lg border border-border bg-background/60 p-3">
            <ShieldCheck className="w-4 h-4 text-green-400 flex-shrink-0 mt-0.5" />
            <div className="text-xs text-gray-400 space-y-1">
              <p>
                Use the <span className="text-gray-200">investor password</span>, never your trading
                password. In the MT5 app: Settings → tap your account → Change investor password.
              </p>
              <p>
                It is read-only: we cannot open, close or modify a trade. It is stored encrypted,
                and changing it in MT5 instantly cuts our access.
              </p>
            </div>
          </div>

          <button
            type="submit"
            disabled={saving || !broker || !server || !login || !password}
            className="flex items-center gap-2 px-4 py-2.5 bg-primary hover:bg-primary-dark text-white rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
          >
            {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Plug className="w-4 h-4" />}
            {saving ? 'Saving…' : 'Connect account'}
          </button>
        </form>
      )}
    </div>
  )
}
