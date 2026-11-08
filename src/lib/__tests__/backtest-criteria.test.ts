import { describe, expect, it } from 'vitest'
import {
  MAX_COMPILE_CRITERIA,
  MAX_COMPILE_IMAGES,
  buildCompileMessages,
  normalizeCriteria,
} from '@/lib/backtest/rules'

const BASE = {
  description: 'wait for the sweep, then enter when a bullish candle closes back above it',
  timeframe: 'M15',
}

describe('normalizeCriteria', () => {
  it('keeps the words, strips control characters and trims', () => {
    expect(normalizeCriteria('  gap\u0000 only  ')).toBe('gap  only')
  })

  it('caps the length, because it is billed on every compile', () => {
    expect(normalizeCriteria('x'.repeat(5_000)).length).toBe(MAX_COMPILE_CRITERIA)
  })

  it('ignores anything that is not text', () => {
    expect(normalizeCriteria(null)).toBe('')
    expect(normalizeCriteria({ text: 'x' })).toBe('')
  })
})

describe('buildCompileMessages with standing criteria', () => {
  it('carries the criteria into both the instructions and the request', () => {
    const messages = buildCompileMessages({ ...BASE, criteria: 'only if the gap is wider than ATR' })
    const system = String(messages[0]?.content)
    const user = String(messages[1]?.content)

    expect(system).toContain('standing definition')
    // The model has to name what it could not encode, not quietly drop it.
    expect(system).toContain('never dropped silently')
    expect(user).toContain('standing acceptance criteria')
    expect(user).toContain('only if the gap is wider than ATR')
  })

  it('leaves the prompt untouched when there are none', () => {
    const messages = buildCompileMessages({ ...BASE, criteria: '   ' })
    expect(String(messages[0]?.content)).not.toContain('standing definition')
    expect(String(messages[1]?.content)).not.toContain('standing acceptance criteria')
  })

  it('allows four charts so a valid and a rejected example both fit', () => {
    expect(MAX_COMPILE_IMAGES).toBe(4)
  })
})
