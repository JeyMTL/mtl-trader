import { describe, it, expect } from 'vitest'
import {
  buildIdf,
  buildQueryFromTrades,
  collectNoteDocs,
  cosineSimilarity,
  findSimilarNotes,
  tfidfVector,
  tokenize,
} from '@/lib/ai/retrieval'
import type { TradeRecord } from '@/lib/ai/types'

describe('tokenize', () => {
  it('lowercases, strips punctuation, and drops stopwords/short tokens', () => {
    expect(tokenize('Breakout of THE London range!!')).toEqual(['breakout', 'london', 'range'])
  })

  it('returns an empty array for empty or symbol-only text', () => {
    expect(tokenize('')).toEqual([])
    expect(tokenize('a an the')).toEqual([])
  })
})

describe('cosineSimilarity', () => {
  it('is 1 for identical vectors and 0 for no shared terms', () => {
    const a = new Map([['breakout', 1], ['london', 1]])
    const b = new Map([['breakout', 1], ['london', 1]])
    const c = new Map([['asian', 1]])
    expect(cosineSimilarity(a, b)).toBeCloseTo(1, 6)
    expect(cosineSimilarity(a, c)).toBe(0)
  })

  it('is 0 when either vector is empty', () => {
    expect(cosineSimilarity(new Map(), new Map([['x', 1]]))).toBe(0)
  })
})

describe('collectNoteDocs', () => {
  it('keeps only trades with usable notes and records their outcome', () => {
    const trades: TradeRecord[] = [
      { pnl: 10, notes: 'london breakout' },
      { pnl: -5, notes: '   ' },
      { pnl: 20 },
      { pnl: 3, notes: 'a the' },
    ]
    const docs = collectNoteDocs(trades)
    expect(docs).toHaveLength(1)
    expect(docs[0].outcome).toBe(10)
  })
})

describe('buildIdf / tfidfVector', () => {
  it('weights rarer terms more heavily', () => {
    const docs = [['breakout', 'london'], ['breakout', 'asian'], ['breakout', 'range']]
    const idf = buildIdf(docs)
    expect(idf.get('london')).toBeGreaterThan(idf.get('breakout') as number)
    const vector = tfidfVector(['breakout', 'london'], idf)
    expect(vector.get('london')).toBeGreaterThan(vector.get('breakout') as number)
  })
})

describe('findSimilarNotes', () => {
  const trades: TradeRecord[] = [
    { pnl: 100, notes: 'London breakout with momentum', close_time: '2026-06-01T09:00:00Z' },
    { pnl: -50, notes: 'Asian range scalp, choppy', close_time: '2026-06-02T02:00:00Z' },
    { pnl: 20, notes: 'London breakout retest, patient', close_time: '2026-06-03T09:00:00Z' },
  ]

  it('ranks notes matching the query first', () => {
    const results = findSimilarNotes(trades, 'london breakout', 2)
    expect(results).toHaveLength(2)
    expect(results[0].note.toLowerCase()).toContain('breakout')
    expect(results[0].score).toBeGreaterThan(0)
  })

  it('returns nothing for an empty or unmatched query', () => {
    expect(findSimilarNotes(trades, '')).toEqual([])
    expect(findSimilarNotes(trades, 'zzzz qqqq')).toEqual([])
  })
})

describe('buildQueryFromTrades', () => {
  it('combines recent notes, strategy and symbol', () => {
    const query = buildQueryFromTrades([
      { pnl: 1, notes: 'patient entry', strategy: 'breakout', symbol: 'EURUSD' },
    ])
    expect(query).toContain('patient entry')
    expect(query).toContain('breakout')
    expect(query).toContain('EURUSD')
  })
})
