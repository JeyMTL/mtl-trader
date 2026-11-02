'use client'

import { useCallback, useEffect, useState } from 'react'
import { BookOpen, Image as ImageIcon, Loader2 } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import {
  summarizeJournalTrades,
  type JournalSummary,
  type JournalTrade,
} from '@/lib/backtest/journal'

/**
 * Your real trades on the same symbol and window as the run.
 *
 * Kept visually separate from the simulated numbers and labelled as such: a
 * journal result is what you actually did, a backtest is what the rules would
 * have done. Putting them side by side is useful; blurring them would not be.
 */
export default function BacktestJournal({
  symbol,
  from,
  to,
}: {
  symbol: string
  from: number
  to: number
}) {
  const [summary, setSummary] = useState<JournalSummary | null>(null)
  const [loading, setLoading] = useState(true)
  const [failed, setFailed] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) {
        setFailed(true)
        return
      }

      const { data, error } = await supabase
        .from('trades')
        .select('strategy, pnl, close_time')
        .eq('user_id', user.id)
        .eq('symbol', symbol)
        .not('close_time', 'is', null)
        .gte('close_time', new Date(from).toISOString())
        .lte('close_time', new Date(to).toISOString())

      if (error) {
        setFailed(true)
        return
      }
      setSummary(summarizeJournalTrades((data ?? []) as JournalTrade[]))
    } catch {
      setFailed(true)
    } finally {
      setLoading(false)
    }
  }, [symbol, from, to])

  useEffect(() => {
    const timer = setTimeout(() => {
      void load()
    }, 0)
    return () => clearTimeout(timer)
  }, [load])

  return (
    <div className="rounded-xl border border-border bg-surface p-5">
      <div className="mb-3 flex items-center gap-2">
        <BookOpen className="h-4 w-4 text-gray-400" />
        <h2 className="text-sm font-semibold text-white">Your journal, same window</h2>
        {loading && <Loader2 className="h-3.5 w-3.5 animate-spin text-gray-500" />}
      </div>

      {failed ? (
        <p className="text-xs text-gray-500">Could not read your journal just now.</p>
      ) : summary === null ? (
        <p className="text-xs text-gray-500">Loading your trades for {symbol}…</p>
      ) : summary.trades === 0 ? (
        <p className="text-xs leading-relaxed text-gray-500">
          No closed {symbol} trades in this window. These are real fills, so they only
          appear if you traded the same period the file covers.
        </p>
      ) : (
        <>
          <div className="grid grid-cols-3 gap-2">
            <div className="rounded-lg border border-border bg-background p-3">
              <p className="text-[11px] uppercase tracking-wide text-gray-500">Closed trades</p>
              <p className="mt-1 font-mono text-sm font-semibold text-white">{summary.trades}</p>
            </div>
            <div className="rounded-lg border border-border bg-background p-3">
              <p className="text-[11px] uppercase tracking-wide text-gray-500">Net</p>
              <p
                className={`mt-1 font-mono text-sm font-semibold ${
                  summary.netPnl >= 0 ? 'text-green-400' : 'text-red-400'
                }`}
              >
                {summary.netPnl >= 0 ? '+' : '−'}$
                {Math.abs(summary.netPnl).toFixed(2)}
              </p>
            </div>
            <div className="rounded-lg border border-border bg-background p-3">
              <p className="text-[11px] uppercase tracking-wide text-gray-500">Win rate</p>
              <p className="mt-1 font-mono text-sm font-semibold text-white">
                {summary.winRate.toFixed(0)}%
              </p>
            </div>
          </div>

          {summary.strategies.length > 0 && (
            <ul className="mt-3 space-y-1">
              {summary.strategies.slice(0, 5).map((entry) => (
                <li key={entry.name} className="flex items-center justify-between text-xs">
                  <span className="truncate text-gray-400">
                    {entry.name} <span className="text-gray-600">· {entry.trades}</span>
                  </span>
                  <span
                    className={`font-mono ${
                      entry.netPnl >= 0 ? 'text-green-400' : 'text-red-400'
                    }`}
                  >
                    {entry.netPnl >= 0 ? '+' : '−'}${Math.abs(entry.netPnl).toFixed(2)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </>
      )}

      <p className="mt-3 flex items-start gap-2 border-t border-border pt-3 text-[11px] leading-relaxed text-gray-500">
        <ImageIcon className="mt-0.5 h-3 w-3 flex-shrink-0" />
        <span>
          These are your recorded trades, not a simulation. Screenshots and notes are
          not replayed by the engine — they feed the AI review, which reads them
          qualitatively.
        </span>
      </p>
    </div>
  )
}
