'use client'

import { useEffect, useState } from 'react'
import { Check, Image as ImageIcon, Loader2, Sparkles, StickyNote } from 'lucide-react'
import { authedFetch } from '@/lib/api'

/**
 * "Suggest rules from a trade": pick a journal entry, let the model read its
 * notes and screenshots, then fill the form with what it chose.
 *
 * The result is presented as a starting point with its reasoning attached, and
 * the parameters are the ones the server already clamped — this component never
 * invents or corrects a number, so what is shown is what will run.
 */

export interface AppliedSuggestion {
  strategyId: string
  params: Record<string, number>
  symbol?: string
  timeframe?: string
}

interface Candidate {
  id: string
  symbol: string
  timeframe: string | null
  strategy: string | null
  notes: string | null
  pnl: number | null
  closeTime: string | null
  images: number
  audio: number
}

interface Suggestion {
  strategyId: string
  name: string
  params: Record<string, number>
  reasoning: string
  confidence: 'low' | 'medium' | 'high'
  imagesRead: number
  disclaimer: string
}

function hasEvidence(trade: Candidate): boolean {
  return Boolean(trade.notes?.trim()) || trade.images > 0
}

function optionLabel(trade: Candidate): string {
  const note = trade.notes?.trim()
  const parts = [
    trade.symbol,
    trade.strategy?.trim() || 'untagged',
    note ? `${note.slice(0, 40)}${note.length > 40 ? '…' : ''}` : 'no note',
    trade.images > 0 ? `${trade.images} photo${trade.images === 1 ? '' : 's'}` : '',
  ].filter(Boolean)
  return parts.join(' · ')
}

export default function BacktestSuggest({
  onApply,
}: {
  onApply: (suggestion: AppliedSuggestion) => void
}) {
  const [open, setOpen] = useState(false)
  const [candidates, setCandidates] = useState<Candidate[] | null>(null)
  const [attempt, setAttempt] = useState(0)
  const [listLoading, setListLoading] = useState(false)
  const [listError, setListError] = useState('')
  const [selected, setSelected] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [result, setResult] = useState<Suggestion | null>(null)
  const [applied, setApplied] = useState(false)

  useEffect(() => {
    if (!open || candidates !== null) return
    let cancelled = false

    void (async () => {
      setListLoading(true)
      setListError('')
      try {
        const response = await authedFetch('/api/backtest/suggest')
        const data = (await response.json()) as { trades?: Candidate[]; error?: string }
        if (cancelled) return
        if (!response.ok) {
          setListError(data.error || 'Could not load your journal trades.')
          return
        }
        const rows = data.trades ?? []
        setCandidates(rows)
        // Preselect the most recent entry that actually carries evidence.
        setSelected((current) => current || rows.find(hasEvidence)?.id || rows[0]?.id || '')
      } catch {
        if (!cancelled) setListError('Could not load your journal trades.')
      } finally {
        if (!cancelled) setListLoading(false)
      }
    })()

    return () => {
      cancelled = true
    }
  }, [open, candidates, attempt])

  const suggest = async () => {
    if (!selected) return
    setBusy(true)
    setError('')
    setApplied(false)
    try {
      const response = await authedFetch('/api/backtest/suggest', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tradeId: selected }),
      })
      const data = (await response.json()) as { suggestion?: Suggestion; error?: string }
      if (!response.ok || !data.suggestion) {
        setResult(null)
        setError(data.error || 'Could not suggest rules for that trade.')
        return
      }
      setResult(data.suggestion)
    } catch {
      setResult(null)
      setError('Could not reach the server. Try again.')
    } finally {
      setBusy(false)
    }
  }

  const apply = () => {
    if (!result) return
    const trade = candidates?.find((item) => item.id === selected)
    onApply({
      strategyId: result.strategyId,
      params: result.params,
      ...(trade?.symbol ? { symbol: trade.symbol } : {}),
      ...(trade?.timeframe ? { timeframe: trade.timeframe } : {}),
    })
    setApplied(true)
  }

  const chosen = candidates?.find((item) => item.id === selected)
  const confidenceClass =
    result?.confidence === 'high'
      ? 'bg-success/20 text-success'
      : result?.confidence === 'medium'
        ? 'bg-primary/20 text-primary'
        : 'bg-warning/20 text-warning'

  return (
    <div className="mb-4 rounded-lg border border-primary/30 bg-primary/5 p-3">
      <div className="flex items-start gap-2">
        <Sparkles className="mt-0.5 h-4 w-4 flex-shrink-0 text-primary" />
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium text-white">Suggest rules from a trade</p>
          <p className="mt-0.5 text-xs leading-relaxed text-gray-400">
            Reads one journal entry — its notes and any chart screenshots — and picks the
            closest of the strategies below.
          </p>
        </div>
        {!open && (
          <button
            type="button"
            onClick={() => setOpen(true)}
            className="shrink-0 rounded-md border border-border bg-background px-2.5 py-1.5 text-xs text-gray-300 transition-colors hover:border-primary/50 hover:text-white"
          >
            Open
          </button>
        )}
      </div>

      {open && (
        <div className="mt-3 space-y-2">
          {listLoading && (
            <p className="flex items-center gap-2 text-xs text-gray-500">
              <Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading journal entries…
            </p>
          )}

          {listError && (
            <div className="flex items-center justify-between gap-2 rounded-md border border-warning/30 bg-warning/10 px-2.5 py-2">
              <p className="text-xs text-warning">{listError}</p>
              <button
                type="button"
                onClick={() => {
                  setCandidates(null)
                  setAttempt((value) => value + 1)
                }}
                className="text-xs text-white underline"
              >
                Retry
              </button>
            </div>
          )}

          {!listLoading && !listError && candidates?.length === 0 && (
            <p className="text-xs text-gray-500">
              No journal trades yet. Log a trade with a short note, then come back.
            </p>
          )}

          {candidates && candidates.length > 0 && (
            <>
              <label className="sr-only" htmlFor="suggest-trade">
                Journal trade
              </label>
              <select
                id="suggest-trade"
                value={selected}
                onChange={(event) => {
                  setSelected(event.target.value)
                  setResult(null)
                  setError('')
                  setApplied(false)
                }}
                className="w-full rounded-md border border-border bg-background px-2.5 py-2 text-xs text-white focus:border-primary focus:outline-none"
              >
                <option value="">Choose a journal entry…</option>
                {candidates.map((trade) => (
                  <option key={trade.id} value={trade.id}>
                    {optionLabel(trade)}
                    {hasEvidence(trade) ? '' : ' — no note or photo'}
                  </option>
                ))}
              </select>

              {chosen && !hasEvidence(chosen) && (
                <p className="text-xs text-warning">
                  This entry has no note and no screenshot. The model would be guessing from
                  the symbol alone — add one first.
                </p>
              )}

              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => void suggest()}
                  disabled={busy || !selected || (chosen ? !hasEvidence(chosen) : false)}
                  className="flex items-center gap-2 rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-white transition-colors hover:bg-primary-dark disabled:opacity-50"
                >
                  {busy ? (
                    <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  ) : (
                    <Sparkles className="h-3.5 w-3.5" />
                  )}
                  {busy ? 'Reading the entry…' : 'Suggest'}
                </button>
                {chosen && (
                  <span className="flex items-center gap-2 text-[11px] text-gray-500">
                    {chosen.notes?.trim() && (
                      <span className="flex items-center gap-1">
                        <StickyNote className="h-3 w-3" /> note
                      </span>
                    )}
                    {chosen.images > 0 && (
                      <span className="flex items-center gap-1">
                        <ImageIcon className="h-3 w-3" /> {chosen.images}
                      </span>
                    )}
                  </span>
                )}
              </div>
            </>
          )}

          {error && (
            <p className="rounded-md border border-warning/30 bg-warning/10 px-2.5 py-2 text-xs text-warning">
              {error}
            </p>
          )}

          {result && (
            <div className="rounded-md border border-border bg-background p-3">
              <div className="flex flex-wrap items-center gap-2">
                <p className="text-sm font-semibold text-white">{result.name}</p>
                <span className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${confidenceClass}`}>
                  {result.confidence} confidence
                </span>
                {result.imagesRead > 0 && (
                  <span className="text-[10px] text-gray-500">
                    read {result.imagesRead} screenshot{result.imagesRead === 1 ? '' : 's'}
                  </span>
                )}
              </div>
              <p className="mt-1.5 text-xs leading-relaxed text-gray-400">{result.reasoning}</p>
              <div className="mt-2 flex flex-wrap gap-1.5">
                {Object.entries(result.params).map(([key, value]) => (
                  <span
                    key={key}
                    className="rounded border border-border bg-surface px-1.5 py-0.5 font-mono text-[10px] text-gray-300"
                  >
                    {key} {value}
                  </span>
                ))}
              </div>
              <div className="mt-2.5 flex items-center gap-2">
                <button
                  type="button"
                  onClick={apply}
                  className="flex items-center gap-1.5 rounded-md border border-primary/50 bg-primary/15 px-2.5 py-1.5 text-xs font-medium text-white transition-colors hover:bg-primary/25"
                >
                  <Check className="h-3.5 w-3.5" />
                  {applied ? 'Applied' : 'Fill the form'}
                </button>
                {applied && <span className="text-[11px] text-gray-500">Review, then run it.</span>}
              </div>
              <p className="mt-2 text-[10px] leading-relaxed text-gray-500">{result.disclaimer}</p>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
