/**
 * Overlaying a second instrument on the desk's price axis.
 *
 * The two instruments have unrelated prices — EUR/USD around 1.08, NAS100 in
 * the twenty thousands — so plotting raw closes would put the compare line off
 * the top of the plot and say nothing. A compare overlay is a *relative* chart:
 * both series are read as percent moves from a shared anchor, and the second
 * series is then printed at the first series' anchor price so it lands inside
 * the plot the axis already describes.
 *
 * Anchoring at the first loaded bar, not the first visible one, matters: a pan
 * is a change of what the trader is looking at, not a change of what happened,
 * and a line that rebases under the pointer is a line you cannot read.
 */

export interface CandleLike {
  t: number
  c: number
}

export interface ComparePoint {
  /** Index into the main series, so a pan never rebuilds the series. */
  i: number
  /** The compare close, expressed in the main instrument's price units. */
  p: number
  /** No compare bar covers this main bar; the painter breaks the line here. */
  stale: boolean
}

export interface CompareSeries {
  points: ComparePoint[]
  /** Percent change across the aligned series, as a fraction (0.01 is +1%). */
  change: number
}

/** Index of the last bar at or before `t`, or -1 when the series starts later. */
function lastAtOrBefore(series: CandleLike[], t: number): number {
  let low = 0
  let high = series.length - 1
  let found = -1
  while (low <= high) {
    const middle = (low + high) >> 1
    if (series[middle].t <= t) {
      found = middle
      low = middle + 1
    } else {
      high = middle - 1
    }
  }
  return found
}

export function alignCompare(
  main: CandleLike[],
  compare: CandleLike[]
): CompareSeries | null {
  if (main.length === 0 || compare.length === 0) return null

  const anchor = main[0].c
  // The compare bar at the anchor time, carried forward from the first bar when
  // the compare window starts later than the main one.
  const baseIndex = lastAtOrBefore(compare, main[0].t)
  const base = baseIndex >= 0 ? compare[baseIndex].c : compare[0].c
  if (!(anchor > 0) || !(base > 0)) return null

  const step =
    main.length > 1 ? Math.max(1, main[1].t - main[0].t) : 60_000
  const tolerance = step / 2

  const points: ComparePoint[] = []
  let cursor = 0
  for (let i = 0; i < main.length; i += 1) {
    const t = main[i].t
    while (cursor + 1 < compare.length && compare[cursor + 1].t <= t) cursor += 1
    const at = compare[cursor]
    points.push({
      i,
      p: (anchor * at.c) / base,
      // A saturated weekend or a thin session leaves a hole rather than a
      // pretend flat stretch.
      stale: Math.abs(at.t - t) > tolerance,
    })
  }

  const first = points[0]
  const last = points[points.length - 1]
  const change = first.p > 0 ? last.p / first.p - 1 : 0

  return { points, change }
}
