import { describe, it, expect, vi } from 'vitest'
import { generateReview, prepareReview, statsFromSummary } from '@/lib/ai/review'
import type { ReviewRequest, TradeRecord } from '@/lib/ai/types'

function trades(count = 12): TradeRecord[] {
  return Array.from({ length: count }, (_, i) => {
    const day = String((i % 9) + 1).padStart(2, '0')
    return {
      symbol: i % 2 ? 'EURUSD' : 'GBPUSD',
      pnl: i % 3 === 0 ? -40 : 60,
      open_time: `2026-06-${day}T08:00:00.000Z`,
      close_time: `2026-06-${day}T09:00:00.000Z`,
      notes: i % 2 ? 'london breakout with momentum' : 'asian range chop',
    }
  })
}

const VALID = JSON.stringify({
  headline: 'Balanced edge with a Friday weakness.',
  confidence: 'medium',
  strengths: [{ title: 'Positive expectancy', detail: 'Overall expectancy is positive.', evidence: 'expectancy: 33' }],
  risks: [{ title: 'Losses cluster', detail: 'Losses are concentrated in a few days.' }],
  actions: [{ title: 'Review Fridays', detail: 'Tag trades by day and compare.' }],
})

describe('generateReview', () => {
  it('computes stats, calls the model once, and returns a normalized review', async () => {
    const complete = vi.fn().mockResolvedValue(VALID)
    const result = await generateReview({ trades: trades(12) }, { complete })

    expect(result.skipped).toBe(false)
    expect(result.review.headline).toContain('Balanced edge')
    expect(result.review.strengths).toHaveLength(1)
    expect(result.stats.trades).toBe(12)
    expect(complete).toHaveBeenCalledTimes(1)

    const [messages, options] = complete.mock.calls[0]
    expect(options).toEqual({ json: true })
    expect(messages).toHaveLength(2)
    expect(messages[0].role).toBe('system')
  })

  it('short-circuits without a model call when the sample is too small', async () => {
    const complete = vi.fn()
    const result = await generateReview({ trades: trades(2) }, { complete })

    expect(result.skipped).toBe(true)
    expect(result.review.confidence).toBe('low')
    expect(complete).not.toHaveBeenCalled()
  })

  it('works from the legacy summary fallback', async () => {
    const complete = vi.fn().mockResolvedValue(VALID)
    const result = await generateReview(
      { totalTrades: 40, totalPnl: 800, winRate: 55, symbols: [{ symbol: 'EURUSD', trades: 20, winRate: 60, pnl: 500 }] },
      { complete }
    )
    expect(result.skipped).toBe(false)
    expect(result.stats.trades).toBe(40)
    expect(result.stats.bySymbol[0].key).toBe('EURUSD')
  })

  it('propagates provider errors so the route can surface them', async () => {
    const complete = vi.fn().mockRejectedValue(new Error('provider down'))
    await expect(generateReview({ trades: trades(12) }, { complete })).rejects.toThrow('provider down')
  })
})

describe('prepareReview', () => {
  it('builds messages and includes an image part for vision input', () => {
    const prepared = prepareReview({
      trades: trades(12),
      question: 'Why do I lose on Fridays?',
      chartImage: 'data:image/png;base64,AAAA',
    })
    expect(prepared.skipped).toBe(false)
    expect(Array.isArray(prepared.messages[1].content)).toBe(true)
  })

  it('marks a too-small sample as skipped with an early review', () => {
    const prepared = prepareReview({ trades: trades(1) })
    expect(prepared.skipped).toBe(true)
    expect(prepared.earlyReview).toBeDefined()
    expect(prepared.messages).toEqual([])
  })
})

describe('statsFromSummary', () => {
  it('marks a small summary as insufficient', () => {
    const input: ReviewRequest = { totalTrades: 3, totalPnl: 10 }
    expect(statsFromSummary(input).insufficient).toBe(true)
  })
})
