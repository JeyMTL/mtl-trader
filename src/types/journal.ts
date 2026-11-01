/** Shapes returned by the aggregate RPCs in `20261026_billing_lifecycle_and_scale.sql`. */

export interface TradeSummary {
  total_trades: number
  wins: number
  losses: number
  month_trades: number
  month_wins: number
  month_pnl: number
  month_winning_days: number
  total_pnl: number
  gross_profit: number
  gross_loss: number
  best_trade: number
  worst_trade: number
  has_trade_today: boolean
}

export interface EquityPoint {
  /** `YYYY-MM-DD` */
  day: string
  pnl: number
  cumulative: number
  trades: number
}

export interface SymbolStat {
  symbol: string
  trades: number
  wins: number
  pnl: number
}

export interface WeekdayStat {
  /** 0 = Sunday … 6 = Saturday */
  dow: number
  wins: number
  losses: number
  pnl: number
}

export interface MonthStat {
  /** `YYYY-MM` */
  month: string
  pnl: number
}

export interface TradeBreakdowns {
  weekdays: WeekdayStat[]
  months: MonthStat[]
}

export interface TradeRow {
  id: string
  symbol: string
  type: string
  entry_price: number
  exit_price: number
  lot_size: number
  stop_loss: number | null
  take_profit: number | null
  pnl: number
  commission: number | null
  swap: number | null
  open_time: string | null
  close_time: string | null
  strategy: string | null
  notes: string | null
  tags: string[] | null
  ticket: number | null
  created_at: string
  image_count?: number
  audio_count?: number
}

/** One UTC trading window from `session_stats` (migration 20261105). */
export interface SessionWindowStat {
  session: string
  trades: number
  wins: number
  losses: number
  pnl: number
}

export interface TradePageResult {
  total: number
  total_pnl: number
  trades: TradeRow[]
}

export interface HourStat {
  /** 0–23, in the user's timezone */
  hour: number
  trades: number
  wins: number
  losses: number
  pnl: number
}

export interface SessionStat {
  session: string
  first_hour: number
  last_hour: number
  trades: number
  wins: number
  losses: number
  pnl: number
}

export interface HoldStat {
  trades: number
  median_minutes: number | null
  average_minutes: number | null
}

export interface TimeStats {
  timezone: string
  hours: HourStat[]
  sessions: SessionStat[]
  hold: HoldStat
}

export const EMPTY_TIME_STATS: TimeStats = {
  timezone: 'UTC',
  hours: [],
  sessions: [],
  hold: { trades: 0, median_minutes: null, average_minutes: null },
}

export interface JournalAttachmentRow {
  id: string
  user_id?: string
  trade_id?: string
  kind: 'image' | 'audio'
  storage_path?: string
  file_name?: string | null
  mime_type: string | null
  size_bytes?: number | null
  duration_seconds: number | null
  created_at?: string
}

export interface JournalFeedEntry {
  id: string
  symbol: string
  type: string
  pnl: number
  strategy: string | null
  notes: string | null
  tags: string[] | null
  open_time: string | null
  close_time: string | null
  created_at: string
  image_count: number
  audio_count: number
  attachments: JournalAttachmentRow[]
}

export interface TagStat {
  tag: string
  trades: number
  wins: number
  losses: number
  pnl: number
  win_rate: number
}

export interface DailyPnlRow {
  /** `YYYY-MM-DD` */
  day: string
  pnl: number
  trades: number
}

export interface NotificationPreferences {
  notifications_journal_reminders: boolean
  notifications_monthly_overview: boolean
}

export const EMPTY_SUMMARY: TradeSummary = {
  total_trades: 0,
  wins: 0,
  losses: 0,
  month_trades: 0,
  month_wins: 0,
  month_pnl: 0,
  month_winning_days: 0,
  total_pnl: 0,
  gross_profit: 0,
  gross_loss: 0,
  best_trade: 0,
  worst_trade: 0,
  has_trade_today: false,
}
