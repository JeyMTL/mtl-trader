import { describe, expect, it } from 'vitest'
import { buyAndHold } from '@/lib/backtest/benchmark'
import type { Bar, CostModel } from '@/lib/backtest/types'

const start = Date.UTC(2026, 9, 1)
const free: CostModel = { spread: 0, slippage: 0, commission: 0 }

function bars(prices: number[]): Bar[] {
  return prices.map((price, index) => ({
    time: start + index * 60_000,
    open: price,
    high: price,
    low: price,
    close: price,
  }))
}

describe('buy and hold', () => {
  it('returns the instrument move when nothing is charged', () => {
    const result = buyAndHold(bars([100, 105, 110]), 10_000, free)

    expect(result).not.toBeNull()
    expect(result!.returnPct).toBeCloseTo(10, 6)
    expect(result!.finalEquity).toBeCloseTo(11_000, 6)
    expect(result!.maxDrawdownPct).toBeCloseTo(0, 6)
  })

  it('charges spread, slippage and commission against the result', () => {
    const freeResult = buyAndHold(bars([100, 110]), 10_000, free)!
    const paid = buyAndHold(bars([100, 110]), 10_000, {
      spread: 0.4,
      slippage: 0.1,
      commission: 7,
    })!

    expect(paid.netPnl).toBeLessThan(freeResult.netPnl)
    expect(paid.returnPct).toBeLessThan(freeResult.returnPct)
  })

  it('measures drawdown from the peak of the curve, not from the entry', () => {
    const result = buyAndHold(bars([100, 120, 90, 110]), 10_000, free)!

    expect(result.maxDrawdownPct).toBeCloseTo(25, 6)
    expect(result.returnPct).toBeCloseTo(10, 6)
  })

  it('returns null when there is nothing to hold', () => {
    expect(buyAndHold(bars([100]), 10_000, free)).toBeNull()
    expect(buyAndHold(bars([100, 110]), 0, free)).toBeNull()
  })
})
