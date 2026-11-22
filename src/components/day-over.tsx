'use client'

import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import {
  AlertTriangle,
  CheckCircle2,
  Clock,
  Loader2,
  ShieldAlert,
  ShieldCheck,
} from 'lucide-react'
import { authedFetch } from '@/lib/api'
import { formatCurrency } from '@/lib/utils'
import type { DayStateResponse } from '@/lib/daily-stop'

/**
 * The daily stop, in the place the trader actually looks.
 *
 * The card has three states, and each one exists to make one sentence true:
 *
 *  - inside the budget: "here is what is left", so the limit is a number the
 *    trader can see shrinking instead of a vague intention;
 *  - at the stop: "the day is closed", so the rule feels like a boundary rather
 *    than a suggestion, with the debrief and the override in the same place;
 *  - after an override: "you chose this, here is your reason", so the decision
 *    is recorded rather than forgotten.
 *
 * It never pretends to block MT5. It closes the journal, which is the surface
 * this app owns, and leaves the broker to the broker.
 */

function resetLabel(endIso: string, now: Date): string {
  const end = new Date(endIso)
  const ms = end.getTime() - now.getTime()
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

export default function DayOver() {
  const [data, setData] = useState<DayStateResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [now, setNow] = useState(() => new Date())
  const [followed, setFollowed] = useState<boolean | null>(null)
  const [valid, setValid] = useState<boolean | null>(null)
  const [note, setNote] = useState('')
  const [overrideOpen, setOverrideOpen] = useState(false)
  const [reason, setReason] = useState('')

  const load = useCallback(async () => {
    try {
      const response = await authedFetch('/api/day-state')
      if (response.ok) setData((await response.json()) as DayStateResponse)
    } catch {
      // The card is an extra; a dashboard must render without it.
    } finally {
      setLoading(false)
    }
  }, [])

  // The first read and the poll are defined inside the effect so the only
  // state writes happen after the request resolves, not during the render pass.
  useEffect(() => {
    let active = true
    async function refresh() {
      try {
        const response = await authedFetch('/api/day-state')
        if (active && response.ok) {
          setData((await response.json()) as DayStateResponse)
        }
      } catch {
        // Keep the last good state; the next poll may succeed.
      } finally {
        if (active) setLoading(false)
      }
    }
    void refresh()
    const timer = setInterval(() => {
      setNow(new Date())
      void refresh()
    }, 60_000)
    return () => {
      active = false
      clearInterval(timer)
    }
  }, [])

  async function saveDebrief() {
    if (followed === null || saving) return
    setSaving(true)
    setError('')
    try {
      const response = await authedFetch('/api/day-state', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'debrief', followed, valid, note }),
      })
      const body = (await response.json()) as { error?: string }
      if (!response.ok) {
        setError(body.error || 'Could not save your answer.')
      } else {
        await load()
      }
    } catch {
      setError('Could not save your answer. Check your connection and try again.')
    } finally {
      setSaving(false)
    }
  }

  async function saveOverride() {
    if (reason.trim().length < 10 || saving) {
      setError('Say why you are overriding the stop (at least 10 characters).')
      return
    }
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
        setError(body.error || 'Could not save the override.')
      } else {
        setOverrideOpen(false)
        setReason('')
        await load()
      }
    } catch {
      setError('Could not save the override. Check your connection and try again.')
    } finally {
      setSaving(false)
    }
  }

  if (loading && !data) return null
  if (!data || data.missing) return null

  const { state, rules } = data
  if (!state.configured) return null

  const reset = resetLabel(data.day.end, now)
  const clock = resetClock(data.day.end, rules.timeZone)
  const lossPct =
    state.lossLimit > 0 ? Math.min(100, (state.lossUsed / state.lossLimit) * 100) : 0
  const tradePct =
    state.maxTrades > 0 ? Math.min(100, (state.tradesCount / state.maxTrades) * 100) : 0
  const usedPct = Math.max(lossPct, tradePct)
  const lossBreached = state.lossLimit > 0 && state.lossUsed >= state.lossLimit
  const tone = state.breached
    ? 'danger'
    : state.atLimit
      ? 'warning'
      : 'ok'

  // ------------------------------------------------------------ breach card
  if (state.breached) {
    return (
      <section className="overflow-hidden rounded-xl border border-danger/40 bg-surface">
        <div className="border-b border-danger/20 bg-danger/10 px-4 py-3 sm:px-5">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div className="flex items-center gap-2">
              <ShieldAlert className="h-5 w-5 text-danger" />
              <p className="text-sm font-semibold text-white">Day closed</p>
            </div>
            <span className="rounded-full border border-danger/30 bg-danger/10 px-2.5 py-1 text-[11px] font-medium text-danger">
              {data.overridden ? 'Stop overridden' : 'Daily stop reached'}
            </span>
          </div>
          <p className="mt-1.5 text-sm leading-relaxed text-danger">
            {state.capReached && !lossBreached
              ? `You reached your ${state.maxTrades}-entry limit for the day.`
              : `Today closed at ${formatCurrency(state.realizedPnl)} against a ${formatCurrency(state.lossLimit)} budget.`}
          </p>
          <p className="mt-1 text-xs text-gray-400">
            {data.lock?.mode === 'hard'
              ? `The journal and MT5 reopen at ${clock} — ${reset}.`
              : data.lock?.mode === 'soft'
                ? `MT5 reopens at ${clock} — ${reset}. The journal stays open.`
                : `The journal reopens at ${clock} — ${reset}.`}{' '}
            The rule did its job; the rest of the day is not yours to trade back.
          </p>
        </div>

        <div className="space-y-4 px-4 py-4 sm:px-5">
          <div className="grid gap-3 sm:grid-cols-3">
            <Stat
              label="Loss today"
              value={`${formatCurrency(-state.lossUsed)}`}
              detail={`of ${formatCurrency(state.lossLimit)}`}
            />
            <Stat
              label="Entries"
              value={`${state.tradesCount}`}
              detail={state.maxTrades > 0 ? `of ${state.maxTrades} allowed` : 'no cap set'}
            />
            <Stat
              label="After the stop"
              value={`${state.afterStopCount}`}
              detail={
                state.afterStopCount > 0
                  ? `${formatCurrency(state.afterStopPnl)} · tagged after_stop`
                  : 'none — you stopped'
              }
              tone={state.afterStopCount > 0 ? 'danger' : 'ok'}
            />
          </div>

          {error && (
            <p className="rounded-lg border border-warning/30 bg-warning/10 p-2.5 text-xs text-warning">
              {error}
            </p>
          )}

          {data.overridden ? (
            <div className="rounded-lg border border-warning/30 bg-warning/10 p-3">
              <p className="text-xs font-medium text-warning">Override recorded</p>
              <p className="mt-1 text-xs leading-relaxed text-gray-400">
                “{data.override?.reason}”
              </p>
            </div>
          ) : data.debrief ? (
            <div className="rounded-lg border border-border bg-background p-3">
              <p className="text-xs font-medium text-white">Debrief recorded</p>
              <p className="mt-1 text-xs leading-relaxed text-gray-400">
                {data.debrief.followed === true
                  ? 'You stopped when the limit was reached.'
                  : 'You kept trading after the limit.'}
                {data.debrief.valid === true
                  ? ' The setup was valid.'
                  : data.debrief.valid === false
                    ? ' The setup was not valid.'
                    : ''}
                {data.debrief.note ? ` “${data.debrief.note}”` : ''}
              </p>
            </div>
          ) : (
            <div className="rounded-lg border border-border bg-background p-3">
              <p className="text-xs font-semibold text-white">Twenty-second debrief</p>
              <p className="mt-0.5 text-xs text-gray-500">
                The stop is only useful if the day is reviewed. Be honest — nobody else reads it.
              </p>

              <div className="mt-3">
                <p className="text-[11px] uppercase tracking-wide text-gray-500">
                  Did you stop at the limit?
                </p>
                <div className="mt-1.5 flex gap-2">
                  <Choice
                    active={followed === true}
                    onClick={() => setFollowed(true)}
                    icon={CheckCircle2}
                    label="Yes, I stopped"
                  />
                  <Choice
                    active={followed === false}
                    onClick={() => setFollowed(false)}
                    icon={AlertTriangle}
                    label="No, I kept trading"
                  />
                </div>
              </div>

              <div className="mt-3">
                <p className="text-[11px] uppercase tracking-wide text-gray-500">
                  Was the last setup valid? <span className="normal-case">(optional)</span>
                </p>
                <div className="mt-1.5 flex gap-2">
                  <Choice
                    active={valid === true}
                    onClick={() => setValid(true)}
                    icon={CheckCircle2}
                    label="Valid"
                  />
                  <Choice
                    active={valid === false}
                    onClick={() => setValid(false)}
                    icon={AlertTriangle}
                    label="Not valid"
                  />
                </div>
              </div>

              <textarea
                value={note}
                onChange={(event) => setNote(event.target.value)}
                rows={2}
                maxLength={1000}
                placeholder="What triggered the stop, in one sentence."
                className="mt-3 w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-white placeholder-gray-600 focus:border-primary focus:outline-none"
              />

              <button
                type="button"
                onClick={() => void saveDebrief()}
                disabled={followed === null || saving}
                className="btn btn-primary mt-3 px-3 py-1.5 text-xs disabled:opacity-50"
              >
                {saving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <ShieldCheck className="h-3.5 w-3.5" />}
                Save debrief
              </button>
            </div>
          )}

          {!data.debrief && !data.overridden && data.lock?.mode === 'hard' && (
            <p className="text-xs leading-relaxed text-gray-500">
              Hard lock is enforced by your MT5 sync EA. It has no in-app release — it clears when
              the trading day rolls over.
            </p>
          )}

          {!data.debrief && !data.overridden && data.lock?.mode !== 'hard' && (
            <div>
              {!overrideOpen ? (
                <button
                  type="button"
                  onClick={() => setOverrideOpen(true)}
                  className="text-xs font-medium text-gray-500 underline decoration-border underline-offset-2 transition-colors hover:text-gray-300"
                >
                  Override today’s stop
                </button>
              ) : (
                <div className="rounded-lg border border-border bg-background p-3">
                  <p className="text-xs font-medium text-white">
                    Override the stop
                  </p>
                  <p className="mt-0.5 text-xs text-gray-500">
                    This reopens the journal for today. It is recorded on the day, not hidden.
                  </p>
                  <textarea
                    value={reason}
                    onChange={(event) => setReason(event.target.value)}
                    rows={2}
                    maxLength={500}
                    placeholder="Why is this trade worth breaking the rule for?"
                    className="mt-2 w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-white placeholder-gray-600 focus:border-primary focus:outline-none"
                  />
                  <div className="mt-2 flex gap-2">
                    <button
                      type="button"
                      onClick={() => void saveOverride()}
                      disabled={saving || reason.trim().length < 10}
                      className="btn btn-secondary px-3 py-1.5 text-xs disabled:opacity-50"
                    >
                      {saving ? 'Saving…' : 'Override today'}
                    </button>
                    <button
                      type="button"
                      onClick={() => setOverrideOpen(false)}
                      className="btn btn-secondary px-3 py-1.5 text-xs"
                    >
                      Cancel
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}

          <div className="flex flex-wrap items-center gap-3 text-xs text-gray-500">
            <Link href="/dashboard/playbook" className="font-medium text-primary hover:underline">
              Review the rules
            </Link>
            <span className="text-border">·</span>
            <Link href="/dashboard/trades" className="hover:text-gray-300">
              See today’s trades
            </Link>
          </div>
        </div>
      </section>
    )
  }

  // ------------------------------------------------------------ inside strip
  return (
    <section
      className={
        tone === 'warning'
          ? 'rounded-xl border border-warning/40 bg-warning/5 px-4 py-3'
          : 'rounded-xl border border-border bg-surface px-4 py-3'
      }
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          {tone === 'warning' ? (
            <AlertTriangle className="h-4 w-4 text-warning" />
          ) : (
            <ShieldCheck className="h-4 w-4 text-success" />
          )}
          <p className="text-xs font-semibold text-white">
            Daily stop
            {tone === 'warning' ? ' — close to the limit' : ''}
          </p>
          <span className="hidden items-center gap-1 text-[11px] text-gray-500 sm:flex">
            <Clock className="h-3 w-3" />
            {reset}
          </span>
        </div>
        <p className="text-[11px] tabular-nums text-gray-400">
          {state.lossLimit > 0 && (
            <>
              {formatCurrency(-state.lossUsed)} of {formatCurrency(state.lossLimit)}
              {state.headroom > 0 ? ` · ${formatCurrency(state.headroom)} left` : ''}
            </>
          )}
          {state.lossLimit > 0 && state.maxTrades > 0 && <span className="mx-1.5 text-border">·</span>}
          {state.maxTrades > 0 && (
            <>
              {state.tradesCount}/{state.maxTrades} entries
            </>
          )}
        </p>
      </div>

      <div className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-surface-light">
        <div
          className={
            tone === 'warning'
              ? 'h-1.5 rounded-full bg-warning'
              : 'h-1.5 rounded-full bg-primary'
          }
          style={{ width: `${usedPct}%` }}
        />
      </div>

      {tone === 'warning' && (
        <p className="mt-1.5 text-[11px] text-warning">
          One more loss of this size reaches your stop. Size the next position for the budget,
          not for the recovery.
        </p>
      )}
    </section>
  )
}

function Stat({
  label,
  value,
  detail,
  tone = 'neutral',
}: {
  label: string
  value: string
  detail: string
  tone?: 'neutral' | 'ok' | 'danger'
}) {
  return (
    <div className="rounded-lg border border-border bg-background p-3">
      <p className="text-[11px] uppercase tracking-wide text-gray-500">{label}</p>
      <p
        className={
          tone === 'danger'
            ? 'num mt-1 text-lg font-semibold text-danger'
            : tone === 'ok'
              ? 'num mt-1 text-lg font-semibold text-success'
              : 'num mt-1 text-lg font-semibold text-white'
        }
      >
        {value}
      </p>
      <p className="mt-0.5 text-[11px] text-gray-500">{detail}</p>
    </div>
  )
}

function Choice({
  active,
  onClick,
  icon: Icon,
  label,
}: {
  active: boolean
  onClick: () => void
  icon: typeof CheckCircle2
  label: string
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={
        active
          ? 'flex items-center gap-1.5 rounded-lg border border-primary bg-primary/10 px-2.5 py-1.5 text-xs font-medium text-primary'
          : 'flex items-center gap-1.5 rounded-lg border border-border px-2.5 py-1.5 text-xs text-gray-400 transition-colors hover:text-white'
      }
    >
      <Icon className="h-3.5 w-3.5" />
      {label}
    </button>
  )
}
