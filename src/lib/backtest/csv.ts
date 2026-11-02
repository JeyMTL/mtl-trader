/**
 * Bar-data CSV import.
 *
 * The realistic data source for this app is the customer's own MT5 history —
 * "Save as Report" or the Copy-to-CSV of the chart window — so the parser is
 * built around that export first: tab separated, `<DATE> <TIME> OPEN HIGH LOW
 * CLOSE …` headers, dotted dates. Anything else in the same spirit works too:
 * comma or semicolon separated, one ISO timestamp or separate date and time.
 *
 * Everything is validated before any simulation runs. A malformed bar that slips
 * through does not throw later, it silently distorts the P&L, and a backtest that
 * quietly lies is worse than one that refuses to start.
 */

import type { Bar } from './types'

export interface ParseOptions {
  /** Minutes to add to each timestamp, for a broker server clock that is not UTC. */
  timezoneOffsetMinutes?: number
  /** Hard cap so one upload cannot exhaust the function. */
  maxBars?: number
}

/** 60k M1 bars is ~6 weeks of FX data and keeps a CSV under the 4.5 MB body limit. */
export const DEFAULT_MAX_BARS = 60_000

type ColumnMap = {
  date: number
  time: number | null
  open: number
  high: number
  low: number
  close: number
  volume: number | null
}

function normalizeHeader(cell: string): string {
  return cell
    .replace(/[<>"]/g, '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '')
}

function detectDelimiter(sample: string): string {
  const counts = [
    { delimiter: '\t', count: (sample.match(/\t/g) ?? []).length },
    { delimiter: ';', count: (sample.match(/;/g) ?? []).length },
    { delimiter: ',', count: (sample.match(/,/g) ?? []).length },
  ]
  counts.sort((a, b) => b.count - a.count)
  const best = counts[0]
  if (!best || best.count === 0) {
    throw new Error('Could not read the file: no tab, comma or semicolon separator was found.')
  }
  return best.delimiter
}

function mapColumns(header: string[]): ColumnMap {
  const index = (names: string[]): number =>
    header.findIndex((cell) => names.includes(normalizeHeader(cell)))

  const date = index(['date', 'datetime', 'timestamp', 'time', 'bar time'])
  const open = index(['open'])
  const high = index(['high'])
  const low = index(['low'])
  const close = index(['close', 'last'])
  const time = index(['time'])

  if (date < 0 || open < 0 || high < 0 || low < 0 || close < 0) {
    throw new Error(
      'The file needs a header row naming date, open, high, low and close (a time column is optional).'
    )
  }

  const volume = index(['volume', 'tickvol', 'tickvolume', 'vol'])
  // `time` only joins the date when the date column is date-only, which is the
  // MT5 layout. A single `datetime`/`timestamp` column stands alone.
  const dateHeader = normalizeHeader(header[date] ?? '')
  const separateTime = dateHeader === 'date' && time >= 0 && time !== date ? time : null

  return { date, time: separateTime, open, high, low, close, volume: volume >= 0 ? volume : null }
}

/**
 * Parses one timestamp. MT5 writes `2026.10.01` plus `10:00`, ISO writes
 * `2026-10-01T10:00:00Z`; both are read as UTC unless an offset is supplied,
 * because guessing the broker's server timezone from a file is not possible.
 */
function toEpochMs(dateCell: string, timeCell: string | null, offsetMinutes: number): number | null {
  const rawDate = dateCell.trim()
  if (!rawDate) return null

  // Only a dotted or slashed *date* is rewritten. Replacing every dot would
  // turn an ISO timestamp's milliseconds (`10:00:00.000Z`) into a dash and make
  // the row unreadable.
  let value = rawDate
  if (/^\d{4}\.\d{2}\.\d{2}/.test(value)) {
    value = value.replace(/\./g, '-')
  } else if (/^\d{4}\/\d{2}\/\d{2}/.test(value)) {
    value = value.replace(/\//g, '-')
  }

  if (timeCell && !/\d:\d/.test(value)) {
    value = `${value} ${timeCell.trim()}`
  }
  value = value.replace(/\s+/, 'T')
  if (!/z$/i.test(value) && !/[+-]\d{2}:?\d{2}$/.test(value)) {
    value = `${value}Z`
  }

  const parsed = Date.parse(value)
  if (!Number.isFinite(parsed)) return null
  return parsed - offsetMinutes * 60_000
}

function toNumber(cell: string | undefined): number | null {
  if (cell === undefined) return null
  const value = Number(cell.replace(/["\s]/g, ''))
  return Number.isFinite(value) ? value : null
}

export function parseBarsCsv(text: string, options: ParseOptions = {}): Bar[] {
  const maxBars = options.maxBars ?? DEFAULT_MAX_BARS
  const offset = options.timezoneOffsetMinutes ?? 0

  const cleaned = text.replace(/^\uFEFF/, '')
  const lines = cleaned.split(/\r?\n/).filter((line) => line.trim().length > 0)
  if (lines.length < 2) {
    throw new Error('The file is empty: export a history range from MT5 and try again.')
  }

  const delimiter = detectDelimiter(lines[0] ?? '')
  const header = (lines[0] ?? '').split(delimiter)
  if (header.some((cell) => /^[-\d.,]+$/.test(cell.trim()))) {
    throw new Error('The first row must be a header naming the columns, not data.')
  }

  const columns = mapColumns(header)
  const bars: Bar[] = []
  let duplicates = 0

  for (let lineIndex = 1; lineIndex < lines.length; lineIndex += 1) {
    const line = lines[lineIndex]
    if (!line) continue
    const cells = line.split(delimiter)
    const rowNumber = lineIndex + 1

    const time = toEpochMs(
      cells[columns.date] ?? '',
      columns.time === null ? null : (cells[columns.time] ?? ''),
      offset
    )
    const open = toNumber(cells[columns.open])
    const high = toNumber(cells[columns.high])
    const low = toNumber(cells[columns.low])
    const close = toNumber(cells[columns.close])
    const volume = columns.volume === null ? undefined : toNumber(cells[columns.volume]) ?? undefined

    if (time === null) {
      throw new Error(`Row ${rowNumber}: the date or time could not be read.`)
    }
    if (open === null || high === null || low === null || close === null) {
      throw new Error(`Row ${rowNumber}: open, high, low and close must all be numbers.`)
    }
    if (open <= 0 || high <= 0 || low <= 0 || close <= 0) {
      throw new Error(`Row ${rowNumber}: prices must be greater than zero.`)
    }
    if (high < low) {
      throw new Error(`Row ${rowNumber}: high (${high}) is below low (${low}).`)
    }
    if (high < Math.max(open, close) || low > Math.min(open, close)) {
      throw new Error(`Row ${rowNumber}: the open or close sits outside the bar's high and low.`)
    }

    const bar: Bar = { time, open, high, low, close }
    if (volume !== undefined) bar.volume = volume

    const previous = bars[bars.length - 1]
    if (previous) {
      if (time < previous.time) {
        throw new Error(
          `Row ${rowNumber}: timestamps must be in chronological order — sort the file ascending.`
        )
      }
      if (time === previous.time) {
        // MT5 exports can repeat the final bar; the last copy is the settled one.
        bars[bars.length - 1] = bar
        duplicates += 1
        continue
      }
    }

    bars.push(bar)
    if (bars.length > maxBars) {
      throw new Error(
        `That is more than ${maxBars.toLocaleString('en-US')} bars. Export a shorter range or a larger timeframe.`
      )
    }
  }

  if (bars.length < 50) {
    throw new Error(
      `Only ${bars.length} bars were read. A backtest needs at least 50, and a useful one needs several hundred.`
    )
  }

  void duplicates
  return bars
}
