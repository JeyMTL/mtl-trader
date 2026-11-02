/**
 * Review orchestration: compute deterministic stats, retrieve similar notes,
 * build the prompt, call the injected model, and validate/normalize the result.
 *
 * The model call is injected so the whole pipeline is testable without network.
 */

import { buildCoachInsights } from './coach'
import { computeEdgeStats } from './edge-stats'
import { buildMessages, selectExamples } from './prompt'
import { buildQueryFromTrades, findSimilarNotes } from './retrieval'
import { insufficientDataReview, normalizeReview } from './schema'
import type {
  CoachInsight,
  EdgeStats,
  GenerateReviewDeps,
  GroupStat,
  PromptMessage,
  ReviewRequest,
  ReviewResult,
  SimilarSetup,
} from './types'

/** Fallback stats when only the legacy summary (no full trades) is provided. */
export function statsFromSummary(input: ReviewRequest): EdgeStats {
  const toGroups = (
    rows: Array<{ key: string; trades?: number; pnl: number; winRate?: number }> | undefined
  ): GroupStat[] =>
    (rows || []).map((row) => ({
      key: row.key,
      trades: row.trades ?? 0,
      wins: 0,
      losses: 0,
      pnl: Number(row.pnl) || 0,
      winRate: Number(row.winRate) || 0,
      expectancy: row.trades ? (Number(row.pnl) || 0) / row.trades : 0,
    }))

  const trades = Number(input.totalTrades) || 0
  const minSample = 10
  return {
    trades,
    wins: Number(input.wins) || 0,
    losses: Number(input.losses) || 0,
    winRate: Number(input.winRate) || 0,
    pnl: Number(input.totalPnl) || 0,
    grossWins: 0,
    grossLosses: 0,
    profitFactor: Number(input.profitFactor) || 0,
    expectancy: Number(input.expectancy) || 0,
    avgWin: Number(input.avgWin) || 0,
    avgLoss: Number(input.avgLoss) || 0,
    best: 0,
    worst: 0,
    maxWinStreak: 0,
    maxLossStreak: 0,
    currentStreak: 0,
    bySymbol: toGroups(input.symbols?.map((s) => ({ key: s.symbol, trades: s.trades, pnl: s.pnl, winRate: s.winRate }))),
    byWeekday: toGroups(input.weekdays?.map((w) => ({ key: w.day, pnl: w.pnl }))),
    bySession: [],
    byHoldTime: [],
    noteCount: 0,
    insufficient: trades < minSample,
    minSample,
  }
}

export interface PreparedReview {
  stats: EdgeStats
  similar: SimilarSetup[]
  /** Deterministic comparisons, shown even when the model is unavailable. */
  insights: CoachInsight[]
  messages: PromptMessage[]
  /** True when the sample guard short-circuited before building a model call. */
  skipped: boolean
  /** Present only when `skipped` is true. */
  earlyReview?: ReviewResult
}

/**
 * Compute stats, retrieve similar notes, and build the prompt. Split out so the
 * streaming route can reuse it and feed the provider's token stream.
 */
export function prepareReview(input: ReviewRequest): PreparedReview {
  const trades = input.trades || []
  const stats = trades.length > 0 ? computeEdgeStats(trades) : statsFromSummary(input)
  const insights = trades.length > 0 ? buildCoachInsights(trades, stats) : []

  if (stats.insufficient) {
    return {
      stats,
      similar: [],
      insights,
      messages: [],
      skipped: true,
      earlyReview: insufficientDataReview(stats),
    }
  }

  const query = (input.question && input.question.trim()) || buildQueryFromTrades(trades)
  const similar = trades.length > 0 ? findSimilarNotes(trades, query) : []
  const examples = trades.length > 0 ? selectExamples(trades) : []

  return {
    stats,
    similar,
    insights,
    messages: buildMessages(input, stats, similar, examples, insights),
    skipped: false,
  }
}

export interface GeneratedReview {
  review: ReviewResult
  stats: EdgeStats
  similar: SimilarSetup[]
  insights: CoachInsight[]
  /** True when the sample guard short-circuited before calling the model. */
  skipped: boolean
}

export async function generateReview(
  input: ReviewRequest,
  deps: GenerateReviewDeps
): Promise<GeneratedReview> {
  const prepared = prepareReview(input)
  if (prepared.skipped) {
    return {
      review: prepared.earlyReview!,
      stats: prepared.stats,
      similar: [],
      insights: prepared.insights,
      skipped: true,
    }
  }

  const raw = await deps.complete(prepared.messages, { json: true })
  const review = normalizeReview(raw, prepared.stats, prepared.similar)

  return {
    review,
    stats: prepared.stats,
    similar: prepared.similar,
    insights: prepared.insights,
    skipped: false,
  }
}
