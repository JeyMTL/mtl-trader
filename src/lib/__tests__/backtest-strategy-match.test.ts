import { describe, expect, it } from 'vitest'
import { STRATEGIES, matchStrategyByLabel } from '@/lib/backtest/strategies'

describe('matchStrategyByLabel', () => {
  it('matches the canonical names and ids', () => {
    expect(matchStrategyByLabel('SMA cross')?.id).toBe('sma_cross')
    expect(matchStrategyByLabel('sma_cross')?.id).toBe('sma_cross')
    expect(matchStrategyByLabel('Donchian breakout')?.id).toBe('donchian_breakout')
    expect(matchStrategyByLabel('RSI reversion')?.id).toBe('rsi_reversion')
  })

  it('ignores case, spacing and punctuation', () => {
    expect(matchStrategyByLabel('  sma CROSS  ')?.id).toBe('sma_cross')
    expect(matchStrategyByLabel('donchian-breakout')?.id).toBe('donchian_breakout')
  })

  it('matches a distinctive fragment a trader would type', () => {
    expect(matchStrategyByLabel('breakout')?.id).toBe('donchian_breakout')
    expect(matchStrategyByLabel('RSI')?.id).toBe('rsi_reversion')
    expect(matchStrategyByLabel('SMA')?.id).toBe('sma_cross')
  })

  it('refuses labels it cannot resolve, instead of guessing', () => {
    expect(matchStrategyByLabel('Untagged')).toBeNull()
    expect(matchStrategyByLabel('martingale')).toBeNull()
    expect(matchStrategyByLabel('')).toBeNull()
    expect(matchStrategyByLabel('ab')).toBeNull()
    expect(matchStrategyByLabel('mean reversion scalper')).toBeNull()
  })

  it('resolves every built-in strategy from its own name', () => {
    for (const strategy of STRATEGIES) {
      expect(matchStrategyByLabel(strategy.name)?.id, strategy.name).toBe(strategy.id)
      expect(matchStrategyByLabel(strategy.id)?.id, strategy.id).toBe(strategy.id)
    }
  })
})
