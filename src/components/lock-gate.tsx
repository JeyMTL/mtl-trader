'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { Clock, Loader2, Lock, ShieldAlert, Unlock } from 'lucide-react'
import { authedFetch } from '@/lib/api'
import { supabase } from '@/lib/supabase'
import { formatCurrency } from '@/lib/utils'
import type { DayStateResponse } from '@/lib/daily-stop'

/**
 * The hard lock: the journal itself, frozen.
 *
 * It sits above every dashboard route, so a trader cannot browse to the trade
 * form to get around the gate. This is the whole app, which is the point — a
 * rule you have to walk past is a rule you will.
 *
 * Soft mode does not render this. There the guard clears resting orders in MT5
 * while the journal stays usable, and a slim notice offers the same written
 * lift the Day Over card uses. A hard lock has no in-app release: the guard
 * applies it and offering a bypass would make it decorative.
 */

function resetLabel(endIso: string, now: Date): string {
  const ms = new Date(endIso).getTime() - now.getTime()
  if (!Number.isFinite(ms)) return ''
  if (ms <= 0) return 'resetting now'
  const totalMinutes = Math.ceil(ms / 60_000)
  const hours = Math.floor(totalMinutes / 60)
  const minutes = totalMinutes % 60
  if (hours <= 0) return `in ${minutes} min`
  return minutes === 0 ? `in ${hours} h` : `in ${hours} h ${minutes} min`
}

function resetClock(endIso: string, timeZone: string): string {
  try {
    return new Intl.DateTimeFormat('en-US', {
      timeZone,
      weekday: 'short',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).format(new Date(endIso))
  } catch {
    return new Date(endIso).toLocaleString()
  }
}

export default function LockGate() {
  const pathname = usePathname()
  const router = useRouter()
  const [data, setData] = useState<DayStateResponse | null>(null)
  const [now, setNow] = useState(() => new Date())
  const [unlockOpen, setUnlockOpen] = useState(false)
  const [reason, setReason] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true
    async function refresh() {
      try {
        const response = await authedFetch('/api/day-state')
        if (active && response.ok) {
          setData((await response.json()) as DayStateResponse)
        }
      } catch {
        // A failed poll must not lock a trader out; the last good state stands.
      }
    }
    void refresh()
    // A synced close changes the day within seconds; realtime is the fast path
    // and the short poll covers a project where the tables are not in the
    // realtime publication yet.
    const tradeChannel = supabase
      .channel('day-lock-trades')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'trades' }, () => {
        void refresh()
      })
      .subscribe()
    const settingsChannel = supabase
      .channel('day-lock-settings')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'playbooks' }, () => {
        void refresh()
      })
      .subscribe()
    const timer = setInterval(() => {
      setNow(new Date())
      void refresh()
    }, 5_000)
    function onVisible() {
      if (document.visibilityState === 'visible') void refresh()
    }
    document.addEventListener('visibilitychange', onVisible)
    return () => {
      active = false
      clearInterval(timer)
      void supabase.removeChannel(tradeChannel)
      void supabase.removeChannel(settingsChannel)
      document.removeEventListener('visibilitychange', onVisible)
    }
  }, [])

  const hard = data?.lock.mode === 'hard'
  const active = data?.lock.active === true && data.state.breached

  async function unfreeze() {
    if (!data || saving || reason.trim().length < 10) return
    setSaving(true)
    setError('')
    try {
      const response = await authedFetch('/api/day-state', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'override', reason }),
      })
      const body = (await response.json()) as { error?: string }
      if (!response.ok) {
        setError(body.error ?? 'Could not lift the stop. Try again.')
        return
      }
      // A full reload, not just this gate's state: the Day Over card and the
      // trade form fetched the old answer and must not keep saying the day is
      // closed for the next minute.
      window.location.reload()
    } catch {
      setError('Could not reach the server. Check your connection and try again.')
    } finally {
      setSaving(false)
    }
  }

  if (!data || !active) return null

  // Soft acts in MT5, not on the journal: a usable notice, never a wall.
  if (!hard) return <SoftLockBanner data={data} />

  // Billing and account deletion must not be held hostage by a trading rule.
  // Settings cannot create a trade, so it is the one journal route left open.
  if (pathname.startsWith('/dashboard/settings')) return null

  const state = data.state
  const limitReached = state.lossLimit > 0 && state.lossUsed >= state.lossLimit

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Daily stop reached"
      className="fixed inset-0 z-[120] flex items-center justify-center overflow-y-auto bg-background/95 px-4 py-10 backdrop-blur-md"
    >
      <div className="w-full max-w-md">
        <div className="flex flex-col items-center text-center">
          <span
            className={
              hard
                ? 'flex h-14 w-14 items-center justify-center rounded-2xl border border-danger/40 bg-danger/10 text-danger'
                : 'flex h-14 w-14 items-center justify-center rounded-2xl border border-warning/40 bg-warning/10 text-warning'
            }
          >
            {hard ? <ShieldAlert className="h-7 w-7" /> : <Lock className="h-7 w-7" />}
          </span>
          <p className="mt-4 text-[11px] font-semibold uppercase tracking-[0.16em] text-gray-500">
            {hard ? 'Hard lock' : 'Soft lock'}
          </p>
          <h1 className="mt-1 text-2xl font-bold text-white">Your day is over</h1>
          <p className="mt-2 text-sm leading-relaxed text-gray-400">
            {limitReached ? (
              <>
                You reached your loss budget —{' '}
                <span className="tabular-nums text-white">{formatCurrency(state.lossUsed)}</span>{' '}
                of {formatCurrency(state.lossLimit)}.
              </>
            ) : (
              <>
                You reached your entry cap —{' '}
                <span className="tabular-nums text-white">
                  {state.tradesCount} of {state.maxTrades}
                </span>{' '}
                entries.
              </>
            )}{' '}
            The journal is closed until the next session.
          </p>
        </div>

        <div className="mt-5 grid grid-cols-3 gap-2 text-center">
          <div className="rounded-xl border border-border bg-surface p-3">
            <p className="text-[10px] uppercase tracking-wide text-gray-500">Realised</p>
            <p
              className={`num mt-1 text-sm font-semibold ${
                state.realizedPnl < 0 ? 'text-danger' : 'text-white'
              }`}
            >
              {formatCurrency(state.realizedPnl)}
            </p>
          </div>
          <div className="rounded-xl border border-border bg-surface p-3">
            <p className="text-[10px] uppercase tracking-wide text-gray-500">Entries</p>
            <p className="num mt-1 text-sm font-semibold text-white">{state.tradesCount}</p>
          </div>
          <div className="rounded-xl border border-border bg-surface p-3">
            <p className="text-[10px] uppercase tracking-wide text-gray-500">After stop</p>
            <p
              className={`num mt-1 text-sm font-semibold ${
                state.afterStopCount > 0 ? 'text-danger' : 'text-white'
              }`}
            >
              {state.afterStopCount}
            </p>
          </div>
        </div>

        <p className="mt-4 flex items-center justify-center gap-2 text-xs text-gray-500">
          <Clock className="h-3.5 w-3.5" />
          Resets {resetClock(data.day.end, data.rules.timeZone)} ·{' '}
          {resetLabel(data.day.end, now)}
        </p>

        {hard && (
          <div className="mt-6 rounded-xl border border-border bg-surface p-4">
            <p className="text-xs leading-relaxed text-gray-400">
              Your MT5 guard removes resting orders while the day is locked and closes any
              position opened after the stop. It cannot stop a manual market order — only your
              broker can. A manual market order can
              still fill before any EA sees it — only the broker can stop that click.
            </p>
            <p className="mt-2 text-xs leading-relaxed text-gray-500">
              There is no in-app release for a hard lock. It clears at the start of your next
              trading day, and the EA releases orders on its next poll after that. Editing the rule
              applies from the next session.
            </p>
            <Link
              href="/support"
              className="mt-3 inline-block text-xs font-medium text-primary hover:underline"
            >
              Something is wrong — contact support
            </Link>
          </div>
        )}

        {!hard && (
          <div className="mt-6">
            {!unlockOpen ? (
              <button
                type="button"
                onClick={() => setUnlockOpen(true)}
                className="flex w-full items-center justify-center gap-2 rounded-xl border border-border bg-surface px-4 py-3 text-sm font-semibold text-white transition-colors hover:border-gray-600"
              >
                <Unlock className="h-4 w-4" /> Lift the stop
              </button>
            ) : (
              <div className="rounded-xl border border-border bg-surface p-4">
                <p className="text-sm font-semibold text-white">Lift the stop — once today</p>
                <p className="mt-1 text-xs leading-relaxed text-gray-500">
                  This reopens the journal and records your reason on today. It is a grace run,
                  not a reset: the stop re-arms on the trades you take after it, with the same
                  budget. Lose that too and the day stays closed.
                </p>
                <textarea
                  value={reason}
                  onChange={(event) => setReason(event.target.value)}
                  rows={3}
                  maxLength={500}
                  autoFocus
                  placeholder="Why is trading past the stop worth it today?"
                  className="mt-3 w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-white placeholder-gray-600 focus:border-primary focus:outline-none"
                />
                {error ? <p className="mt-2 text-xs text-danger">{error}</p> : null}
                <div className="mt-3 flex gap-2">
                  <button
                    type="button"
                    onClick={() => void unfreeze()}
                    disabled={saving || reason.trim().length < 10}
                    className="btn btn-primary flex-1 px-3 py-2 text-xs disabled:opacity-50"
                  >
                    {saving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : null}
                    {saving ? 'Lifting…' : 'Lift and keep trading'}
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      setUnlockOpen(false)
                      setError('')
                    }}
                    disabled={saving}
                    className="btn btn-secondary px-3 py-2 text-xs"
                  >
                    Cancel
                  </button>
                </div>
                <p className="mt-2 text-[11px] text-gray-600">
                  At least 10 characters. Your broker is not affected by this button.
                </p>
              </div>
            )}
          </div>
        )}

        <p className="mt-5 text-center text-[11px] leading-relaxed text-gray-600">
          Reaching the stop is a green day. The trades you took before it are already in your
          journal.
        </p>

        <div className="mt-3 flex justify-center gap-4 text-[11px] text-gray-600">
          <Link href="/support" className="hover:text-gray-400">
            Support
          </Link>
          <button
            type="button"
            onClick={async () => {
              await supabase.auth.signOut()
              router.push('/')
            }}
            className="hover:text-gray-400"
          >
            Sign out
          </button>
        </div>
      </div>
    </div>
  )
}

/**
 * The soft lock acts in MT5, not on the journal. The notice stays out of
 * the way but keeps the override one tap away, and the reason lands on the same
 * `trading_days` row the Day Over card writes.
 */
function SoftLockBanner({ data }: { data: DayStateResponse }) {
  const [open, setOpen] = useState(false)
  const [reason, setReason] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const state = data.state
  const limitReached = state.lossLimit > 0 && state.lossUsed >= state.lossLimit

  async function unfreeze() {
    if (saving || reason.trim().length < 10) return
    setSaving(true)
    setError('')
    try {
      const response = await authedFetch('/api/day-state', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'override', reason }),
      })
      const body = (await response.json()) as { error?: string }
      if (!response.ok) {
        setError(body.error ?? 'Could not lift the stop. Try again.')
        return
      }
      window.location.reload()
    } catch {
      setError('Could not reach the server. Check your connection and try again.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <>
      <div className="fixed inset-x-0 bottom-3 z-[120] px-3">
        <div className="mx-auto flex max-w-md items-center gap-3 rounded-xl border border-warning/40 bg-surface/95 px-3 py-2.5 shadow-lg backdrop-blur">
          <Lock className="h-4 w-4 shrink-0 text-warning" />
          <div className="min-w-0 flex-1">
            <p className="text-xs font-semibold text-white">Soft lock · guard active</p>
            <p className="truncate text-[11px] text-gray-400">
              {limitReached
                ? `${formatCurrency(state.lossUsed)} of ${formatCurrency(state.lossLimit)}`
                : `${state.tradesCount} of ${state.maxTrades} entries`}{' '}
              · the journal stays open
            </p>
          </div>
          <button
            type="button"
            onClick={() => setOpen(true)}
            className="shrink-0 rounded-lg border border-warning/40 px-2.5 py-1 text-[11px] font-medium text-warning transition-colors hover:bg-warning/10"
          >
            Lift
          </button>
        </div>
      </div>

      {open ? (
        <div className="fixed inset-0 z-[121] flex items-end justify-center bg-black/50 p-4 sm:items-center">
          <div className="w-full max-w-sm rounded-xl border border-border bg-surface p-4">
            <p className="text-sm font-semibold text-white">Lift the stop — once today</p>
            <p className="mt-1 text-xs leading-relaxed text-gray-500">
              Saving your reason reopens the day, and the guard stops removing orders on its
              next poll. It is a grace run, not a reset: the stop re-arms on the trades you take
              after this, with the same budget. Lose that too and the day stays closed.
            </p>
            <textarea
              value={reason}
              onChange={(event) => setReason(event.target.value)}
              rows={3}
              maxLength={500}
              autoFocus
              placeholder="Why is trading past the stop worth it today?"
              className="mt-3 w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-white placeholder-gray-600 focus:border-primary focus:outline-none"
            />
            {error ? <p className="mt-2 text-xs text-danger">{error}</p> : null}
            <div className="mt-3 flex gap-2">
              <button
                type="button"
                onClick={() => void unfreeze()}
                disabled={saving || reason.trim().length < 10}
                className="btn btn-primary flex-1 px-3 py-2 text-xs disabled:opacity-50"
              >
                {saving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Unlock className="h-3.5 w-3.5" />}
                {saving ? 'Lifting…' : 'Lift the stop'}
              </button>
              <button
                type="button"
                onClick={() => {
                  setOpen(false)
                  setError('')
                }}
                disabled={saving}
                className="btn btn-secondary px-3 py-2 text-xs"
              >
                Cancel
              </button>
            </div>
            <p className="mt-2 text-[11px] text-gray-600">
              At least 10 characters. Your broker is not affected by this button.
            </p>
          </div>
        </div>
      ) : null}
    </>
  )
}
