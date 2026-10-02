/**
 * Prompt construction. Everything the model is told to reason about is passed
 * as pre-computed, deterministic numbers — the model narrates, it does not
 * calculate.
 */

import { tradePnl, tradeTime } from './edge-stats'
import { MAX_FINDINGS } from './schema'
import type { EdgeStats, GroupStat, PromptMessage, ReviewRequest, SimilarSetup, TradeRecord } from './types'

export interface Example {
  note: string
  outcome: number
  when: string | null
}

/** Pick the strongest and weakest noted trades as in-context examples. */
export function selectExamples(trades: TradeRecord[], perBucket = 2): Example[] {
  const withNotes = trades.filter((trade) => trade.notes && trade.notes.trim())
  const sorted = [...withNotes].sort((a, b) => tradePnl(b) - tradePnl(a))
  const picks = [...sorted.slice(0, perBucket), ...sorted.slice(-perBucket).reverse()]
  const seen = new Set<string>()
  const out: Example[] = []
  for (const trade of picks) {
    const note = (trade.notes || '').trim().slice(0, 240)
    if (!note || seen.has(note)) continue
    seen.add(note)
    out.push({ note, outcome: tradePnl(trade), when: tradeTime(trade) })
  }
  return out
}

function topGroups(groups: GroupStat[], count = 6): GroupStat[] {
  return [...groups].sort((a, b) => b.pnl - a.pnl).slice(0, count).map((group) => ({
    ...group,
    pnl: Number(group.pnl.toFixed(2)),
  }))
}

/** Trim the stats payload so large journals do not blow the context window. */
export function compactStats(stats: EdgeStats) {
  return {
    trades: stats.trades,
    wins: stats.wins,
    losses: stats.losses,
    winRate: Number(stats.winRate.toFixed(1)),
    pnl: Number(stats.pnl.toFixed(2)),
    profitFactor: Number.isFinite(stats.profitFactor) ? Number(stats.profitFactor.toFixed(2)) : 'inf',
    expectancy: Number(stats.expectancy.toFixed(2)),
    avgWin: Number(stats.avgWin.toFixed(2)),
    avgLoss: Number(stats.avgLoss.toFixed(2)),
    best: Number(stats.best.toFixed(2)),
    worst: Number(stats.worst.toFixed(2)),
    maxWinStreak: stats.maxWinStreak,
    maxLossStreak: stats.maxLossStreak,
    notesRecorded: stats.noteCount,
    bySymbol: topGroups(stats.bySymbol),
    bySession: stats.bySession,
    byWeekday: stats.byWeekday,
    byHoldTime: stats.byHoldTime,
  }
}

export function buildSystemPrompt(hasImage: boolean): string {
  return [
    'You are a careful trading-journal analyst.',
    'You are given deterministic statistics computed from the trader\'s own journal, plus excerpts of their notes.',
    'Ground every point in the supplied numbers and quote the metric you rely on as "evidence". Never invent statistics.',
    'If the sample is small or a pattern is weak, say so plainly and lower your confidence.',
    'Do not recommend specific assets, entries, exits, or position sizes, and do not predict markets.',
    hasImage ? 'A chart screenshot is attached; comment only on what is visible, and say if it is unclear.' : '',
    'Reply with a single JSON object and nothing else, matching this shape:',
    JSON.stringify({
      headline: 'one grounded sentence',
      confidence: 'low | medium | high',
      strengths: [{ title: '...', detail: '...', evidence: 'metric: value' }],
      risks: [{ title: '...', detail: '...', evidence: 'metric: value' }],
      actions: [{ title: '...', detail: '...' }],
    }),
    `Include at most ${MAX_FINDINGS} items per list. Keep each detail under 240 characters.`,
  ]
    .filter(Boolean)
    .join('\n')
}

export function buildUserPrompt(
  input: ReviewRequest,
  stats: EdgeStats,
  similar: SimilarSetup[],
  examples: Example[]
): string {
  const sections: string[] = []
  sections.push(`Journal statistics (computed, trust these):\n${JSON.stringify(compactStats(stats))}`)

  if (examples.length) {
    sections.push(
      `Notable trades with notes (strongest and weakest):\n${examples
        .map((example) => `- P&L ${example.outcome.toFixed(2)}${example.when ? ` (${example.when.slice(0, 10)})` : ''}: ${example.note}`)
        .join('\n')}`
    )
  }

  if (similar.length) {
    sections.push(
      `The trader's own past notes on similar setups (use these to reference their history):\n${similar
        .map((item) => `- outcome ${item.outcome.toFixed(2)}${item.when ? ` (${item.when.slice(0, 10)})` : ''}: ${item.note}`)
        .join('\n')}`
    )
  }

  if (input.question && input.question.trim()) {
    sections.push(`The trader specifically asks: ${input.question.trim().slice(0, 500)}`)
  }

  sections.push('Produce the JSON review now.')
  return sections.join('\n\n')
}

export function buildMessages(
  input: ReviewRequest,
  stats: EdgeStats,
  similar: SimilarSetup[],
  examples: Example[]
): PromptMessage[] {
  const text = buildUserPrompt(input, stats, similar, examples)
  const system: PromptMessage = { role: 'system', content: buildSystemPrompt(Boolean(input.chartImage)) }
  if (input.chartImage) {
    return [
      system,
      {
        role: 'user',
        content: [
          { type: 'text', text },
          { type: 'image', dataUrl: input.chartImage },
        ],
      },
    ]
  }
  return [system, { role: 'user', content: text }]
}
