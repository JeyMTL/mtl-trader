/**
 * Prop-firm evaluation rules: validation and shapes.
 *
 * The numbers here are the ones a prop firm publishes — daily loss cap, total
 * drawdown (trailing or static), profit target, minimum trading days. Validation
 * lives in a pure module so the route cannot accept a rule the status maths
 * would then divide by.
 */

export interface PropRules {
  account_size: number
  max_daily_loss_pct: number
  max_drawdown_pct: number
  trailing_drawdown: boolean
  profit_target_pct: number
  min_trading_days: number
  /**
   * The largest share of the total gain one trading day may produce, e.g. `30`
   * for a 30% consistency rule. Most firms publish one; a negative or zero
   * total has nothing to measure, so the rule only speaks once in profit.
   */
  consistency_pct: number
  /** `YYYY-MM-DD`, the day the evaluation started. */
  started_on: string
}

export type PropStatusLevel =
  | 'ok'
  | 'warn_daily'
  | 'breach_daily'
  | 'warn_drawdown'
  | 'breach_drawdown'
  | 'warn_consistency'
  | 'breach_consistency'

/** What `prop_status()` computes; amounts are in the account's currency. */
export interface PropStatus {
  configured: boolean
  account_size: number
  equity: number
  peak_equity: number
  daily_pnl: number
  daily_loss_limit: number
  daily_headroom: number
  drawdown: number
  drawdown_limit: number
  drawdown_headroom: number
  profit_target: number
  profit_progress: number
  best_day_pnl: number
  /** Actual share of total profit made by the best day, in percent. */
  consistency: number
  consistency_pct: number
  trading_days: number
  min_trading_days: number
  trailing_drawdown: boolean
  max_daily_loss_pct: number
  max_drawdown_pct: number
  profit_target_pct: number
  status: PropStatusLevel
}

export const DEFAULT_PROP_RULES: PropRules = {
  account_size: 10000,
  max_daily_loss_pct: 5,
  max_drawdown_pct: 10,
  trailing_drawdown: true,
  profit_target_pct: 10,
  min_trading_days: 5,
  consistency_pct: 30,
  started_on: new Date().toISOString().slice(0, 10),
}

export type ParseResult =
  | { ok: true; value: PropRules }
  | { ok: false; error: string }

function number(value: unknown): number {
  if (typeof value === 'number') return value
  if (typeof value === 'string' && value.trim()) return Number(value)
  return NaN
}

function isoDay(value: unknown): string | null {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null
  const date = new Date(`${value}T00:00:00.000Z`)
  return Number.isNaN(date.getTime()) ? null : value
}

/**
 * Validates a client payload. Bounds are deliberately generous but finite: a
 * 0% cap would make every trade a breach, and a 10,000,000% cap is a typo, not a
 * rule.
 */
export function parsePropRules(input: unknown): ParseResult {
  if (!input || typeof input !== 'object') return { ok: false, error: 'Invalid rule payload.' }
  const record = input as Record<string, unknown>

  const accountSize = number(record.account_size)
  if (!Number.isFinite(accountSize) || accountSize < 1 || accountSize > 100_000_000) {
    return { ok: false, error: 'Account size must be between 1 and 100,000,000.' }
  }

  const dailyLoss = number(record.max_daily_loss_pct)
  if (!Number.isFinite(dailyLoss) || dailyLoss <= 0 || dailyLoss > 50) {
    return { ok: false, error: 'Daily loss limit must be between 0 and 50%.' }
  }

  const drawdown = number(record.max_drawdown_pct)
  if (!Number.isFinite(drawdown) || drawdown <= 0 || drawdown > 100) {
    return { ok: false, error: 'Drawdown limit must be between 0 and 100%.' }
  }

  const target = number(record.profit_target_pct)
  if (!Number.isFinite(target) || target < 0 || target > 200) {
    return { ok: false, error: 'Profit target must be between 0 and 200%.' }
  }

  const minDays = number(record.min_trading_days)
  if (!Number.isFinite(minDays) || minDays < 0 || minDays > 60) {
    return { ok: false, error: 'Minimum trading days must be between 0 and 60.' }
  }

  // Optional so a client that predates the rule (or a saved form without the
  // field) keeps the previous behaviour instead of failing to save.
  const consistency =
    record.consistency_pct === undefined || record.consistency_pct === null
      ? DEFAULT_PROP_RULES.consistency_pct
      : number(record.consistency_pct)
  if (!Number.isFinite(consistency) || consistency <= 0 || consistency > 100) {
    return { ok: false, error: 'Consistency limit must be between 0 and 100%.' }
  }

  const startedOn = isoDay(record.started_on) ?? new Date().toISOString().slice(0, 10)

  return {
    ok: true,
    value: {
      account_size: Math.round(accountSize * 100) / 100,
      max_daily_loss_pct: dailyLoss,
      max_drawdown_pct: drawdown,
      trailing_drawdown: record.trailing_drawdown !== false,
      profit_target_pct: target,
      min_trading_days: Math.round(minDays),
      consistency_pct: consistency,
      started_on: startedOn,
    },
  }
}

/** Three-way read of the SQL status, so the card colours itself correctly. */
export function propStatusLevel(status: string | undefined): 'ok' | 'warning' | 'breach' {
  if (
    status === 'breach_daily' ||
    status === 'breach_drawdown' ||
    status === 'breach_consistency'
  ) {
    return 'breach'
  }
  if (
    status === 'warn_daily' ||
    status === 'warn_drawdown' ||
    status === 'warn_consistency'
  ) {
    return 'warning'
  }
  return 'ok'
}
