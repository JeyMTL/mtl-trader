import { describe, expect, it } from 'vitest'
import { niceStep, objectInPane, priceAxisTicks, timeAxisTicks } from '@/components/chart-workspace'

/** The step between two ticks, which for a round axis must be a ladder number. */
function steps(ticks: number[]): number[] {
  return ticks.slice(1).map((tick, index) => Number((tick - ticks[index]).toFixed(10)))
}

function isLadderStep(step: number): boolean {
  const magnitude = 10 ** Math.floor(Math.log10(step))
  const normalised = Number((step / magnitude).toFixed(6))
  return [1, 2, 2.5, 5, 10].some((candidate) => Math.abs(candidate - normalised) < 1e-6)
}

describe('priceAxisTicks', () => {
  it('fits more labels on a tall plot than on a short one', () => {
    const tall = priceAxisTicks(1800, 2000, 900, 1)
    const short = priceAxisTicks(1800, 2000, 240, 1)

    expect(tall.length).toBeGreaterThan(short.length)
    // Three is the floor: two labels only say "top" and "bottom".
    expect(short.length).toBeGreaterThanOrEqual(3)
  })

  it('keeps at least 32px between labels at every height', () => {
    for (const height of [180, 300, 640, 1200]) {
      const ticks = priceAxisTicks(1.07, 1.09, height, 5)
      const step = ticks[1] - ticks[0]
      const pixelGap = (step / (1.09 - 1.07)) * height
      expect(pixelGap).toBeGreaterThanOrEqual(32)
      expect(ticks[0]).toBeGreaterThanOrEqual(1.07)
      expect(ticks[ticks.length - 1]).toBeLessThanOrEqual(1.09)
    }
  })

  it('only uses steps a trader reads as round', () => {
    for (const [min, max, precision] of [
      [1800, 2000, 1],
      [0.98, 1.02, 5],
      [60_000, 68_000, 0],
      [0.00012, 0.00014, 6],
    ] as const) {
      const ticks = priceAxisTicks(min, max, 600, precision)
      for (const step of steps(ticks)) {
        expect(isLadderStep(step), `step ${step} for ${min}..${max}`).toBe(true)
      }
    }
  })

  it('never steps below the instrument precision', () => {
    // A 0.4 pip range: a 1e-6 step would print the same 5 decimals twice.
    const ticks = priceAxisTicks(1.085, 1.0854, 600, 5)
    const step = ticks[1] - ticks[0]
    expect(step).toBeGreaterThanOrEqual(0.00001)
    const printed = ticks.map((tick) => tick.toFixed(5))
    expect(new Set(printed).size).toBe(printed.length)
  })

  it('refuses a range with no height or no width', () => {
    expect(priceAxisTicks(10, 10, 600, 2)).toEqual([])
    expect(priceAxisTicks(10, 20, 0, 2)).toEqual([])
  })

  it('rounds a raw step up to the next rung of the ladder', () => {
    expect(niceStep(0.013)).toBeCloseTo(0.02, 10)
    expect(niceStep(1.1)).toBeCloseTo(2, 10)
    expect(niceStep(37)).toBeCloseTo(50, 10)
  })
})

describe('timeAxisTicks', () => {
  // Fri 27 Nov 2026 13:00Z onwards.
  const start = Date.UTC(2026, 10, 27, 13, 0)
  const end = Date.UTC(2026, 10, 27, 17, 0)

  it('lands on real clock boundaries, not on bar counts', () => {
    const ticks = timeAxisTicks(start, end, 900)
    expect(ticks.length).toBeGreaterThan(1)
    for (const tick of ticks) {
      expect(tick.ms % 60_000).toBe(0)
      expect(tick.ms).toBeGreaterThanOrEqual(start)
      expect(tick.ms).toBeLessThanOrEqual(end)
      expect(tick.label).toMatch(/^\d{2}:\d{2}$/)
    }
  })

  it('keeps labels at least 95px apart', () => {
    const ticks = timeAxisTicks(start, end, 900)
    const span = end - start
    const scaled = ticks.map((tick) => ((tick.ms - start) / span) * 900)
    for (let index = 1; index < scaled.length; index += 1) {
      expect(scaled[index] - scaled[index - 1]).toBeGreaterThanOrEqual(95 - 1e-6)
    }
  })

  it('steps up to the calendar when the view is zoomed out', () => {
    const yearStart = Date.UTC(2026, 0, 1)
    const yearEnd = Date.UTC(2027, 0, 1)
    const ticks = timeAxisTicks(yearStart, yearEnd, 1000)

    expect(ticks.length).toBeGreaterThan(3)
    expect(ticks.length).toBeLessThan(20)
    for (const tick of ticks) {
      const date = new Date(tick.ms)
      expect(date.getUTCDate()).toBe(1)
      expect(date.getUTCHours()).toBe(0)
    }
    // A month boundary is a major tick, and January prints the year.
    expect(ticks.some((tick) => tick.major && /^\d{4}$/.test(tick.label))).toBe(true)
  })

  it('does not leave a hundred-day view almost bare', () => {
    const ticks = timeAxisTicks(Date.UTC(2026, 7, 1), Date.UTC(2026, 10, 9), 1000)
    // Roughly ten labels across a 1000px plot is the target; three would be a
    // sparse axis, which is the complaint this generator exists to answer.
    expect(ticks.length).toBeGreaterThanOrEqual(5)
  })

  it('marks a new day in heavier type on an intraday axis', () => {
    const ticks = timeAxisTicks(Date.UTC(2026, 10, 27, 20, 0), Date.UTC(2026, 10, 28, 4, 0), 900)
    const midnight = ticks.find((tick) => tick.ms === Date.UTC(2026, 10, 28, 0, 0))
    expect(midnight).toBeTruthy()
    expect(midnight?.major).toBe(true)
    expect(midnight?.label).toBe('28 Nov')
  })

  it('refuses an empty or inverted window', () => {
    expect(timeAxisTicks(start, start, 900)).toEqual([])
    expect(timeAxisTicks(end, start, 900)).toEqual([])
  })
})

describe('objectInPane', () => {
  const pane = { width: 1000, height: 600 }

  it('culls a box panned past the right edge', () => {
    expect(
      objectInPane({ minX: 1100, maxX: 1300, minY: 100, maxY: 200 }, 'rectangle', pane.width, pane.height)
    ).toBe(false)
  })

  it('keeps a trendline that crosses the pane with both anchors outside it', () => {
    // Top-left of the pane to bottom-right, anchors beyond both corners.
    expect(
      objectInPane({ minX: -200, maxX: 1200, minY: -100, maxY: 700 }, 'trendline', pane.width, pane.height)
    ).toBe(true)
  })

  it('culls a trendline that is entirely above the pane', () => {
    expect(
      objectInPane({ minX: 100, maxX: 800, minY: -300, maxY: -50 }, 'trendline', pane.width, pane.height)
    ).toBe(false)
  })

  it('decides a horizontal line by its price, not by an anchor', () => {
    expect(objectInPane({ minX: 0, maxX: 0, minY: 700, maxY: 700 }, 'ray', pane.width, pane.height)).toBe(false)
    expect(objectInPane({ minX: 0, maxX: 0, minY: 300, maxY: 300 }, 'ray', pane.width, pane.height)).toBe(true)
  })

  it('decides a vertical line by its time', () => {
    expect(objectInPane({ minX: 1400, maxX: 1400, minY: 0, maxY: 0 }, 'vline', pane.width, pane.height)).toBe(false)
    expect(objectInPane({ minX: 400, maxX: 400, minY: 0, maxY: 0 }, 'vline', pane.width, pane.height)).toBe(true)
  })

  it('gives a text label its own box above the anchor', () => {
    // Anchored near the bottom of the pane, the words still sit inside it.
    expect(objectInPane({ minX: 200, maxX: 200, minY: 590, maxY: 590 }, 'text', pane.width, pane.height)).toBe(true)
    // Anchored below the pane, the label hangs outside it.
    expect(objectInPane({ minX: 200, maxX: 200, minY: 700, maxY: 700 }, 'text', pane.width, pane.height)).toBe(false)
  })
})
