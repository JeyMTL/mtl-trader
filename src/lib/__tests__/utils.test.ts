import { describe, it, expect } from 'vitest'
import { getPointValue, calculatePnL, formatCurrency, formatPercent } from '@/lib/utils'

describe('getPointValue', () => {
  it('classifies FX, JPY, metals, crypto and indices', () => {
    expect(getPointValue('EURUSD')).toBe(100000)
    expect(getPointValue('USDJPY')).toBe(1000)
    expect(getPointValue('XAUUSD')).toBe(100)
    expect(getPointValue('XAGUSD')).toBe(5000)
    expect(getPointValue('BTCUSD')).toBe(1)
    expect(getPointValue('US30')).toBe(1)
    expect(getPointValue('NAS100')).toBe(1)
    expect(getPointValue('USOIL')).toBe(1000)
  })

  it('ignores broker suffixes and case', () => {
    expect(getPointValue('eurusdm')).toBe(100000)
    expect(getPointValue('GBPUSDm')).toBe(100000)
  })
})

describe('calculatePnL', () => {
  it('computes a winning BUY in USD terms', () => {
    const pnl = calculatePnL({ type: 'BUY', symbol: 'EURUSD', entry_price: 1.1, exit_price: 1.11, lot_size: 1 })
    expect(pnl).toBeCloseTo(1000, 6)
  })

  it('computes a SELL in the opposite direction', () => {
    const pnl = calculatePnL({ type: 'SELL', symbol: 'EURUSD', entry_price: 1.1, exit_price: 1.09, lot_size: 0.1 })
    expect(pnl).toBeCloseTo(100, 6)
  })

  it('adds signed commission and swap (negative = cost)', () => {
    const pnl = calculatePnL({
      type: 'BUY', symbol: 'EURUSD', entry_price: 1.1, exit_price: 1.11, lot_size: 1,
      commission: -2, swap: -0.74,
    })
    expect(pnl).toBeCloseTo(997.26, 6)
  })

  it('handles JPY and metal point values', () => {
    expect(calculatePnL({ type: 'BUY', symbol: 'USDJPY', entry_price: 150.0, exit_price: 150.5, lot_size: 1 })).toBeCloseTo(500, 6)
    expect(calculatePnL({ type: 'BUY', symbol: 'XAUUSD', entry_price: 2000, exit_price: 2001, lot_size: 1 })).toBeCloseTo(100, 6)
  })
})

describe('formatters', () => {
  it('formats currency and percent', () => {
    expect(formatCurrency(1234.5)).toBe('$1,234.50')
    expect(formatCurrency(-5)).toBe('-$5.00')
    expect(formatPercent(62.5)).toBe('62.5%')
  })
})
