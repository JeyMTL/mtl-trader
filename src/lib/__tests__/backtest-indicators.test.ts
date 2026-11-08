import { describe, expect, it } from 'vitest'
import { ema, macd } from '@/lib/backtest/indicators'

describe('MACD', () => {
  it('uses the conventional 12/26/9 lengths at the default slow period', () => {
    const values = Array.from({ length: 120 }, (_, index) =>
      100 + Math.sin(index / 4) * 6 + Math.cos(index / 11) * 2
    )

    const fast = ema(values, 12)
    const slow = ema(values, 26)
    const expectedLine = values.map((_, index) => {
      const f = fast[index]
      const s = slow[index]
      return f == null || s == null ? null : f - s
    })
    const expectedSignal = ema(
      expectedLine.map((value) => value ?? 0),
      9
    )

    const result = macd(values, 26)

    expect(result.macd).toEqual(expectedLine)
    expect(result.signal).toEqual(expectedSignal)
  })
})
