'use client'

import { useState, useEffect } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import {
  Download,
  Key,
  Server,
  XCircle,
  Loader2,
  Copy,
  Check,
  RefreshCw,
  Lock,
  ArrowRight,
} from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { authedFetch } from '@/lib/api'
import { MT5_HOSTED_SYNC_ENABLED, MT5_SYNC_ENABLED } from '@/lib/features'
import { useToast } from '@/components/toast'
import BrokerConnect from '@/components/broker-connect'
import BrokerPicker, { ServerSuggestions } from '@/components/broker-picker'

export default function SyncPage() {
  const router = useRouter()
  const { toast } = useToast()
  const [user, setUser] = useState<{ id: string; email: string } | null>(null)
  const [token, setToken] = useState('')
  const [loading, setLoading] = useState(true)
  const [copied, setCopied] = useState(false)
  const [brokerName, setBrokerName] = useState('')
  const [server, setServer] = useState('')
  const [login, setLogin] = useState('')
  // Set when the server refuses the token because the account is not entitled.
  // Without it the page used to render an empty token box and the full setup
  // guide, so a free trader pasted a blank token into the EA and watched it
  // fail with nothing on screen to explain why. A genuine failure (the route
  // 500s, the network drops) uses the same slot but must not be called a plan
  // problem, hence `refused`.
  const [notice, setNotice] = useState<{
    title: string
    message: string
    refused: boolean
  } | null>(null)

  useEffect(() => {
    // The nav link is hidden, but a bookmark or an old typed URL still reaches
    // this route. Bounce it instead of showing a feature that is not sold.
    if (!MT5_SYNC_ENABLED) {
      router.replace('/dashboard')
      return
    }

    async function loadUser() {
      const { data: { user: authUser } } = await supabase.auth.getUser()
      if (!authUser) {
        router.push('/auth/login')
        return
      }
      setUser({ id: authUser.id, email: authUser.email! })

      try {
        const response = await authedFetch(`/api/sync?userId=${authUser.id}`)
        const data = await response.json()
        if (data.code === 'upgrade_required') {
          setNotice({
            title: 'Auto sync is not part of your plan',
            refused: true,
            message:
              data.error ||
              'MT5 auto sync is included from Basic. Choose a plan to sync your trades automatically.',
          })
        } else if (data.token) {
          setToken(data.token)
        } else if (data.error) {
          // A rejected token is not a sync problem the trader can fix on this
          // page, so it says what to do instead of echoing "Unauthorized".
          const expired = data.error === 'Unauthorized'
          setNotice({
            title: expired ? 'Your session expired' : 'Could not load your sync token',
            refused: false,
            message: expired ? 'Sign in again to load your sync token.' : data.error,
          })
        }
      } catch {
        setNotice({
          title: 'Could not reach the server',
          refused: false,
          message: 'Check your connection and reload the page to load your sync token.',
        })
      }
      setLoading(false)
    }
    loadUser()
  }, [router])

  const copyCommand = () => {
    const cmd = 'python mt5_agent.py --config mtl-trader-config.json'
    navigator.clipboard.writeText(cmd)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  const downloadConfig = () => {
    if (!user || !token) return
    const config = {
      app_url: window.location.origin,
      user_id: user.id,
      token,
      broker_name: brokerName,
      server,
      login,
    }
    const blob = new Blob([JSON.stringify(config, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url
    link.download = 'mtl-trader-config.json'
    link.click()
    URL.revokeObjectURL(url)
  }

  const regenerateToken = async () => {
    if (!confirm('Rotate your sync token? The old token will stop working immediately.')) return
    setLoading(true)
    try {
      const res = await authedFetch('/api/sync/rotate', { method: 'POST' })
      const data = await res.json()
      if (data.token) {
        setToken(data.token)
        toast('New token generated. Update your agent command and restart it.', { tone: 'success' })
      } else {
        toast(data.error || 'Could not rotate the token.', { tone: 'error' })
      }
    } catch {
      toast('Could not rotate the token. Check your connection and try again.', { tone: 'error' })
    }
    setLoading(false)
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[400px]">
        <Loader2 className="w-8 h-8 animate-spin text-primary" />
      </div>
    )
  }

  // A refused plan is the only state where the rest of the page would be a set
  // of instructions that cannot be followed: every card below needs a token the
  // server will not issue. Say why, and leave the way to fix it one click away.
  if (notice) {
    return (
      <div className="max-w-4xl mx-auto space-y-6">
        <div>
          <h1 className="text-2xl font-bold text-white">MT5 Auto Sync</h1>
          <p className="text-gray-400 mt-1">
            Sync closed trades from your own MT5 terminal, and let the same EA enforce the daily
            stop.
          </p>
        </div>

        <div
          className={
            notice.refused
              ? 'rounded-xl border border-primary/40 bg-primary/10 p-5'
              : 'rounded-xl border border-danger/40 bg-danger/10 p-5'
          }
        >
          <div className="flex items-start gap-3">
            <div
              className={`flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-lg ${
                notice.refused ? 'bg-primary/15' : 'bg-danger/15'
              }`}
            >
              {notice.refused ? (
                <Lock className="h-5 w-5 text-primary" />
              ) : (
                <XCircle className="h-5 w-5 text-danger" />
              )}
            </div>
            <div className="min-w-0">
              <p className="text-base font-semibold text-white">{notice.title}</p>
              <p className="mt-1 text-sm leading-relaxed text-gray-300">{notice.message}</p>
              {notice.refused && (
                <p className="mt-2 text-xs leading-relaxed text-gray-400">
                  Nothing in your journal is affected: the trades you already have stay where they
                  are, and the chart desk, calendar and simulator keep working.
                </p>
              )}
              <div className="mt-4 flex flex-wrap items-center gap-3">
                {notice.refused && (
                  <>
                    <Link
                      href="/pricing"
                      className="inline-flex items-center gap-1.5 rounded-lg bg-primary px-3.5 py-2 text-sm font-medium text-white transition-colors hover:bg-primary-dark"
                    >
                      Compare plans
                      <ArrowRight className="h-4 w-4" />
                    </Link>
                    <Link
                      href="/dashboard/import"
                      className="inline-flex items-center gap-1.5 rounded-lg border border-border px-3.5 py-2 text-sm font-medium text-gray-300 transition-colors hover:border-gray-600"
                    >
                      Import history by hand
                    </Link>
                  </>
                )}
                <button
                  type="button"
                  onClick={() => window.location.reload()}
                  className="text-xs font-medium text-gray-500 transition-colors hover:text-gray-300"
                >
                  {notice.refused ? 'Already upgraded? Reload' : 'Reload'}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-white">MT5 Auto Sync</h1>
        <p className="text-gray-400 mt-1">
          {MT5_HOSTED_SYNC_ENABLED
            ? 'Connect your MT5 account once and every closed trade lands here — from a phone, no PC needed'
            : 'Sync closed trades from your own MT5 terminal, and let the same EA enforce the daily stop.'}
        </p>
      </div>

      {MT5_HOSTED_SYNC_ENABLED ? <BrokerConnect /> : null}

      <div className="rounded-xl border border-border bg-surface p-5">
        <h2 className="text-lg font-semibold text-white">Daily stop guard — soft and hard</h2>
        <p className="mt-2 text-sm leading-relaxed text-gray-400">
          Set a daily loss limit in Rules and the MT5 guard carries it into your terminal.
          Both modes act the same way in MT5. A{' '}
          <strong className="text-gray-300">soft lock</strong> keeps the journal open, so you
          can lift it only by writing down why. A{' '}
          <strong className="text-gray-300">hard lock</strong> also closes the journal until
          the next trading day. While locked, the guard deletes resting orders and closes any
          position opened after the limit was hit. It cannot block a manual market-order click
          — that fills before the terminal reports it — and it only stops another expert
          advisor that checks it first. If the journal cannot be reached for five minutes,
          the lock releases so an outage cannot trap you in a position.
        </p>
        <Link
          href="/dashboard/playbook"
          className="mt-3 inline-flex text-sm font-medium text-primary hover:text-primary-light"
        >
          Choose the lock in Rules
        </Link>
      </div>

      {/* The manual route stays available for traders who run their own
          terminal, but it is folded away: the hosted connection above needs no
          downloads, and the four-step setup was the first thing a new account
          saw. */}
      <details className="rounded-xl border border-border bg-surface p-4">
        <summary className="cursor-pointer text-sm font-medium text-gray-400">
          Run your own MT5 terminal instead
        </summary>
        <div className="mt-4 space-y-6">
      <div className="bg-surface rounded-xl border border-border p-6">
        <div className="flex items-center gap-3 mb-4">
          <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
            <Server className="w-5 h-5 text-primary" />
          </div>
          <div>
            <h2 className="text-lg font-semibold text-white">MT5 Expert Advisor</h2>
            <p className="text-sm text-gray-400">
              Syncs closed trades and enforces the daily stop. Recommended on desktop.
            </p>
          </div>
        </div>
        <ol className="space-y-3 text-sm text-gray-400">
          <li>
            <span className="font-medium text-white">1. Install</span> — copy{' '}
            <code className="rounded bg-background px-1.5 py-0.5 text-gray-300">
              MTLTraderSync.mq5
            </code>{' '}
            into <code className="rounded bg-background px-1.5 py-0.5 text-gray-300">
              MQL5/Experts
            </code>{' '}
            and press F7 in MetaEditor.
          </li>
          <li>
            <span className="font-medium text-white">2. Attach</span> — add the EA to any
            one chart and allow this site under Tools → Options → Expert Advisors →
            “Allow WebRequest for listed URL”.
          </li>
          <li>
            <span className="font-medium text-white">3. Configure</span> — paste your
            user id and the token below into the EA inputs, then turn AutoTrading on.
          </li>
          <li>
            <span className="font-medium text-white">4. Enforce</span> — a lock deletes
            resting orders and closes a fill opened after the limit. A manual market order
            still fills before the EA can see it, and the lock releases if the journal is
            unreachable for five minutes.
          </li>
        </ol>
      </div>

      <div className="bg-surface rounded-xl border border-border p-6">
        <div className="flex items-center gap-3 mb-4">
          <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
            <Key className="w-5 h-5 text-primary" />
          </div>
          <div>
            <h2 className="text-lg font-semibold text-white">Desktop agent token</h2>
            <p className="text-sm text-gray-400">
              Only needed if you run the agent on a Windows PC — the automatic connection above
              uses no token
            </p>
          </div>
        </div>
        <div className="flex flex-col sm:flex-row items-stretch gap-2">
          <code className="flex-1 min-w-0 break-all bg-background px-4 py-3 rounded-lg text-sm text-gray-300 font-mono">
            {token}
          </code>
          <button
            onClick={() => { navigator.clipboard.writeText(token); setCopied(true); setTimeout(() => setCopied(false), 2000) }}
            className="px-4 py-3 bg-surface-light rounded-lg hover:bg-surface transition-colors self-stretch sm:self-auto"
          >
            {copied ? <Check className="w-5 h-5 text-green-400" /> : <Copy className="w-5 h-5 text-gray-400" />}
          </button>
          <button
            onClick={regenerateToken}
            disabled={loading}
            className="flex items-center justify-center gap-2 px-4 py-3 bg-surface-light rounded-lg hover:bg-surface transition-colors text-sm text-gray-300 disabled:opacity-50"
          >
            <RefreshCw className="w-4 h-4 text-gray-400" />
            Rotate
          </button>
        </div>
        <p className="text-xs text-gray-500 mt-2">Rotate the token if it ever leaks. Old tokens stop working immediately.</p>
      </div>

      <div className="bg-surface rounded-xl border border-border p-6">
        <div className="flex items-center gap-3 mb-4">
          <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
            <Server className="w-5 h-5 text-primary" />
          </div>
          <div>
            <h2 className="text-lg font-semibold text-white">MT5 Connection Details</h2>
              <p className="text-sm text-gray-400">Enter these once, then download your setup file</p>
          </div>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <BrokerPicker
            value={brokerName}
            onChange={setBrokerName}
            label="Broker Name"
            placeholder="Search e.g. IC Markets, Exness, XM"
          />
          <div>
            <label className="block text-sm font-medium text-gray-400 mb-2">Server</label>
            <input
              type="text"
              value={server}
              onChange={(e) => setServer(e.target.value)}
              placeholder="e.g., MetaQuotes-Demo"
              className="w-full bg-background border border-border rounded-lg px-4 py-2.5 text-white placeholder-gray-500 focus:outline-none focus:border-primary"
            />
            <ServerSuggestions broker={brokerName} query={server} onPick={setServer} />
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
        </div>
        <button
          onClick={downloadConfig}
          disabled={!brokerName || !server || !login}
          className="mt-4 flex items-center gap-2 px-4 py-2 bg-primary hover:bg-primary-dark text-white rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
        >
          <Download className="w-4 h-4" />
          Download setup file
        </button>
        <p className="text-xs text-gray-500 mt-3">The setup file contains your sync token. Keep it private. Your MT5 password is entered only into the local agent and never sent to our servers.</p>
      </div>

      <div className="bg-surface rounded-xl border border-border p-6">
        <div className="flex items-center gap-3 mb-4">
          <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
            <Download className="w-5 h-5 text-primary" />
          </div>
          <div>
            <h2 className="text-lg font-semibold text-white">Running the Python agent yourself</h2>
            <p className="text-sm text-gray-400">
              Syncs trades only — hard-lock enforcement needs the Expert Advisor above.
            </p>
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
              <p className="text-white font-medium">Run the agent with one command</p>
              <div className="mt-2 flex items-center gap-2">
                <code className="flex-1 bg-background px-3 py-2 rounded text-sm text-gray-300 overflow-x-auto">
                  python mt5_agent.py --config mtl-trader-config.json
                </code>
                <button
                  onClick={copyCommand}
                  className="px-3 py-2 bg-primary hover:bg-primary-dark rounded-lg transition-colors flex-shrink-0"
                >
                  {copied ? <Check className="w-4 h-4 text-white" /> : <Copy className="w-4 h-4 text-white" />}
                </button>
              </div>
              <p className="text-xs text-gray-500 mt-2">Put the downloaded setup file beside mt5_agent.py. The agent will ask only for your MT5 password.</p>
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
              <li>• Your credentials are never stored on our servers (you type the password only in the local prompt)</li>
              <li>• All data is encrypted during transfer (HTTPS)</li>
            </ul>
          </div>
        </div>
      </div>
        </div>
      </details>
    </div>
  )
}
