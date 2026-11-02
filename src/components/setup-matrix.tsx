'use client'

import { useMemo, useState } from 'react'
import { LayoutGrid } from 'lucide-react'
import { cn, formatCurrency, formatPercent } from '@/lib/utils'
import { strategyColor } from '@/lib/strategy-colors'
import type { StrategyStat, TagStat } from '@/types/journal'

/**
 * Setups side by side.
 *
 * Tags and strategy labels answer the same question — "how does this model
 * perform?" — so they are one matrix rather than two tables the trader has to
 * compare by eye. Rows keep their source in a `kind` column because the two are
 * not the same field and a tag can legitimately duplicate a strategy name.
 *
 * Per-setup profit factor is not shown: the RPCs return net P&L per group, not
 * gross wins and losses, and computing a factor from those would be a different
 * (wrong) number than the headline one.
 */

interface Row {
  key: string
  label: string
  kind: 'tag' | 'strategy'
  trades: number
  pnl: number
  winRate: number
  expectancy: number
}

export function SetupMatrix({
  tagStats,
  strategyStats,
}: {
  tagStats: TagStat[]
  strategyStats: StrategyStat[]
}) {
  const rows = useMemo<Row[]>(() => {
    const tags: Row[] = tagStats.map((item) => ({
      key: `tag:${item.tag}`,
      label: item.tag,
      kind: 'tag',
      trades: Number(item.trades) || 0,
      pnl: Number(item.pnl) || 0,
      winRate: Number(item.win_rate) || 0,
      expectancy: Number(item.trades) ? (Number(item.pnl) || 0) / Number(item.trades) : 0,
    }))
    const strategies: Row[] = strategyStats.map((item) => ({
      key: `strategy:${item.strategy}`,
      label: item.strategy,
      kind: 'strategy',
      trades: Number(item.trades) || 0,
      pnl: Number(item.pnl) || 0,
      winRate: Number(item.win_rate) || 0,
      expectancy: Number(item.trades) ? (Number(item.pnl) || 0) / Number(item.trades) : 0,
    }))
    return [...tags, ...strategies].sort((a, b) => b.pnl - a.pnl || b.trades - a.trades)
  }, [tagStats, strategyStats])

  // Store what is turned off rather than what is on: a new setup that appears
  // after the next load is visible by default instead of silently filtered out.
  const [hidden, setHidden] = useState<Record<string, boolean>>({})
  // Colours are multi-select: the point of the filter is comparing models that
  // share a hue, so allowing only one would hide half of the comparison.
  const [colorFilter, setColorFilter] = useState<string[]>([])

  if (rows.length === 0) return null

  const colorGroups = (() => {
    const counts = new Map<string, number>()
    for (const row of rows) {
      const color = strategyColor(row.key)
      counts.set(color, (counts.get(color) ?? 0) + 1)
    }
    return [...counts.entries()]
      .map(([color, count]) => ({ color, count }))
      .sort((a, b) => b.count - a.count)
  })()

  const visible = rows.filter(
    (row) =>
      !hidden[row.key] &&
      (colorFilter.length === 0 || colorFilter.includes(strategyColor(row.key)))
  )

  const toggle = (key: string) => setHidden((current) => ({ ...current, [key]: !current[key] }))
  const toggleColor = (color: string) =>
    setColorFilter((current) =>
      current.includes(color) ? current.filter((item) => item !== color) : [...current, color]
    )

  return (
    <div className="rounded-xl border border-border bg-surface p-4 sm:p-6">
      <div className="flex items-center gap-2">
        <LayoutGrid className="h-5 w-5 text-primary" />
        <h2 className="text-lg font-semibold text-white">Setup matrix</h2>
      </div>
      <p className="mt-1 text-sm text-gray-400">
        Compare your trading models directly. Tap a setup to include or remove it; the two kinds of
        label are listed separately because they are different fields on the journal form.
      </p>

      {colorGroups.length > 1 && (
        <div className="mt-4 flex flex-wrap items-center gap-2">
          <span className="text-[10px] uppercase tracking-wide text-gray-500">Colour</span>
          {colorGroups.map((group) => {
            const active = colorFilter.includes(group.color)
            return (
              <button
                key={group.color}
                type="button"
                onClick={() => toggleColor(group.color)}
                aria-pressed={active}
                aria-label={`Filter by colour: ${group.count} setup${group.count === 1 ? '' : 's'}`}
                className={cn(
                  'inline-flex items-center gap-1.5 rounded-full border px-2 py-1 text-[11px] tabular-nums transition-colors',
                  active
                    ? 'border-primary bg-primary/15 text-white'
                    : 'border-border text-gray-400 hover:text-white'
                )}
              >
                <span
                  aria-hidden
                  className="h-2 w-2 rounded-full"
                  style={{ backgroundColor: group.color }}
                />
                {group.count}
              </button>
            )
          })}
          {colorFilter.length > 0 && (
            <button
              type="button"
              onClick={() => setColorFilter([])}
              className="text-[11px] text-gray-500 transition-colors hover:text-white"
            >
              Clear
            </button>
          )}
        </div>
      )}

      <div className="mt-4 flex flex-wrap gap-2">
        {rows.map((row) => {
          const active = !hidden[row.key]
          return (
            <button
              key={row.key}
              type="button"
              onClick={() => toggle(row.key)}
              aria-pressed={active}
              className={cn(
                'inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-xs font-medium transition-colors',
                active
                  ? 'border-primary/40 bg-primary/15 text-primary-light'
                  : 'border-border bg-background text-gray-500 hover:text-white'
              )}
            >
              <span
                aria-hidden
                className="h-2 w-2 shrink-0 rounded-full"
                style={{ backgroundColor: strategyColor(row.key) }}
              />
              {row.label}
              <span className="text-[10px] uppercase tracking-wide opacity-70">{row.kind}</span>
            </button>
          )
        })}
      </div>

      {visible.length === 0 ? (
        <p className="mt-4 text-sm text-gray-500">
          {colorFilter.length > 0 && rows.some((row) => !hidden[row.key])
            ? 'No setup on this list matches the colour filter.'
            : 'Every setup is hidden — tap one above to bring it back.'}
        </p>
      ) : (
        <>
          <div className="mt-4 grid gap-2 sm:hidden">
            {visible.map((row) => (
              <div key={row.key} className="rounded-lg border border-border bg-background p-3">
                <div className="flex items-baseline justify-between gap-3">
                  <p className="flex min-w-0 items-center gap-2 truncate text-sm font-medium text-white">
                    <span
                      aria-hidden
                      className="h-2 w-2 shrink-0 rounded-full"
                      style={{ backgroundColor: strategyColor(row.key) }}
                    />
                    {row.label}
                  </p>
                  <p className={cn('shrink-0 text-sm font-semibold tabular-nums', row.pnl >= 0 ? 'text-success' : 'text-danger')}>
                    {formatCurrency(row.pnl)}
                  </p>
                </div>
                <p className="mt-1 text-xs text-gray-500">
                  {row.kind} · {row.trades} trades · {formatPercent(row.winRate)} win ·{' '}
                  {formatCurrency(row.expectancy)}/trade
                </p>
              </div>
            ))}
          </div>

          <div className="mt-4 hidden overflow-x-auto sm:block">
            <table className="w-full">
              <thead>
                <tr className="border-b border-border">
                  <th className="px-3 py-2 text-left text-xs font-medium uppercase text-gray-400">Setup</th>
                  <th className="px-3 py-2 text-left text-xs font-medium uppercase text-gray-400">Kind</th>
                  <th className="px-3 py-2 text-right text-xs font-medium uppercase text-gray-400">Trades</th>
                  <th className="px-3 py-2 text-right text-xs font-medium uppercase text-gray-400">Win rate</th>
                  <th className="px-3 py-2 text-right text-xs font-medium uppercase text-gray-400">Expectancy</th>
                  <th className="px-3 py-2 text-right text-xs font-medium uppercase text-gray-400">Net P&amp;L</th>
                </tr>
              </thead>
              <tbody>
                {visible.map((row) => (
                  <tr key={row.key} className="border-b border-border last:border-0">
                    <td className="px-3 py-2 text-sm font-medium text-white">
                      <span className="inline-flex items-center gap-2">
                        <span
                          aria-hidden
                          className="h-2 w-2 shrink-0 rounded-full"
                          style={{ backgroundColor: strategyColor(row.key) }}
                        />
                        {row.label}
                      </span>
                    </td>
                    <td className="px-3 py-2 text-xs uppercase tracking-wide text-gray-500">{row.kind}</td>
                    <td className="px-3 py-2 text-right text-sm tabular-nums text-gray-300">{row.trades}</td>
                    <td className="px-3 py-2 text-right text-sm tabular-nums text-gray-300">
                      {formatPercent(row.winRate)}
                    </td>
                    <td className={cn('px-3 py-2 text-right text-sm tabular-nums', row.expectancy >= 0 ? 'text-gray-300' : 'text-danger')}>
                      {formatCurrency(row.expectancy)}
                    </td>
                    <td className={cn('px-3 py-2 text-right text-sm font-semibold tabular-nums', row.pnl >= 0 ? 'text-success' : 'text-danger')}>
                      {formatCurrency(row.pnl)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}

      <p className="mt-3 text-[10px] leading-relaxed text-gray-500">
        Sorted by net P&amp;L. Labels match exactly after trimming, so two spellings of one model appear
        as two rows; rename them on the journal form to combine them.
      </p>
    </div>
  )
}
