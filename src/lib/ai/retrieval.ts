/**
 * Lightweight retrieval over the user's own trade notes (a "poor man's RAG").
 *
 * Uses TF-IDF + cosine similarity instead of embeddings so it needs no extra
 * API, no vector database, and stays fully unit-testable. If embeddings are
 * added later, only this module's ranking changes.
 */

import type { TradeRecord } from './types'
import { tradePnl, tradeTime } from './edge-stats'

const STOPWORDS = new Set([
  'the', 'and', 'for', 'was', 'were', 'with', 'this', 'that', 'then', 'than',
  'but', 'not', 'had', 'has', 'have', 'into', 'out', 'got', 'get', 'did',
  'so', 'it', 'its', 'as', 'at', 'on', 'in', 'to', 'of', 'a', 'an', 'is',
  'i', 'my', 'me', 'we', 'he', 'she', 'they', 'you', 'very', 'just', 'after',
  'before', 'when', 'while', 'because', 'would', 'could', 'should', 'been',
])

export function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((token) => token.length >= 3 && !STOPWORDS.has(token))
}

export interface NoteDoc {
  note: string
  tokens: string[]
  outcome: number
  when: string | null
}

export function collectNoteDocs(trades: TradeRecord[]): NoteDoc[] {
  const docs: NoteDoc[] = []
  for (const trade of trades) {
    const note = (trade.notes || '').trim()
    if (!note) continue
    const tokens = tokenize(note)
    if (tokens.length === 0) continue
    docs.push({ note, tokens, outcome: tradePnl(trade), when: tradeTime(trade) })
  }
  return docs
}

/** Inverse document frequency across note documents (smoothed). */
export function buildIdf(docs: string[][]): Map<string, number> {
  const df = new Map<string, number>()
  for (const tokens of docs) {
    for (const token of new Set(tokens)) df.set(token, (df.get(token) || 0) + 1)
  }
  const idf = new Map<string, number>()
  const total = docs.length || 1
  for (const [token, count] of df) idf.set(token, Math.log((total + 1) / (count + 1)) + 1)
  return idf
}

export function tfidfVector(tokens: string[], idf: Map<string, number>): Map<string, number> {
  const tf = new Map<string, number>()
  for (const token of tokens) tf.set(token, (tf.get(token) || 0) + 1)
  const vector = new Map<string, number>()
  const length = tokens.length || 1
  for (const [token, count] of tf) {
    if (!idf.has(token)) continue
    vector.set(token, (count / length) * (idf.get(token) || 0))
  }
  return vector
}

export function cosineSimilarity(a: Map<string, number>, b: Map<string, number>): number {
  if (a.size === 0 || b.size === 0) return 0
  let dot = 0
  let normA = 0
  let normB = 0
  for (const value of a.values()) normA += value * value
  for (const value of b.values()) normB += value * value
  const [small, large] = a.size <= b.size ? [a, b] : [b, a]
  for (const [token, value] of small) {
    const other = large.get(token)
    if (other) dot += value * other
  }
  const denom = Math.sqrt(normA) * Math.sqrt(normB)
  return denom === 0 ? 0 : dot / denom
}

export interface SimilarNote {
  note: string
  outcome: number
  when: string | null
  score: number
}

/** Build a retrieval query from recent trades' notes, strategy and symbols. */
export function buildQueryFromTrades(trades: TradeRecord[], limit = 8): string {
  const parts: string[] = []
  for (const trade of trades.slice(-limit)) {
    if (trade.notes) parts.push(trade.notes)
    if (trade.strategy) parts.push(trade.strategy)
    if (trade.symbol) parts.push(trade.symbol)
  }
  return parts.join(' ')
}

/** Top-k notes most similar to `query`, excluding the query's own trades. */
export function findSimilarNotes(
  trades: TradeRecord[],
  query: string,
  k = 5
): SimilarNote[] {
  const queryTokens = tokenize(query)
  if (queryTokens.length === 0) return []

  const docs = collectNoteDocs(trades)
  if (docs.length === 0) return []

  const idf = buildIdf(docs.map((doc) => doc.tokens))
  const queryVector = tfidfVector(queryTokens, idf)
  if (queryVector.size === 0) return []

  return docs
    .map((doc) => ({
      note: doc.note.slice(0, 300),
      outcome: doc.outcome,
      when: doc.when,
      score: cosineSimilarity(queryVector, tfidfVector(doc.tokens, idf)),
    }))
    .filter((item) => item.score > 0.05)
    .sort((a, b) => b.score - a.score)
    .slice(0, k)
}
