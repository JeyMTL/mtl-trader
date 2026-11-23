/**
 * The daily stop: one loss budget per trading day, measured on the trader's own
 * clock.
 *
 * This module is pure on purpose. It decides whether the day is over, how much
 * of the budget is left, and which trades were taken *after* the stop — all
 * from the rows the journal already has. The route, the dashboard card and the
 * trade form therefore cannot disagree about the number, and the rules can be
 * unit tested without a database, a browser or a network.
 *
 * The limit is deliberately one-directional: it stops new risk, never exits.
 * A trader with an open position must always be able to close it, and nothing
 * here is wired into order execution anyway.
 */

import { normalizeTimeZone, zonedDayBounds } from './timezone'

export interface DailyStopRules {
  /** Loss budget for the day, in account currency. 0 disables the rule. */
  limit: number
  /** Most entries allowed today. 0 disables the cap. */
  maxTrades: number
  /** IANA zone, or anything `normalizeTimeZone` understands. */
  timeZone: string
}

export interface TradeForDay {
  id?: string
  pnl: number
  close_time?: string | null
  open_time?: string | null
  created_at?: string | null
  tags?: string[] | null
}

export type DailyStopState = 'off' | 'inside' | 'breached'

/**
 * How hard the stop holds.
 *
 * `soft` freezes MT5 through the guard EA and leaves the journal usable; the
 * trader can lift it with a written reason. `hard` freezes MT5 as well and
 * locks the journal until the reset, with no in-app release. The EA refuses
 * programmatic orders and removes pending ones; it is as close to a broker-side
 * block as a client can get, and it cannot intercept a manual market-order
 * click before the fill.
 */
export type LockMode = 'off' | 'soft' | 'hard'

export interface DayLock {
  mode: LockMode
  /** The rule is reached, is not overridden, and a lock mode is chosen. */
  active: boolean
}

export interface DayState {
  /** A limit or a trade cap is set, so the card has something to say. */
  configured: boolean
  state: DailyStopState
  dayKey: string
  /** ISO bounds of the local day, so the client can count down to the reset. */
  dayStart: string
  dayEnd: string
  lossLimit: number
  maxTrades: number
  realizedPnl: number
  /** Loss consumed, never negative. */
  lossUsed: number
  /** Loss still allowed before the stop; 0 once reached. */
  headroom: number
  tradesCount: number
  /** Entries left under the cap; null when there is no cap. */
  tradesRemaining: number | null
  /** True when the loss budget or the trade cap has been reached. */
  breached: boolean
  /** True inside 80% of a limit, which is the point to slow down. */
  atLimit: boolean
  /** The trade cap has been reached (separate from the loss budget). */
  capReached: boolean
  /** Close time of the trade that reached the limit; null when inside it. */
  stopAt: string | null
  /** Trades taken after the first trade that reached either limit. */
  afterStopCount: number
  afterStopPnl: number
}

export interface DailyStopDebrief {
  followed: boolean | null
  valid: boolean | null
  note: string
}

export interface DailyStopOverride {
  reason: string
  at: string
}

/** Shape `/api/day-state` returns to the dashboard and the trade form. */
export interface DayStateResponse {
  configured: boolean
  missing?: boolean
  day: { key: string; start: string; end: string }
  rules: { limit: number; maxTrades: number; timeZone: string }
  state: DayState
  lock: DayLock
  overridden: boolean
  debrief: DailyStopDebrief | null
  override: DailyStopOverride | null
}

export const DEFAULT_DAILY_STOP: DailyStopRules = {
  limit: 0,
  maxTrades: 0,
  timeZone: 'UTC',
}

/** Upper bound on a stored limit, so a typo cannot become an impossible rule. */
export const MAX_DAILY_LOSS_LIMIT = 100_000_000
export const MAX_TRADES_PER_DAY = 100

/** Clamps a stored or typed value into the range the rule understands. */
export function normalizeDailyStop(input: {
  limit?: unknown
  maxTrades?: unknown
  timeZone?: unknown
}): DailyStopRules {
  const limit = Number(input.limit)
  const maxTrades = Number(input.maxTrades)
  return {
    limit:
      Number.isFinite(limit) && limit > 0
        ? Math.min(MAX_DAILY_LOSS_LIMIT, Math.round(limit * 100) / 100)
        : 0,
    maxTrades:
      Number.isFinite(maxTrades) && maxTrades > 0
        ? Math.min(MAX_TRADES_PER_DAY, Math.round(maxTrades))
        : 0,
    timeZone: normalizeTimeZone(typeof input.timeZone === 'string' ? input.timeZone : null),
  }
}

/** Anything unrecognised becomes `off`, so a bad row cannot lock an account. */
export function normalizeLockMode(value: unknown): LockMode {
  return value === 'soft' || value === 'hard' ? value : 'off'
}

/** The instant a trade belongs to: its close, falling back to its open/creation. */
export function tradeInstant(trade: TradeForDay): Date | null {
  const raw = trade.close_time ?? trade.open_time ?? trade.created_at
  if (!raw) return null
  const date = new Date(raw)
  return Number.isNaN(date.getTime()) ? null : date
}

/**
 * The day's numbers.
 *
 * Trades are ordered by their own clock rather than by row id, because a trade
 * imported in the evening may have closed in the morning. The first trade that
 * reaches either limit marks the stop; everything after it is "after stop",
 * which is the cohort worth showing a trader, not an accusation.
 */
export function computeDayState(options: {
  rules: DailyStopRules
  trades: TradeForDay[]
  now?: Date
}): DayState {
  const now = options.now ?? new Date()
  const rules = options.rules
  const bounds = zonedDayBounds(now, rules.timeZone)
  const limit = Math.max(0, rules.limit)
  const maxTrades = Math.max(0, Math.round(rules.maxTrades))
  const configured = limit > 0 || maxTrades > 0

  const inDay = options.trades
    .map((trade) => ({ trade, at: tradeInstant(trade) }))
    .filter(
      (entry): entry is { trade: TradeForDay; at: Date } =>
        entry.at !== null && entry.at >= bounds.start && entry.at < bounds.end
    )
    .sort((a, b) => a.at.getTime() - b.at.getTime())
    .map((entry) => entry.trade)

  let realizedPnl = 0
  let triggerIndex = -1
  for (let index = 0; index < inDay.length; index += 1) {
    realizedPnl += Number(inDay[index].pnl) || 0
    if (triggerIndex < 0 && limit > 0 && realizedPnl <= -limit) {
      triggerIndex = index
    }
  }

  const lossUsed = Math.max(0, -realizedPnl)
  const lossBreached = limit > 0 && lossUsed >= limit
  const capReached = maxTrades > 0 && inDay.length >= maxTrades
  const breached = lossBreached || capReached

  // The trade cap is reached at the last allowed entry; the loss stop when the
  // running total first crosses the budget. Whichever came first owns the stop.
  if (triggerIndex < 0 && capReached) {
    triggerIndex = Math.min(inDay.length, maxTrades) - 1
  }

  const stopAt =
    triggerIndex >= 0 && triggerIndex < inDay.length
      ? (tradeInstant(inDay[triggerIndex])?.toISOString() ?? null)
      : null
  const afterStop = triggerIndex >= 0 ? inDay.slice(triggerIndex + 1) : []
  const afterStopPnl = afterStop.reduce((sum, trade) => sum + (Number(trade.pnl) || 0), 0)
  const atLimit =
    !breached &&
    ((limit > 0 && lossUsed >= limit * 0.8) ||
      (maxTrades > 0 && inDay.length >= maxTrades - 1))

  return {
    configured,
    state: !configured ? 'off' : breached ? 'breached' : 'inside',
    dayKey: bounds.key,
    dayStart: bounds.start.toISOString(),
    dayEnd: bounds.end.toISOString(),
    lossLimit: limit,
    maxTrades,
    realizedPnl,
    lossUsed,
    headroom: limit > 0 ? Math.max(0, limit - lossUsed) : 0,
    tradesCount: inDay.length,
    tradesRemaining: maxTrades > 0 ? Math.max(0, maxTrades - inDay.length) : null,
    breached,
    atLimit,
    capReached,
    stopAt,
    afterStopCount: afterStop.length,
    afterStopPnl,
  }
}

/**
 * Whether the day is locked right now, and how much of a fresh budget an
 * override has left.
 *
 * A lift is a grace run, not a switch that disables the stop until midnight. The
 * trades that closed before the trader's written reason are history; the stop
 * re-arms on the trades that closed after it, with the same budget. That is the
 * difference between a speed bump and a button that turns the rule off: without
 * it, one reset means `nothing happens` for the rest of the day, which is
 * exactly what a stop is supposed to prevent.
 */
export function computeDayLock(options: {
  rules: DailyStopRules
  mode: LockMode
  state: DayState
  trades: TradeForDay[]
  overrideAt?: Date | null
  now?: Date
}): { active: boolean; resumed: DayState | null } {
  if (options.mode === 'off') return { active: false, resumed: null }
  const overrideAt = options.overrideAt ?? null
  if (!overrideAt || Number.isNaN(overrideAt.getTime())) {
    return { active: options.state.breached, resumed: null }
  }
  const resumed = computeDayState({
    rules: options.rules,
    trades: options.trades.filter((trade) => {
      const at = tradeInstant(trade)
      return at !== null && at >= overrideAt
    }),
    now: options.now,
  })
  return { active: resumed.breached, resumed }
}

/**
 * Whether an entry would be taken after today's stop, which is what earns the
 * `after_stop` tag. A trade dated on another day is not part of this day's
 * story, so it is left alone.
 */
export function isAfterStopEntry(
  trade: TradeForDay,
  day: { dayStart: string; dayEnd: string },
  breached: boolean
): boolean {
  if (!breached) return false
  const at = tradeInstant(trade)
  if (!at) return false
  return at >= new Date(day.dayStart) && at < new Date(day.dayEnd)
}
