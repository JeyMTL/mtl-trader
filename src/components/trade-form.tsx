'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import {
  AlertCircle,
  ArrowLeft,
  ArrowRight,
  CheckCircle2,
  ChevronDown,
  Clock,
  Loader2,
  Save,
  TrendingDown,
  TrendingUp,
  Plus,
  Tag,
  X,
} from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { calculatePnL, cn, formatCurrency, formatDuration, getPointValue } from '@/lib/utils'
import { effectiveMaxTrades, UNLIMITED } from '@/lib/subscription'
import { mergeTags, suggestTags } from '@/lib/ai/autotag'
import { strategyColor } from '@/lib/strategy-colors'
import { JournalMedia } from '@/components/journal-media'
import {
  deleteJournalMedia,
  listJournalMedia,
  persistJournalMedia,
  type JournalAttachment,
  type PendingJournalAttachment,
} from '@/lib/journal-media'

type Mode = 'create' | 'edit'

type FormState = {
  symbol: string
  type: 'BUY' | 'SELL'
  entry_price: string
  exit_price: string
  lot_size: string
  stop_loss: string
  take_profit: string
  commission: string
  swap: string
  strategy: string
  notes: string
  tags: string[]
  open_time: string
  close_time: string
}

const EMPTY_FORM: FormState = {
  symbol: '',
  type: 'BUY',
  entry_price: '',
  exit_price: '',
  lot_size: '',
  stop_loss: '',
  take_profit: '',
  commission: '',
  swap: '',
  strategy: '',
  notes: '',
  tags: [],
  open_time: '',
  close_time: '',
}

const QUICK_SYMBOLS = ['EURUSD', 'GBPUSD', 'USDJPY', 'XAUUSD', 'NAS100']

function pipSize(symbol: string): number {
  const s = symbol.toUpperCase().replace(/[^A-Z0-9]/g, '')
  if (!s) return 0.0001
  if (s.endsWith('JPY')) return 0.01
  if (s.startsWith('XAU') || s.startsWith('GOLD') || s.startsWith('XAG') || s.startsWith('SILVER')) return 0.1
  if (getPointValue(s) === 1) return 1
  if (getPointValue(s) === 1000 && !s.endsWith('JPY')) return 0.01
  return 0.0001
}

/**
 * One strategy name, one row in analytics.
 *
 * The field is a free-text filter key, so leading, trailing and doubled spaces
 * are collapsed before the value is compared, suggested or saved — otherwise
 * "London  breakout" and "London breakout" split one model's statistics.
 */
function normalizeStrategy(value: string): string {
  return value.replace(/\s+/g, ' ').trim().slice(0, 60)
}

function labelForDateInput(value: string | null | undefined): string {
  if (!value) return ''
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  return new Date(date.getTime() - date.getTimezoneOffset() * 60_000).toISOString().slice(0, 16)
}

export function TradeForm({ mode, tradeId }: { mode: Mode; tradeId?: string }) {
  const router = useRouter()
  const [form, setForm] = useState<FormState>(EMPTY_FORM)
  const [loading, setLoading] = useState(mode === 'edit')
  const [saving, setSaving] = useState(false)
  const [showErrors, setShowErrors] = useState(false)
  const [error, setError] = useState('')
  const [notFound, setNotFound] = useState(false)
  const [quotaHit, setQuotaHit] = useState<number | null>(null)
  const [tagDraft, setTagDraft] = useState('')
  const [strategyLabels, setStrategyLabels] = useState<string[]>([])
  const [strategyOpen, setStrategyOpen] = useState(false)
  const [userId, setUserId] = useState('')
  const [attachments, setAttachments] = useState<JournalAttachment[]>([])
  const [pendingMedia, setPendingMedia] = useState<PendingJournalAttachment[]>([])
  // Set after the trade row exists, so a failed media insert can be retried
  // without duplicating the trade.
  const [createdTradeId, setCreatedTradeId] = useState<string | null>(null)
  // Files uploaded before the trade row exists are removed if the form is
  // abandoned, so a cancelled draft does not leave orphans in storage.
  const pendingMediaRef = useRef<PendingJournalAttachment[]>([])
  const savedRef = useRef(false)

  useEffect(() => {
    pendingMediaRef.current = pendingMedia
  }, [pendingMedia])

  // Strategy labels this trader has already used. Tapping one keeps the
  // analytics matrix from splitting a single model across spelling variants.
  // The RPC is optional: a database without the migration simply shows none.
  useEffect(() => {
    let active = true
    try {
      // `rpc` is typed as PromiseLike by the generated client, so it is wrapped
      // to get a `catch`: no suggestions is a valid state, not an error.
      Promise.resolve(
        supabase.rpc('strategy_labels', { p_limit: 20 }) as unknown as Promise<{ data: unknown }>
      )
        .then((result) => {
          if (!active || !Array.isArray(result?.data)) return
          const labels = result.data
            .map((row) => (row as { label?: unknown })?.label)
            .filter((label): label is string => typeof label === 'string' && label.trim().length > 0)
          setStrategyLabels(labels)
        })
        .catch(() => {
          // No suggestions is a valid state, not an error worth showing.
        })
    } catch {
      // A test double without `rpc` lands here.
    }
    return () => {
      active = false
    }
  }, [])

  const update = useCallback((field: keyof FormState, value: string) => {
    setForm(prev => ({ ...prev, [field]: value }))
  }, [])

  const addTag = useCallback((raw: string) => {
    const clean = raw.trim().toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '').slice(0, 24)
    if (!clean) return
    setForm(prev => ({ ...prev, tags: mergeTags(prev.tags, [clean]) }))
  }, [])

  const removeTag = useCallback((tag: string) => {
    setForm(prev => ({ ...prev, tags: prev.tags.filter(item => item !== tag) }))
  }, [])

  useEffect(() => {
    return () => {
      if (savedRef.current) return
      for (const item of pendingMediaRef.current) void deleteJournalMedia(item)
    }
  }, [])

  // Create mode needs the user id before a photo can be uploaded, so the media
  // section is live as soon as the page opens.
  useEffect(() => {
    if (mode !== 'create') return
    let cancelled = false
    supabase.auth.getUser().then(({ data }) => {
      if (!cancelled) setUserId(data.user?.id ?? '')
    })
    return () => { cancelled = true }
  }, [mode])

  useEffect(() => {
    if (mode !== 'edit' || !tradeId) return
    const id = tradeId
    let cancelled = false

    async function fetchTrade() {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        router.push('/auth/login')
        return
      }
      setUserId(user.id)
      const { data } = await supabase.from('trades').select('*').eq('id', id).eq('user_id', user.id).single()
      if (cancelled) return
      if (!data) {
        setNotFound(true)
        setLoading(false)
        return
      }
      try {
        const media = await listJournalMedia(id)
        if (!cancelled) setAttachments(media)
      } catch {
        // The journal entry still opens; media can be re-listed on reload.
      }
      setForm({
        symbol: data.symbol || '',
        type: data.type === 'SELL' ? 'SELL' : 'BUY',
        entry_price: data.entry_price?.toString() || '',
        exit_price: data.exit_price?.toString() || '',
        lot_size: data.lot_size?.toString() || '',
        stop_loss: data.stop_loss?.toString() || '',
        take_profit: data.take_profit?.toString() || '',
        commission: data.commission?.toString() || '',
        swap: data.swap?.toString() || '',
        strategy: data.strategy || '',
        notes: data.notes || '',
        tags: Array.isArray(data.tags) ? data.tags : [],
        open_time: labelForDateInput(data.open_time),
        close_time: labelForDateInput(data.close_time),
      })
      setLoading(false)
    }

    fetchTrade()
    return () => {
      cancelled = true
    }
  }, [mode, tradeId, router])

  const numbers = {
    entry: parseFloat(form.entry_price),
    exit: parseFloat(form.exit_price),
    lots: parseFloat(form.lot_size),
    stop: parseFloat(form.stop_loss),
    target: parseFloat(form.take_profit),
    commission: parseFloat(form.commission || '0'),
    swap: parseFloat(form.swap || '0'),
  }

  const openedAt = form.open_time ? new Date(form.open_time) : null
  const closedAt = form.close_time ? new Date(form.close_time) : null
  const windowInvalid = Boolean(openedAt && closedAt && closedAt.getTime() < openedAt.getTime())
  const windowMinutes = openedAt && closedAt && !windowInvalid
    ? Math.round((closedAt.getTime() - openedAt.getTime()) / 60_000)
    : null

  const hasPrices = !Number.isNaN(numbers.entry) && !Number.isNaN(numbers.exit) && !Number.isNaN(numbers.lots)

  const pnl = hasPrices
    ? calculatePnL({
        type: form.type,
        symbol: form.symbol || 'EURUSD',
        entry_price: numbers.entry,
        exit_price: numbers.exit,
        lot_size: numbers.lots,
        commission: Number.isNaN(numbers.commission) ? 0 : numbers.commission,
        swap: Number.isNaN(numbers.swap) ? 0 : numbers.swap,
      })
    : null

  const pips = hasPrices
    ? (form.type === 'BUY' ? numbers.exit - numbers.entry : numbers.entry - numbers.exit) / pipSize(form.symbol || 'EURUSD')
    : null

  const risk = !Number.isNaN(numbers.stop) && !Number.isNaN(numbers.entry) && !Number.isNaN(numbers.lots)
    ? Math.abs(numbers.entry - numbers.stop) * numbers.lots * getPointValue(form.symbol || 'EURUSD')
    : null

  const reward = !Number.isNaN(numbers.target) && !Number.isNaN(numbers.entry) && !Number.isNaN(numbers.lots)
    ? Math.abs(numbers.target - numbers.entry) * numbers.lots * getPointValue(form.symbol || 'EURUSD')
    : null

  const rMultiple = risk && risk > 0 && pnl !== null ? pnl / risk : null

  const suggestedTags = mergeTags(form.tags, suggestTags(form.notes)).filter(tag => !form.tags.includes(tag))
  const typedStrategy = normalizeStrategy(form.strategy)
  // Case-only drift is the most common split, and it is the one that is safe to
  // spot: a genuinely different model is a different label.
  const similarStrategy = typedStrategy && !strategyLabels.includes(typedStrategy)
    ? strategyLabels.find(label => label.toLowerCase() === typedStrategy.toLowerCase())
    : undefined
  // Typing filters the saved labels; focusing the empty field shows them all.
  const showStrategyMenu = strategyOpen && strategyLabels.length > 0
  const filteredStrategies = (typedStrategy
    ? strategyLabels.filter(label => label.toLowerCase().includes(typedStrategy.toLowerCase()))
    : strategyLabels
  ).slice(0, 8)

  const missing = {
    symbol: form.symbol.trim().length === 0,
    entry: Number.isNaN(numbers.entry) || numbers.entry <= 0,
    exit: Number.isNaN(numbers.exit) || numbers.exit <= 0,
    lots: Number.isNaN(numbers.lots) || numbers.lots <= 0,
  }
  const canSave = !missing.symbol && !missing.entry && !missing.exit && !missing.lots

  const handleSubmit = async () => {
    if (saving) return
    if (!canSave) {
      setShowErrors(true)
      return
    }
    if (windowInvalid) {
      setError('The exit time cannot be before the entry time.')
      return
    }
    setSaving(true)
    setError('')
    setQuotaHit(null)

    const payload = {
      symbol: form.symbol.trim().toUpperCase(),
      type: form.type,
      entry_price: numbers.entry,
      exit_price: numbers.exit,
      lot_size: numbers.lots,
      stop_loss: Number.isNaN(numbers.stop) ? null : numbers.stop,
      take_profit: Number.isNaN(numbers.target) ? null : numbers.target,
      pnl: pnl ?? 0,
      commission: Number.isNaN(numbers.commission) ? 0 : numbers.commission,
      swap: Number.isNaN(numbers.swap) ? 0 : numbers.swap,
      strategy: typedStrategy || null,
      notes: form.notes.trim() || null,
      tags: form.tags.length ? form.tags : null,
      open_time: form.open_time ? new Date(form.open_time).toISOString() : null,
      close_time: form.close_time ? new Date(form.close_time).toISOString() : null,
    }

    if (mode === 'edit' && tradeId) {
      // RLS already restricts this row, but the read path filters on the owner
      // explicitly and the write path should not depend on a single layer.
      if (!userId) {
        setError('Your session expired. Sign in again to save this trade.')
        setSaving(false)
        return
      }
      const { error: updateError } = await supabase
        .from('trades')
        .update(payload)
        .eq('id', tradeId)
        .eq('user_id', userId)
      if (updateError) {
        setError(updateError.message)
        setSaving(false)
        return
      }
      savedRef.current = true
      router.push('/dashboard/trades')
      return
    }

    const { data: { user } } = await supabase.auth.getUser()
    if (!user) {
      setError('Your session expired. Sign in again to save this trade.')
      setSaving(false)
      return
    }
    setUserId(user.id)

    // The server enforces this too; checking here keeps the failure friendly.
    const { data: userRow } = await supabase
      .from('users')
      .select('max_trades, subscription_tier, subscription_status, trial_ends_at, current_period_end')
      .eq('id', user.id)
      .single()
    const effectiveMax = effectiveMaxTrades(userRow ?? {})
    if (effectiveMax !== UNLIMITED) {
      // `month_trade_count` uses the trigger's own definition of "this month";
      // counting by `created_at` here used to disagree with the database.
      const { data: monthCount } = await supabase.rpc('month_trade_count')
      const used = typeof monthCount === 'number' ? monthCount : Number(monthCount ?? 0)
      if (used >= effectiveMax) {
        setQuotaHit(effectiveMax)
        setSaving(false)
        return
      }
    }

    // A retry after a media failure must not create the trade twice.
    let tradeIdForMedia = createdTradeId
    if (!tradeIdForMedia) {
      const { data: inserted, error: insertError } = await supabase
        .from('trades')
        .insert({ user_id: user.id, ...payload })
        .select('id')
        .single()
      if (insertError) {
        // The trigger speaks in SQL. A refused save must say what happened to the
        // journal, not just what the constraint was called.
        const message = insertError.message
        if (/Free trial ended/i.test(message)) {
          setError(
            'Your 30-day trial has ended. Nothing was deleted — your journal is still here and readable. Choose a plan to add new trades.'
          )
        } else if (/Monthly trade limit/i.test(message)) {
          setError(
            'You have reached this month’s trade limit. Your journal is untouched — upgrade for a higher limit, or log this trade next month.'
          )
        } else {
          setError(message)
        }
        setSaving(false)
        return
      }
      tradeIdForMedia = inserted?.id as string
      setCreatedTradeId(tradeIdForMedia)
    }

    if (pendingMedia.length > 0) {
      try {
        await persistJournalMedia({ userId: user.id, tradeId: tradeIdForMedia, pending: pendingMedia })
      } catch (mediaError) {
        setError(
          'The trade was saved, but its photos or voice notes could not be attached: ' +
          (mediaError instanceof Error ? mediaError.message : 'unknown error') +
          ' Press “Log trade” again to retry the media only.'
        )
        setSaving(false)
        return
      }
    }

    savedRef.current = true
    router.push('/dashboard/trades')
  }

  const fieldClass = (invalid: boolean) =>
    cn('input num', invalid && showErrors && 'border-danger focus:border-danger')

  if (loading) {
    return (
      <div className="mx-auto max-w-5xl space-y-4">
        <div className="skeleton h-8 w-40" />
        <div className="skeleton h-72 w-full" />
      </div>
    )
  }

  if (notFound) {
    return (
      <div className="mx-auto max-w-md panel p-6 text-center">
        <AlertCircle className="mx-auto h-6 w-6 text-primary" />
        <h1 className="mt-3 text-lg font-semibold text-white">Trade not found</h1>
        <p className="mt-1 text-sm text-gray-400">It may have been deleted, or it belongs to another account.</p>
        <Link href="/dashboard/trades" className="btn btn-secondary mt-5">
          <ArrowLeft className="h-4 w-4" />
          Back to the trade log
        </Link>
      </div>
    )
  }

  const isEdit = mode === 'edit'
  const positive = (pnl ?? 0) >= 0

  return (
    <div className="mx-auto max-w-5xl">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <Link
            href="/dashboard/trades"
            className="mb-3 inline-flex items-center gap-1.5 text-xs font-medium text-gray-500 transition-colors hover:text-white"
          >
            <ArrowLeft className="h-3.5 w-3.5" />
            Trade log
          </Link>
          <p className="eyebrow">{isEdit ? 'Amend record' : 'New record'}</p>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight text-white">
            {isEdit ? 'Edit trade' : 'Log a trade'}
          </h1>
          <p className="mt-1 text-sm text-gray-400">
            {isEdit
              ? 'Corrections recalculate P&L and every downstream statistic.'
              : 'Prices, size and costs are enough — the ticket and R-multiple are computed as you type.'}
          </p>
        </div>
        <span className="chip">
          <span className={cn('h-1.5 w-1.5 rounded-full', positive ? 'bg-success' : 'bg-danger')} />
          {isEdit ? 'Editing a closed position' : 'Closed position'}
        </span>
      </div>

      {error && (
        <div className="mt-5 flex items-start gap-3 rounded-xl border border-danger/40 bg-danger/10 px-4 py-3 text-sm text-danger">
          <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
          <p className="flex-1">{error}</p>
          <button onClick={() => setError('')} className="text-xs font-medium text-danger/80 hover:text-danger">
            Dismiss
          </button>
        </div>
      )}

      {quotaHit !== null && (
        <div className="mt-5 flex flex-col gap-2 rounded-xl border border-primary/40 bg-primary/10 px-4 py-3 text-sm sm:flex-row sm:items-center sm:justify-between">
          <p className="text-primary-light">
            {quotaHit === 0
              ? 'Your trial has ended. Nothing was deleted — the journal is still here and readable — but new trades need a plan.'
              : `Monthly limit reached — this plan logs ${quotaHit} trades per month.`}
          </p>
          <Link href="/pricing" className="btn btn-primary self-start px-3 py-1.5 text-xs">
            Compare plans
            <ArrowRight className="h-3.5 w-3.5" />
          </Link>
        </div>
      )}

      <div className="mt-6 grid gap-5 lg:grid-cols-[minmax(0,1fr)_300px]">
        <form
          onSubmit={(event) => {
            event.preventDefault()
            handleSubmit()
          }}
          className="space-y-4"
        >
          <section className="panel">
            <div className="panel-head">
              <div>
                <h2 className="text-sm font-semibold text-white">Instrument</h2>
                <p className="text-xs text-gray-500">What you traded and which way</p>
              </div>
              <span className="eyebrow">01</span>
            </div>
            <div className="space-y-4 p-4">
              <div className="grid gap-4 sm:grid-cols-[1fr_auto]">
                <div>
                  <label htmlFor="symbol" className="field-label">Symbol</label>
                  <input
                    id="symbol"
                    type="text"
                    autoCapitalize="characters"
                    spellCheck={false}
                    value={form.symbol}
                    onChange={(event) => update('symbol', event.target.value.toUpperCase())}
                    placeholder="EURUSD"
                    className={cn(fieldClass(missing.symbol), 'font-sans font-medium uppercase tracking-wide')}
                  />
                  {showErrors && missing.symbol && <p className="mt-1.5 text-xs text-danger">A symbol is required.</p>}
                  <div className="mt-2 flex flex-wrap gap-1.5">
                    {QUICK_SYMBOLS.map((symbol) => (
                      <button
                        key={symbol}
                        type="button"
                        onClick={() => update('symbol', symbol)}
                        className={cn('chip', form.symbol === symbol && 'chip-active')}
                      >
                        {symbol}
                      </button>
                    ))}
                  </div>
                </div>

                <div>
                  <span className="field-label">Direction</span>
                  <div className="flex gap-2">
                    <button
                      type="button"
                      onClick={() => update('type', 'BUY')}
                      aria-pressed={form.type === 'BUY'}
                      className={cn(
                        'btn flex-1 border px-4',
                        form.type === 'BUY'
                          ? 'border-success/50 bg-success/15 text-success'
                          : 'border-border bg-transparent text-gray-400 hover:text-white'
                      )}
                    >
                      <TrendingUp className="h-4 w-4" />
                      Buy
                    </button>
                    <button
                      type="button"
                      onClick={() => update('type', 'SELL')}
                      aria-pressed={form.type === 'SELL'}
                      className={cn(
                        'btn flex-1 border px-4',
                        form.type === 'SELL'
                          ? 'border-danger/50 bg-danger/15 text-danger'
                          : 'border-border bg-transparent text-gray-400 hover:text-white'
                      )}
                    >
                      <TrendingDown className="h-4 w-4" />
                      Sell
                    </button>
                  </div>
                  <p className="mt-2 text-xs text-gray-500">Signed convention: commission and swap as charged.</p>
                </div>
              </div>
            </div>
          </section>

          <section className="panel">
            <div className="panel-head">
              <div>
                <h2 className="text-sm font-semibold text-white">Execution</h2>
                <p className="text-xs text-gray-500">Entry, exit and size</p>
              </div>
              <span className="eyebrow">02</span>
            </div>
            <div className="grid gap-4 p-4 sm:grid-cols-3">
              <div>
                <label htmlFor="entry" className="field-label">Entry price</label>
                <input
                  id="entry"
                  type="number"
                  inputMode="decimal"
                  step="any"
                  value={form.entry_price}
                  onChange={(event) => update('entry_price', event.target.value)}
                  placeholder="1.08500"
                  className={fieldClass(missing.entry)}
                />
              </div>
              <div>
                <label htmlFor="exit" className="field-label">Exit price</label>
                <input
                  id="exit"
                  type="number"
                  inputMode="decimal"
                  step="any"
                  value={form.exit_price}
                  onChange={(event) => update('exit_price', event.target.value)}
                  placeholder="1.08800"
                  className={fieldClass(missing.exit)}
                />
              </div>
              <div>
                <label htmlFor="lots" className="field-label">Size (lots)</label>
                <input
                  id="lots"
                  type="number"
                  inputMode="decimal"
                  step="any"
                  value={form.lot_size}
                  onChange={(event) => update('lot_size', event.target.value)}
                  placeholder="0.10"
                  className={fieldClass(missing.lots)}
                />
              </div>
              {showErrors && (missing.entry || missing.exit || missing.lots) && (
                <p className="text-xs text-danger sm:col-span-3">Entry, exit and size must all be greater than zero.</p>
              )}
              <div>
                <label htmlFor="stop" className="field-label">Stop loss</label>
                <input
                  id="stop"
                  type="number"
                  inputMode="decimal"
                  step="any"
                  value={form.stop_loss}
                  onChange={(event) => update('stop_loss', event.target.value)}
                  placeholder="Optional"
                  className="input num"
                />
              </div>
              <div>
                <label htmlFor="target" className="field-label">Take profit</label>
                <input
                  id="target"
                  type="number"
                  inputMode="decimal"
                  step="any"
                  value={form.take_profit}
                  onChange={(event) => update('take_profit', event.target.value)}
                  placeholder="Optional"
                  className="input num"
                />
              </div>
              <div>
                <label htmlFor="strategy" className="field-label">Strategy</label>
                <div className="relative">
                  <input
                    id="strategy"
                    type="text"
                    value={form.strategy}
                    onChange={(event) => {
                      update('strategy', event.target.value)
                      setStrategyOpen(true)
                    }}
                    onFocus={() => setStrategyOpen(true)}
                    onBlur={() => {
                      update('strategy', normalizeStrategy(form.strategy))
                      // Delayed so a click on an option lands before the list closes.
                      window.setTimeout(() => setStrategyOpen(false), 120)
                    }}
                    onKeyDown={(event) => {
                      if (event.key === 'Escape') setStrategyOpen(false)
                    }}
                    maxLength={60}
                    autoCapitalize="words"
                    autoComplete="off"
                    spellCheck
                    placeholder="e.g. London breakout"
                    role="combobox"
                    aria-expanded={showStrategyMenu}
                    aria-controls="strategy-options"
                    className="input pr-9"
                  />
                  {strategyLabels.length > 0 && (
                    <button
                      type="button"
                      aria-label="Show saved strategies"
                      onClick={() => setStrategyOpen(open => !open)}
                      className="absolute right-1.5 top-1/2 -translate-y-1/2 rounded p-1 text-gray-400 transition-colors hover:text-white"
                    >
                      <ChevronDown
                        className={cn('h-4 w-4 transition-transform', showStrategyMenu && 'rotate-180')}
                      />
                    </button>
                  )}
                  {showStrategyMenu && (
                    <ul
                      id="strategy-options"
                      role="listbox"
                      className="absolute z-30 mt-1 max-h-56 w-full overflow-auto rounded-lg border border-border bg-surface p-1 shadow-xl"
                    >
                      {filteredStrategies.length === 0 ? (
                        <li className="px-3 py-2 text-xs text-gray-500">
                          No saved strategy matches. Saving this one adds it to the list.
                        </li>
                      ) : (
                        filteredStrategies.map((label) => (
                          <li key={label} role="option" aria-selected={typedStrategy === label}>
                            <button
                              type="button"
                              // mousedown rather than click: the input must not blur first.
                              onMouseDown={(event) => event.preventDefault()}
                              onClick={() => {
                                update('strategy', label)
                                setStrategyOpen(false)
                              }}
                              className="flex w-full items-center gap-2 rounded-md px-2.5 py-2 text-left text-sm text-gray-300 transition-colors hover:bg-surface-light hover:text-white"
                            >
                              <span
                                aria-hidden
                                className="h-2 w-2 shrink-0 rounded-full"
                                style={{ backgroundColor: strategyColor(label) }}
                              />
                              <span className="flex-1 truncate">{label}</span>
                              {typedStrategy === label && (
                                <CheckCircle2 className="h-3.5 w-3.5 shrink-0 text-primary" />
                              )}
                            </button>
                          </li>
                        ))
                      )}
                    </ul>
                  )}
                </div>
                {similarStrategy && (
                  <p className="mt-1.5 text-xs text-warning">
                    You already use “{similarStrategy}”. Pick the existing spelling so its statistics stay together.
                  </p>
                )}
              </div>
            </div>
          </section>

          <section className="panel">
            <div className="panel-head">
              <div>
                <h2 className="text-sm font-semibold text-white">Costs & timing</h2>
                <p className="text-xs text-gray-500">Broker charges and when the position lived</p>
              </div>
              <span className="eyebrow">03</span>
            </div>
            <div className="grid gap-4 p-4 sm:grid-cols-2">
              <div>
                <label htmlFor="commission" className="field-label">Commission</label>
                <input
                  id="commission"
                  type="number"
                  inputMode="decimal"
                  step="any"
                  value={form.commission}
                  onChange={(event) => update('commission', event.target.value)}
                  placeholder="-2.50"
                  className="input num"
                />
                <p className="mt-1.5 text-xs text-gray-500">Negative is a cost paid.</p>
              </div>
              <div>
                <label htmlFor="swap" className="field-label">Swap</label>
                <input
                  id="swap"
                  type="number"
                  inputMode="decimal"
                  step="any"
                  value={form.swap}
                  onChange={(event) => update('swap', event.target.value)}
                  placeholder="-0.74"
                  className="input num"
                />
                <p className="mt-1.5 text-xs text-gray-500">Overnight financing, signed.</p>
              </div>
              <div>
                <label htmlFor="open_time" className="field-label">Opened</label>
                <input
                  id="open_time"
                  type="datetime-local"
                  value={form.open_time}
                  onChange={(event) => update('open_time', event.target.value)}
                  className="input num"
                />
              </div>
              <div>
                <label htmlFor="close_time" className="field-label">Closed</label>
                <input
                  id="close_time"
                  type="datetime-local"
                  value={form.close_time}
                  onChange={(event) => update('close_time', event.target.value)}
                  className={cn('input num', windowInvalid && 'border-danger focus:border-danger')}
                />
              </div>
              <div className="rounded-lg border border-border bg-surface-light/60 px-3 py-2 text-xs sm:col-span-2">
                <div className="flex items-center justify-between gap-3">
                  <span className="flex items-center gap-1.5 text-gray-400">
                    <Clock className="h-3.5 w-3.5" />
                    Time in market
                  </span>
                  <span className={cn('num font-semibold', windowInvalid ? 'text-danger' : 'text-white')}>
                    {windowInvalid
                      ? 'Exit before entry'
                      : windowMinutes !== null
                        ? formatDuration(windowMinutes)
                        : 'Set both times'}
                  </span>
                </div>
                <p className="mt-1 text-[11px] text-gray-500">
                  The journal uses this window for the hour and session report.
                </p>
              </div>
            </div>
          </section>

          <section className="panel">
            <div className="panel-head">
              <div>
                <h2 className="text-sm font-semibold text-white">Journal</h2>
                <p className="text-xs text-gray-500">The part the AI review reads first</p>
              </div>
              <span className="eyebrow">04</span>
            </div>
            <div className="p-4">
              <label htmlFor="notes" className="field-label">What was the setup, and what did you do?</label>
              <textarea
                id="notes"
                value={form.notes}
                onChange={(event) => update('notes', event.target.value)}
                placeholder="One or two lines: the idea, the trigger, how you managed it."
                rows={4}
                className="input resize-none"
              />

              <div className="mt-5 border-t border-border pt-4">
                <JournalMedia
                  userId={userId}
                  tradeId={mode === 'edit' ? tradeId : undefined}
                  pending={pendingMedia}
                  onPendingChange={setPendingMedia}
                  existing={attachments}
                  onExistingChange={setAttachments}
                  disabled={saving}
                />
              </div>

              <div className="mt-4">
                <label htmlFor="tags" className="field-label">Tags</label>

                {form.tags.length > 0 ? (
                  <div className="mb-2 flex flex-wrap gap-1.5">
                    {form.tags.map(tag => (
                      <span key={tag} className="chip chip-active">
                        {tag}
                        <button
                          type="button"
                          onClick={() => removeTag(tag)}
                          aria-label={`Remove ${tag} tag`}
                          className="-mr-1 rounded p-0.5 hover:text-white"
                        >
                          <X className="h-3 w-3" />
                        </button>
                      </span>
                    ))}
                  </div>
                ) : (
                  <div className="mb-2 flex items-center gap-2 rounded-lg border border-dashed border-border px-3 py-2 text-xs text-gray-500">
                    <Tag className="h-3.5 w-3.5" />
                    No tags yet — they drive the edge report.
                  </div>
                )}

                <div className="flex gap-2">
                  <input
                    id="tags"
                    type="text"
                    value={tagDraft}
                    onChange={(event) => setTagDraft(event.target.value)}
                    onKeyDown={(event) => {
                      if (event.key === 'Enter' || event.key === ',') {
                        event.preventDefault()
                        addTag(tagDraft)
                        setTagDraft('')
                      }
                    }}
                    onBlur={() => {
                      if (tagDraft.trim()) {
                        addTag(tagDraft)
                        setTagDraft('')
                      }
                    }}
                    placeholder="Add a tag and press Enter"
                    className="input"
                    maxLength={24}
                  />
                  <button
                    type="button"
                    onClick={() => {
                      addTag(tagDraft)
                      setTagDraft('')
                    }}
                    className="btn btn-secondary px-3"
                    aria-label="Add tag"
                  >
                    <Plus className="h-4 w-4" />
                  </button>
                </div>

                {suggestedTags.length > 0 && (
                  <div className="mt-3">
                    <p className="eyebrow">Suggested from your note</p>
                    <div className="mt-1.5 flex flex-wrap gap-1.5">
                      {suggestedTags.map(tag => (
                        <button
                          key={tag}
                          type="button"
                          onClick={() => addTag(tag)}
                          className="chip border-dashed hover:border-primary/50 hover:text-white"
                        >
                          <Plus className="h-3 w-3" />
                          {tag}
                        </button>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            </div>
          </section>

          <div className="mobile-actionbar sticky z-10 flex items-center gap-2 rounded-xl border border-border bg-background/95 p-2 backdrop-blur lg:static lg:border-0 lg:bg-transparent lg:p-0 lg:backdrop-blur-none">
            <button
              type="submit"
              disabled={saving}
              className="btn btn-primary flex-1 lg:flex-none lg:px-6"
            >
              {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
              {saving ? 'Saving…' : isEdit ? 'Save changes' : 'Log trade'}
            </button>
            <Link href="/dashboard/trades" className="btn btn-secondary flex-1 lg:flex-none lg:px-6">
              Cancel
            </Link>
          </div>
        </form>

        <aside className="lg:sticky lg:top-24 lg:self-start">
          <div className="panel overflow-hidden">
            <div className="border-b border-border px-4 py-3">
              <p className="eyebrow">Live ticket</p>
              <p className="mt-1 font-sans text-sm font-medium text-white">
                {form.symbol || 'Instrument'}
                <span className={cn('ml-2 badge', form.type === 'BUY' ? 'badge-buy' : 'badge-sell')}>
                  {form.type}
                </span>
              </p>
            </div>

            <div className="p-4">
              <p className="metric-label">Estimated P&L</p>
              <p className={cn('num mt-1 text-3xl font-semibold tracking-tight', pnl === null ? 'text-gray-500' : positive ? 'text-success' : 'text-danger')}>
                {pnl === null ? '—' : `${positive ? '+' : ''}${formatCurrency(pnl)}`}
              </p>
              <p className="mt-1 text-xs text-gray-500">
                {pips === null ? 'Enter entry, exit and size' : `${pips >= 0 ? '+' : ''}${pips.toFixed(1)} pips · ${form.lot_size || '0'} lots`}
              </p>

              <div className="rule my-4" />

              <dl className="space-y-2.5 text-sm">
                <div className="flex items-baseline justify-between gap-3">
                  <dt className="text-gray-500">Risk</dt>
                  <dd className={cn('num', risk === null ? 'text-gray-600' : 'text-danger')}>
                    {risk === null ? '—' : formatCurrency(risk)}
                  </dd>
                </div>
                <div className="flex items-baseline justify-between gap-3">
                  <dt className="text-gray-500">Target</dt>
                  <dd className={cn('num', reward === null ? 'text-gray-600' : 'text-success')}>
                    {reward === null ? '—' : formatCurrency(reward)}
                  </dd>
                </div>
                <div className="flex items-baseline justify-between gap-3">
                  <dt className="text-gray-500">Realised R</dt>
                  <dd className="num text-white">
                    {rMultiple === null ? '—' : `${rMultiple >= 0 ? '+' : ''}${rMultiple.toFixed(2)}R`}
                  </dd>
                </div>
                <div className="flex items-baseline justify-between gap-3">
                  <dt className="text-gray-500">Costs</dt>
                  <dd className="num text-gray-300">
                    {formatCurrency((Number.isNaN(numbers.commission) ? 0 : numbers.commission) + (Number.isNaN(numbers.swap) ? 0 : numbers.swap))}
                  </dd>
                </div>
                <div className="flex items-baseline justify-between gap-3">
                  <dt className="text-gray-500">Window</dt>
                  <dd className={cn('num', windowInvalid ? 'text-danger' : 'text-gray-300')}>
                    {windowMinutes !== null ? formatDuration(windowMinutes) : '—'}
                  </dd>
                </div>
              </dl>
            </div>

            <div className="flex items-start gap-2 border-t border-border bg-surface-light/60 px-4 py-3 text-xs leading-relaxed text-gray-500">
              <CheckCircle2 className="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary" />
              P&L = price movement × lots × contract size, plus commission and swap.
            </div>
          </div>
        </aside>
      </div>
    </div>
  )
}
