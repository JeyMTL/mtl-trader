'use client'

import { useEffect, useState } from 'react'
import { ArrowUpRight, Gauge, Loader2, Target } from 'lucide-react'

/**
 * Exit capture: what share of each trade's move the trader kept.
 *
 * The numbers come from `/api/analytics/excursion`, which measures MFE/MAE from
 * the candle feed with the maths in `src/lib/excursion.ts`. This card only
 * formats them — and it is careful to say when the sample is partial, because a
 * capture ratio computed on six trades is a hint, not a verdict.
 */

interface Bucket {
  key: string
  measured: number
  captureMedian: number | null
  giveBackMedian: number | null
  mfeMedian: number
  maeMedian: number
}

interface ExcursionResponse {
  days: number
  persisted: boolean
  coverage: {
    closed: number
    measured: number
    pending: number
    unsupportedSymbols: string[]
  }
  summary: {
    measured: number
    captureMedian: number | null
    giveBackMedian: number | null
    mfeMedian: number
    maeMedian: number
    efficiencyMedian: number | null
    bySetup: Bucket[]
    bySymbol: Bucket[]
  }
}

const RANGES = [
  { days: 30, label: '30D' },
  { days: 90, label: '90D' },
  { days: 365, label: '1Y' },
] as const

function pct(value: number | null): string {
  return value === null ? '—' : `${Math.round(value * 100)}%`
}

/** Prices are shown at four significant decimals: MFE is a distance, not money. */
function price(value: number): string {
  if (!Number.isFinite(value)) return '—'
  if (value === 0) return '0'
  if (Math.abs(value) >= 100) return value.toFixed(1)
  if (Math.abs(value) >= 1) return value.toFixed(3)
  return value.toFixed(5)
}

export function ExcursionCard() {
  const [days, setDays] = useState<number>(90)
  const [data, setData] = useState<ExcursionResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  // The range buttons start the next read. Setting the flag from the effect
  // instead painted one frame of the previous range's numbers under the new
  // heading, which is why the hook rule flags it.
  const chooseRange = (next: number) => {
    if (next === days) return
    setDays(next)
    setLoading(true)
    setError('')
  }

  useEffect(() => {
    let cancelled = false
    void (async () => {
      try {
        const res = await fetch(`/api/analytics/excursion?days=${days}`, {
          headers: { 'Cache-Control': 'no-store' },
        })
        const payload = (await res.json()) as ExcursionResponse & { error?: string }
        if (cancelled) return
        if (!res.ok) {
          setError(payload.error || 'Could not measure your trades.')
          setData(null)
        } else {
          setData(payload)
        }
      } catch {
        if (!cancelled) setError('Could not connect. Try again in a moment.')
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [days])

  const summary = data?.summary
  const measured = summary?.measured ?? 0
  const capture = summary?.captureMedian ?? null
  const giveBack = summary?.giveBackMedian ?? null

  return (
    <div className="rounded-xl border border-border bg-surface p-4 sm:p-6">
      <div className="flex flex-wrap items-start gap-3">
        <div className="flex min-w-0 items-center gap-2">
          <Target className="h-5 w-5 text-primary" />
          <h2 className="text-lg font-semibold text-white">Exit capture</h2>
        </div>
        <div className="ml-auto flex items-center gap-1 rounded-lg border border-border bg-background p-0.5">
          {RANGES.map((range) => (
            <button
              key={range.days}
              type="button"
              onClick={() => chooseRange(range.days)}
              aria-pressed={days === range.days}
              className={`min-h-8 rounded-md px-2.5 text-[11px] font-semibold ${
                days === range.days
                  ? 'bg-surface-light text-white'
                  : 'text-gray-500 hover:text-gray-300'
              }`}
            >
              {range.label}
            </button>
          ))}
        </div>
      </div>

      <p className="mt-1 text-sm text-gray-400">
        How much of the move each trade actually kept, measured bar by bar between your entry and
        your exit. Maximum favourable excursion (MFE) is the best price while you were in; maximum
        adverse excursion (MAE) is the worst.
      </p>

      {loading && (
        <div className="mt-5 flex items-center gap-2 text-sm text-gray-500">
          <Loader2 className="h-4 w-4 animate-spin" />
          Measuring trades against the candle feed…
        </div>
      )}

      {!loading && error && (
        <p className="mt-5 rounded-lg border border-warning/30 bg-warning/10 px-3 py-2 text-xs text-warning">
          {error}
        </p>
      )}

      {!loading && !error && measured === 0 && (
        <p className="mt-5 text-sm text-gray-500">
          No trade in the last {days} days could be measured yet. Closed trades are measured as
          soon as their instrument is on the candle feed — pairs, metals and indices are; a
          broker-only symbol such as a synthetic index cannot be.
        </p>
      )}

      {!loading && !error && measured > 0 && summary && (
        <>
          <div className="mt-5 grid gap-3 sm:grid-cols-3">
            <div className="rounded-lg border border-border bg-background p-3">
              <div className="flex items-center gap-1.5 text-[10px] uppercase tracking-wide text-gray-500">
                <ArrowUpRight className="h-3 w-3" /> Kept of the move
              </div>
              <div
                className={`mt-1 text-2xl font-bold tabular-nums ${
                  (capture ?? 0) >= 0.5
                    ? 'text-success'
                    : (capture ?? 0) >= 0
                      ? 'text-warning'
                      : 'text-danger'
                }`}
              >
                {pct(capture)}
              </div>
              <div className="text-[11px] text-gray-500">median across measured trades</div>
            </div>

            <div className="rounded-lg border border-border bg-background p-3">
              <div className="flex items-center gap-1.5 text-[10px] uppercase tracking-wide text-gray-500">
                <Gauge className="h-3 w-3" /> Given back
              </div>
              <div className="mt-1 text-2xl font-bold tabular-nums text-white">{pct(giveBack)}</div>
              <div className="text-[11px] text-gray-500">of the best price reached</div>
            </div>

            <div className="rounded-lg border border-border bg-background p-3">
              <div className="text-[10px] uppercase tracking-wide text-gray-500">MFE / MAE</div>
              <div className="mt-1 text-2xl font-bold tabular-nums text-white">
                {price(summary.mfeMedian)}
                <span className="mx-1 text-sm font-normal text-gray-500">/</span>
                {price(summary.maeMedian)}
              </div>
              <div className="text-[11px] text-gray-500">
                median favourable vs adverse move
              </div>
            </div>
          </div>

          {summary.bySetup.length > 0 && (
            <div className="mt-5">
              <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-500">
                By setup
              </h3>
              <div className="mt-2 space-y-2">
                {summary.bySetup.slice(0, 5).map((bucket) => (
                  <div key={bucket.key} className="flex items-center gap-3">
                    <span className="w-32 truncate text-xs text-gray-300" title={bucket.key}>
                      {bucket.key}
                    </span>
                    <div className="h-2 flex-1 overflow-hidden rounded-full bg-background">
                      <div
                        className={`h-full rounded-full ${
                          (bucket.captureMedian ?? 0) >= 0.5 ? 'bg-success' : 'bg-warning'
                        }`}
                        style={{
                          width: `${Math.min(100, Math.max(0, (bucket.captureMedian ?? 0) * 100))}%`,
                        }}
                      />
                    </div>
                    <span className="w-12 text-right text-xs tabular-nums text-gray-400">
                      {pct(bucket.captureMedian)}
                    </span>
                    <span className="w-14 text-right text-[10px] tabular-nums text-gray-600">
                      {bucket.measured} tr
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}

          <p className="mt-4 text-[11px] leading-relaxed text-gray-500">
            Measured on {data.coverage.measured} of {data.coverage.closed} closed trades in the
            last {days} days
            {data.coverage.pending > 0
              ? `, ${data.coverage.pending} still to measure — reopen this card in a minute`
              : ''}
            .
            {data.coverage.unsupportedSymbols.length > 0
              ? ` Not on the candle feed: ${data.coverage.unsupportedSymbols.join(', ')}.`
              : ''}
            {!data.persisted
              ? ' Measurements are not being saved yet, so this runs again on each visit.'
              : ''}
          </p>
        </>
      )}
    </div>
  )
}
