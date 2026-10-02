import { describe, it, expect } from 'vitest'
import {
  DISCLAIMER,
  MAX_FINDINGS,
  extractJsonObject,
  insufficientDataReview,
  normalizeReview,
} from '@/lib/ai/schema'
import type { EdgeStats } from '@/lib/ai/types'

function stats(overrides: Partial<EdgeStats> = {}): EdgeStats {
  return {
    trades: 25,
    wins: 15,
    losses: 10,
    winRate: 60,
    pnl: 500,
    grossWins: 900,
    grossLosses: 400,
    profitFactor: 2.25,
    expectancy: 20,
    avgWin: 60,
    avgLoss: -40,
    best: 150,
    worst: -90,
    maxWinStreak: 4,
    maxLossStreak: 3,
    currentStreak: 1,
    bySymbol: [],
    bySession: [],
    byWeekday: [],
    byHoldTime: [],
    noteCount: 5,
    insufficient: false,
    minSample: 10,
    ...overrides,
  }
}

describe('extractJsonObject', () => {
  it('pulls the first balanced object out of surrounding prose', () => {
    expect(extractJsonObject('Sure! {"a":1} hope that helps')).toBe('{"a":1}')
  })

  it('handles nested braces and braces inside strings', () => {
    const text = 'x {"a":{"b":2},"c":"}{"} tail'
    expect(extractJsonObject(text)).toBe('{"a":{"b":2},"c":"}{"}')
  })

  it('returns null when there is no object', () => {
    expect(extractJsonObject('no json here')).toBeNull()
  })
})

describe('normalizeReview', () => {
  it('coerces a valid response and caps the finding lists', () => {
    const many = Array.from({ length: 8 }, (_, i) => ({ title: `t${i}`, detail: `d${i}` }))
    const review = normalizeReview(
      JSON.stringify({
        headline: 'Solid edge but risk management drags.',
        confidence: 'high',
        strengths: many,
        risks: [],
        actions: [{ title: 'Journal more', detail: 'Add notes to every trade.' }],
      }),
      stats()
    )
    expect(review.headline).toContain('Solid edge')
    expect(review.confidence).toBe('high')
    expect(review.strengths).toHaveLength(MAX_FINDINGS)
    expect(review.actions[0].title).toBe('Journal more')
    expect(review.sampleSize).toBe(25)
    expect(review.disclaimer).toBe(DISCLAIMER)
  })

  it('drops malformed findings and defaults bad confidence to low', () => {
    const review = normalizeReview(
      JSON.stringify({
        headline: 'x',
        confidence: 'extreme',
        strengths: [{ title: 'ok', detail: 'fine' }, { title: '', detail: 'no title' }, 'nope'],
        risks: 'not-an-array',
      }),
      stats()
    )
    expect(review.strengths).toHaveLength(1)
    expect(review.risks).toEqual([])
    expect(review.confidence).toBe('low')
  })

  it('forces low confidence when the sample is insufficient', () => {
    const review = normalizeReview(
      JSON.stringify({ headline: 'x', confidence: 'high', strengths: [], risks: [], actions: [] }),
      stats({ insufficient: true })
    )
    expect(review.confidence).toBe('low')
  })

  it('falls back to the supplied similar setups when the model omits them', () => {
    const review = normalizeReview(
      JSON.stringify({ headline: 'x', strengths: [], risks: [], actions: [] }),
      stats(),
      [{ note: 'london breakout', outcome: 50, when: null, score: 0.5 }]
    )
    expect(review.similarSetups[0].note).toBe('london breakout')
  })

  it('throws when the response is not usable JSON', () => {
    expect(() => normalizeReview('no json', stats())).toThrow()
    expect(() => normalizeReview('{bad json', stats())).toThrow()
  })
})

describe('insufficientDataReview', () => {
  it('explains the sample is too small without calling a model', () => {
    const review = insufficientDataReview(stats({ trades: 3, insufficient: true }))
    expect(review.confidence).toBe('low')
    expect(review.risks[0].title).toMatch(/sample/i)
    expect(review.actions).toHaveLength(1)
  })
})
