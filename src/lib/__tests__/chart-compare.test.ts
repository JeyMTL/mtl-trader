import { describe, expect, it } from 'vitest'

import { alignCompare, type CandleLike } from '@/lib/chart-compare'

function series(closes: number[], start = 0, step = 60_000): CandleLike[] {
  return closes.map((c, index) => ({ t: start + index * step, c }))
}

describe('compare overlay', () => {
  it('prints the compare series in the main instrument’s price units', () => {
    const main = series([1, 2, 3, 4])
    // Doubles over the same four bars.
    const compare = series([100, 140, 180, 200])
    const aligned = alignCompare(main, compare)

    expect(aligned).not.toBeNull()
    // The anchor bar is unchanged, and the last is the main anchor times the
    // compare's relative move, not the compare's own price.
    expect(aligned!.points[0].p).toBeCloseTo(1, 10)
    expect(aligned!.points[3].p).toBeCloseTo(2, 10)
    expect(aligned!.change).toBeCloseTo(1, 10)
  })

  it('keeps the same shape whichever price the instruments trade at', () => {
    const main = series([1.08, 1.075, 1.09])
    const cheap = alignCompare(main, series([100, 99.5, 101]))!
    const dear = alignCompare(main, series([20_000, 19_900, 20_200]))!
    // Ratios of adjacent points are identical; only the scale differs.
    expect(cheap.points[2].p / cheap.points[1].p).toBeCloseTo(
      dear.points[2].p / dear.points[1].p,
      10
    )
    expect(dear.points[0].p).toBeCloseTo(1.08, 10)
  })

  it('carries the last compare bar forward and marks the hole as stale', () => {
    const main = series([1, 1, 1, 1, 1])
    // The compare series is missing the last bar.
    const compare = series([50, 60, 70, 80], 0)
    const aligned = alignCompare(main, compare)!
    expect(aligned.points[3].stale).toBe(false)
    expect(aligned.points[4].stale).toBe(true)
    // Carried forward at the last known close rather than dropped.
    expect(aligned.points[4].p).toBeCloseTo(aligned.points[3].p, 10)
  })

  it('starts the compare window early enough for a main series that begins later', () => {
    const compare = series([10, 20, 30], 0, 60_000)
    const main: CandleLike[] = [
      { t: 180_000, c: 5 },
      { t: 240_000, c: 6 },
    ]
    const aligned = alignCompare(main, compare)!
    // Anchored on the compare bar at the main series' first timestamp.
    expect(aligned.points[0].p).toBeCloseTo(5, 10)
    expect(aligned.points[1].stale).toBe(true)
  })

  it('refuses to draw a line with nothing to anchor to', () => {
    expect(alignCompare([], series([1]))).toBeNull()
    expect(alignCompare(series([1]), [])).toBeNull()
    expect(alignCompare(series([1, 2]), series([0, 0]))).toBeNull()
  })
})
