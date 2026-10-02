/**
 * Shared types for the AI review pipeline. Kept dependency-free so every layer
 * (stats, retrieval, prompt, provider, validation) can be unit tested.
 */

export interface TradeRecord {
  symbol?: string | null
  type?: string | null
  pnl: number | string
  lot_size?: number | string | null
  open_time?: string | null
  close_time?: string | null
  created_at?: string | null
  timeframe?: string | null
  strategy?: string | null
  notes?: string | null
  tags?: string[] | null
}

/** Legacy/summary input the dashboard already builds. All fields optional. */
export interface SummaryInput {
  totalTrades?: number
  wins?: number
  losses?: number
  winRate?: number
  totalPnl?: number
  profitFactor?: number
  maxDrawdown?: number
  expectancy?: number
  avgWin?: number
  avgLoss?: number
  symbols?: Array<{ symbol: string; trades: number; winRate: number; pnl: number }>
  weekdays?: Array<{ day: string; wins: number; losses: number; pnl: number }>
  months?: Array<{ month: string; pnl: number }>
}

export interface ReviewRequest extends SummaryInput {
  /** Full trades give the model notes, session and hold-time context. */
  trades?: TradeRecord[]
  /** Optional question the trader wants answered. */
  question?: string
  /** Optional chart screenshot as a data URL (vision models). */
  chartImage?: string
}

export interface GroupStat {
  key: string
  trades: number
  wins: number
  losses: number
  pnl: number
  winRate: number
  expectancy: number
}

export interface EdgeStats {
  trades: number
  wins: number
  losses: number
  winRate: number
  pnl: number
  grossWins: number
  grossLosses: number
  profitFactor: number
  expectancy: number
  avgWin: number
  avgLoss: number
  best: number
  worst: number
  maxWinStreak: number
  maxLossStreak: number
  currentStreak: number
  bySymbol: GroupStat[]
  bySession: GroupStat[]
  byWeekday: GroupStat[]
  byHoldTime: GroupStat[]
  noteCount: number
  /** True when there is not enough data for a trustworthy review. */
  insufficient: boolean
  minSample: number
}

export interface ReviewFinding {
  title: string
  detail: string
  /** The deterministic metric this finding is grounded in, e.g. "London: -$120". */
  evidence?: string
}

export type Confidence = 'low' | 'medium' | 'high'

export interface SimilarSetup {
  note: string
  outcome: number
  when?: string | null
  score: number
}

export interface ReviewResult {
  headline: string
  confidence: Confidence
  sampleSize: number
  strengths: ReviewFinding[]
  risks: ReviewFinding[]
  actions: ReviewFinding[]
  similarSetups: SimilarSetup[]
  disclaimer: string
}

export interface ReviewMeta {
  provider: string
  model: string
  cached: boolean
  generatedAt: string
  stats: EdgeStats
}

export interface GenerateReviewDeps {
  /** Calls the model. Injected so tests never hit the network. */
  complete: (messages: PromptMessage[], options?: { json?: boolean; signal?: AbortSignal }) => Promise<string>
  providerName?: string
  model?: string
  now?: Date
}

export interface PromptMessage {
  role: 'system' | 'user' | 'assistant'
  content: string | PromptContent[]
}

export type PromptContent =
  | { type: 'text'; text: string }
  | { type: 'image'; dataUrl: string }
