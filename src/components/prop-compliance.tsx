'use client'

import { useCallback, useEffect, useState } from 'react'
import { AlertTriangle, CheckCircle2, Pencil, ShieldCheck, X } from 'lucide-react'
import { authedFetch } from '@/lib/api'
import { cn, formatCurrency } from '@/lib/utils'
import {
  DEFAULT_PROP_RULES,
  propStatusLevel,
  type PropRules,
  type PropStatus,
} from '@/lib/prop-rules'

/**
 * Prop-firm rule monitor.
 *
 * A prop evaluation is lost by breaking a rule, so the card leads with headroom
 * rather than P&L: how much of today's loss budget is left, how far the trailing
 * drawdown can go before the account is gone, and how many trading days remain
 * before the payout is valid. Everything shown comes from `prop_status()`, so the
 * browser never decides whether a rule is breached.
 */

interface Payload {
  configured?: boolean
  missing?: boolean
  rules?: PropRules
  status?: PropStatus
  error?: string
}

const LEVEL_STYLE = {
  ok: { chip: 'bg-success/15 text-success border-success/30', icon: CheckCircle2, label: 'Within rules' },
  warning: { chip: 'bg-warning/15 text-warning border-warning/30', icon: AlertTriangle, label: 'Close to a limit' },
  breach: { chip: 'bg-danger/15 text-danger border-danger/30', icon: AlertTriangle, label: 'Rule breached' },
} as const

function Field({
  label,
  suffix,
  value,
  onChange,
  step = '1',
}: {
  label: string
  suffix?: string
  value: number
  onChange: (value: number) => void
  step?: string
}) {
  return (
    <label className="block">
      <span className="text-xs text-gray-400">{label}</span>
      <span className="mt-1 flex items-center gap-2 rounded-lg border border-border bg-background px-3 py-2">
        <input
          type="number"
          min="0"
          step={step}
          value={value}
          onChange={(event) => onChange(Number(event.target.value))}
          className="w-full bg-transparent text-sm text-white outline-none"
        />
        {suffix && <span className="shrink-0 text-xs text-gray-500">{suffix}</span>}
      </span>
    </label>
  )
}

function Meter({
  label,
  detail,
  used,
  limit,
  tone,
}: {
  label: string
  detail: string
  used: number
  limit: number
  tone: 'ok' | 'warning' | 'breach'
}) {
  const pct = limit > 0 ? Math.min(100, Math.max(0, (used / limit) * 100)) : 0
  return (
    <div className="rounded-lg border border-border bg-background p-3">
      <div className="flex items-baseline justify-between gap-2">
        <p className="text-xs uppercase tracking-wide text-gray-500">{label}</p>
        <p className="text-xs tabular-nums text-gray-400">
          {formatCurrency(used)} / {formatCurrency(limit)}
        </p>
      </div>
      <div className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-surface-light">
        <div
          className={cn(
            'h-1.5 rounded-full',
            tone === 'breach' ? 'bg-danger' : tone === 'warning' ? 'bg-warning' : 'bg-primary'
          )}
          style={{ width: `${pct}%` }}
        />
      </div>
      <p className="mt-1.5 text-[11px] text-gray-500">{detail}</p>
    </div>
  )
}

export function PropCompliance() {
  const [payload, setPayload] = useState<Payload | null>(null)
  const [loading, setLoading] = useState(true)
  const [editing, setEditing] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [form, setForm] = useState<PropRules>(DEFAULT_PROP_RULES)

  const apply = useCallback((next: Payload) => {
    setPayload(next)
    if (next.rules) setForm({ ...DEFAULT_PROP_RULES, ...next.rules })
  }, [])

  useEffect(() => {
    let active = true
    authedFetch('/api/prop-rules')
      .then(async (response) => {
        const body = (await response.json()) as Payload
        return { ok: response.ok, body }
      })
      .then(({ ok, body }) => {
        if (!active) return
        if (!ok) {
          setError(body.error || 'Could not load your prop rules.')
        } else {
          apply(body)
          // First visit: open the form rather than showing an empty monitor.
          if (!body.configured) setEditing(true)
        }
        setLoading(false)
      })
      .catch(() => {
        if (!active) return
        setError('Could not load your prop rules.')
        setLoading(false)
      })
    return () => {
      active = false
    }
  }, [apply])

  const save = async () => {
    setSaving(true)
    setError('')
    try {
      const response = await authedFetch('/api/prop-rules', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(form),
      })
      const body = (await response.json()) as Payload
      if (!response.ok) {
        setError(body.error || 'Could not save your prop rules.')
      } else {
        apply(body)
        setEditing(false)
      }
    } catch {
      setError('Could not save your prop rules. Check your connection and try again.')
    }
    setSaving(false)
  }

  if (loading) {
    return (
      <div className="rounded-xl border border-border bg-surface p-4 sm:p-5">
        <p className="text-sm text-gray-500">Loading prop rules…</p>
      </div>
    )
  }

  if (payload?.missing) {
    return (
      <div className="rounded-xl border border-warning/30 bg-warning/10 p-4 text-sm text-warning">
        Prop-rule monitoring needs the database migration
        {' '}
        <span className="font-mono text-xs">20261111_prop_rules.sql</span>. Apply it and reload.
      </div>
    )
  }

  const status = payload?.status
  const level = propStatusLevel(status?.status)
  const style = LEVEL_STYLE[level]
  const StatusIcon = style.icon

  const header = (
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div className="flex items-start gap-2">
        <ShieldCheck className="mt-0.5 h-5 w-5 text-primary" />
        <div>
          <h2 className="text-base font-semibold text-white">Prop rule monitor</h2>
          <p className="mt-0.5 text-sm text-gray-400">
            {status
              ? 'Headroom against the evaluation rules you set.'
              : 'Track a prop-firm evaluation: daily loss, trailing drawdown and the profit target.'}
          </p>
        </div>
      </div>
      {status && (
        <div className="flex items-center gap-2">
          <span className={cn('inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium', style.chip)}>
            <StatusIcon className="h-3.5 w-3.5" />
            {style.label}
          </span>
          <button
            type="button"
            onClick={() => setEditing((current) => !current)}
            className="inline-flex items-center gap-1 rounded-lg border border-border px-2.5 py-1 text-xs text-gray-300 transition-colors hover:border-primary hover:text-white"
          >
            {editing ? <X className="h-3.5 w-3.5" /> : <Pencil className="h-3.5 w-3.5" />}
            {editing ? 'Close' : 'Edit'}
          </button>
        </div>
      )}
    </div>
  )

  return (
    <div className="rounded-xl border border-border bg-surface p-4 sm:p-5">
      {header}

      {error && (
        <p className="mt-3 rounded-lg border border-warning/30 bg-warning/10 p-2.5 text-xs text-warning">
          {error}
        </p>
      )}

      {editing ? (
        <div className="mt-4 space-y-3">
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            <Field
              label="Account size"
              suffix="USD"
              value={form.account_size}
              step="100"
              onChange={(value) => setForm({ ...form, account_size: value })}
            />
            <Field
              label="Max daily loss"
              suffix="%"
              step="0.5"
              value={form.max_daily_loss_pct}
              onChange={(value) => setForm({ ...form, max_daily_loss_pct: value })}
            />
            <Field
              label="Max drawdown"
              suffix="%"
              step="0.5"
              value={form.max_drawdown_pct}
              onChange={(value) => setForm({ ...form, max_drawdown_pct: value })}
            />
            <Field
              label="Profit target"
              suffix="%"
              step="0.5"
              value={form.profit_target_pct}
              onChange={(value) => setForm({ ...form, profit_target_pct: value })}
            />
            <Field
              label="Minimum trading days"
              suffix="days"
              value={form.min_trading_days}
              onChange={(value) => setForm({ ...form, min_trading_days: value })}
            />
            <label className="flex items-end gap-2 pb-2">
              <input
                type="checkbox"
                checked={form.trailing_drawdown}
                onChange={(event) => setForm({ ...form, trailing_drawdown: event.target.checked })}
                className="h-4 w-4 rounded border-border bg-background"
              />
              <span className="text-xs text-gray-400">
                Trailing drawdown (measured from the peak balance)
              </span>
            </label>
          </div>

          <label className="block max-w-[220px]">
            <span className="text-xs text-gray-400">Evaluation started</span>
            <input
              type="date"
              value={form.started_on}
              onChange={(event) => setForm({ ...form, started_on: event.target.value })}
              className="mt-1 w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-white outline-none"
            />
          </label>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={save}
              disabled={saving}
              className="rounded-lg bg-primary px-3 py-2 text-sm font-medium text-white transition-colors hover:bg-primary-dark disabled:opacity-50"
            >
              {saving ? 'Saving…' : 'Save rules'}
            </button>
            {status && (
              <button
                type="button"
                onClick={() => {
                  setEditing(false)
                  if (payload?.rules) setForm({ ...DEFAULT_PROP_RULES, ...payload.rules })
                }}
                className="rounded-lg border border-border px-3 py-2 text-sm text-gray-300 transition-colors hover:text-white"
              >
                Cancel
              </button>
            )}
          </div>
        </div>
      ) : (
        status && (
          <div className="mt-4 space-y-3">
            {level !== 'ok' && (
              <p className="rounded-lg border border-danger/30 bg-danger/10 p-2.5 text-xs text-danger">
                {status.status === 'breach_daily'
                  ? 'Today’s loss has reached the daily limit — most firms require you to stop for the day.'
                  : status.status === 'breach_drawdown'
                    ? 'The drawdown limit has been reached. Check the firm’s rules before opening another trade.'
                    : 'You are within 20% of a rule limit. Position size and stop distance matter more than the next setup.'}
              </p>
            )}

            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              <Meter
                label="Daily loss"
                used={Math.max(0, -status.daily_pnl)}
                limit={status.daily_loss_limit}
                tone={level === 'breach' && status.status === 'breach_daily' ? 'breach' : level === 'warning' && status.status === 'warn_daily' ? 'warning' : 'ok'}
                detail={`${formatCurrency(status.daily_headroom)} left today · limit ${status.max_daily_loss_pct}%`}
              />
              <Meter
                label={status.trailing_drawdown ? 'Trailing drawdown' : 'Drawdown'}
                used={status.drawdown}
                limit={status.drawdown_limit}
                tone={status.status === 'breach_drawdown' ? 'breach' : status.status === 'warn_drawdown' ? 'warning' : 'ok'}
                detail={`${formatCurrency(status.drawdown_headroom)} left · peak ${formatCurrency(status.peak_equity)}`}
              />
              <Meter
                label="Profit target"
                used={Math.max(0, status.profit_progress)}
                limit={status.profit_target}
                tone="ok"
                detail={`${status.trading_days}/${status.min_trading_days} qualifying days`}
              />
            </div>

            <p className="text-[11px] text-gray-500">
              Evaluated from {formatCurrency(status.account_size)} of starting balance and your logged
              trades. A firm’s rules win any disagreement — check its dashboard before relying on this.
            </p>
          </div>
        )
      )}

      {!status && !editing && !payload?.rules && (
        <p className="mt-4 text-sm text-gray-500">Save your evaluation rules to see the monitor.</p>
      )}
    </div>
  )
}
