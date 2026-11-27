/**
 * R-multiples and the session heatmap.
 *
 * A win of $400 says nothing on its own: it was a $200-risk trade or a
 * $4,000-risk one. Dividing the move by the distance to the stop turns every
 * trade into the same unit, so a journal of different sizes can be added up.
 * The calculation is in price units, so it needs no contract size and no
 * migration — only the entry, the exit and the stop the trader already logs.
 */

/** The columns this needs from a trade row. */
export interface RiskRow {
  type: string | null
  entry_price: number | null
  exit_price: number | null
  stop_loss: number | null
}

/**
 * How many R a closed trade made, or null when it cannot be measured.
 *
 * Null for a missing stop, a missing exit, or a stop exactly on the entry —
 * a trade with no risk defined has no R, and printing 0 would claim it was a
 * scratch.
 */
export function riskMultipleOf(row: RiskRow): number | null {
  // `Number(null)` is 0, which would quietly turn a missing stop into a risk of
  // the whole entry price. Absent has to stay absent.
  if (row.entry_price === null || row.exit_price === null || row.stop_loss === null) {
    return null
  }
  const entry = Number(row.entry_price)
  const exit = Number(row.exit_price)
  const stop = Number(row.stop_loss)
  if (!Number.isFinite(entry) || !Number.isFinite(exit) || !Number.isFinite(stop)) {
    return null
  }
  const risk = Math.abs(entry - stop)
  if (!(risk > 1e-9)) return null
  // A short profits when price falls, so its move is negated before dividing.
  const direction = String(row.type ?? '').toUpperCase() === 'SELL' ? -1 : 1
  const value = ((exit - entry) * direction) / risk
  return Number.isFinite(value) ? value : null
}

/** The measurable multiples in a set of rows, in the order they arrived. */
export function riskMultiples(rows: RiskRow[]): number[] {
  const values: number[] = []
  for (const row of rows) {
    const value = riskMultipleOf(row)
    if (value !== null) values.push(value)
  }
  return values
}

export interface RBucket {
  label: string
  count: number
  tone: 'loss' | 'flat' | 'gain'
}

/** Bucket edges, left-closed: `[-2, -1)` is the "-2R" column. */
const R_EDGES = [-2, -1, 0, 1, 2, 3]
const R_LABELS = ['<-2R', '-2R', '-1R', '0', '+1R', '+2R', '+3R']

/**
 * Seven columns from "worse than -2R" to "3R and beyond".
 *
 * The last bucket is open-ended on purpose: one 12R runner should not stretch
 * the scale until every ordinary trade is a one-pixel bar.
 */
export function rDistribution(values: number[]): RBucket[] {
  const counts = R_LABELS.map(() => 0)
  for (const value of values) {
    let bucket = R_LABELS.length - 1
    for (let index = 0; index < R_EDGES.length; index++) {
      if (value < R_EDGES[index]) {
        bucket = index
        break
      }
    }
    counts[bucket] += 1
  }
  return counts.map((count, index) => ({
    label: R_LABELS[index],
    count,
    tone: index <= 2 ? 'loss' : index === 3 ? 'flat' : 'gain',
  }))
}

export interface RSummary {
  count: number
  average: number
  median: number
  best: number
  worst: number
  /** Share of measured trades that finished in profit, in percent. */
  hitRate: number
}

function median(sorted: number[]): number {
  if (sorted.length === 0) return 0
  const middle = Math.floor(sorted.length / 2)
  return sorted.length % 2 === 0
    ? (sorted[middle - 1] + sorted[middle]) / 2
    : sorted[middle]
}

/** Average and median R, plus the spread the average hides. */
export function rSummary(values: number[]): RSummary {
  if (values.length === 0) {
    return { count: 0, average: 0, median: 0, best: 0, worst: 0, hitRate: 0 }
  }
  const sorted = [...values].sort((a, b) => a - b)
  const total = values.reduce((sum, value) => sum + value, 0)
  return {
    count: values.length,
    average: total / values.length,
    median: median(sorted),
    best: sorted[sorted.length - 1],
    worst: sorted[0],
    hitRate: (values.filter((value) => value > 0).length / values.length) * 100,
  }
}

/**
 * The four UTC windows `session_stats()` uses. A trade in the London/New York
 * overlap counts in both, exactly as it does in the journal filter.
 */
export const SESSION_WINDOWS = [
  { session: 'sydney', firstHour: 21, lastHour: 6 },
  { session: 'asian', firstHour: 0, lastHour: 9 },
  { session: 'london', firstHour: 7, lastHour: 16 },
  { session: 'newyork', firstHour: 12, lastHour: 21 },
] as const

export interface SessionDayCell {
  session: string
  /** 1 = Monday … 5 = Friday, in UTC. */
  weekday: number
  pnl: number
  trades: number
}

/** Weekday in UTC, 1 = Monday; 6/7 are the weekend and are not plotted. */
export function utcWeekday(iso: string): number | null {
  const time = new Date(iso).getTime()
  if (Number.isNaN(time)) return null
  const day = new Date(time).getUTCDay()
  return day === 0 ? 7 : day
}

function inWindow(hour: number, firstHour: number, lastHour: number): boolean {
  return firstHour < lastHour
    ? hour >= firstHour && hour < lastHour
    : hour >= firstHour || hour < lastHour
}

/**
 * P&L per session per weekday, for the heatmap.
 *
 * Empty cells are left out rather than filled with zeros, so the map can tell
 * "you lost money on Tuesday in London" from "you did not trade it".
 */
export function sessionDayHeat(
  rows: Array<{ open_time: string | null; pnl: number }>
): SessionDayCell[] {
  const cells = new Map<string, SessionDayCell>()
  for (const row of rows) {
    if (!row.open_time) continue
    const when = new Date(row.open_time)
    if (Number.isNaN(when.getTime())) continue
    const weekday = utcWeekday(row.open_time)
    if (weekday === null || weekday > 5) continue
    const hour = when.getUTCHours()
    for (const window of SESSION_WINDOWS) {
      if (!inWindow(hour, window.firstHour, window.lastHour)) continue
      const key = `${window.session}:${weekday}`
      const cell = cells.get(key) ?? {
        session: window.session,
        weekday,
        pnl: 0,
        trades: 0,
      }
      cell.pnl += Number(row.pnl) || 0
      cell.trades += 1
      cells.set(key, cell)
    }
  }
  return [...cells.values()]
}
