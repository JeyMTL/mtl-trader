/**
 * Structured-output contract for AI reviews: the JSON schema we request, a
 * tolerant extractor, and a strict normalizer. Validating in code (not just the
 * prompt) is what lets the result drive the UI reliably.
 */

import type { Confidence, EdgeStats, ReviewFinding, ReviewResult, SimilarSetup } from './types'

export const MAX_FINDINGS = 5
export const DISCLAIMER =
  'AI feedback is educational, generated from your own journal statistics, and is not financial advice.'

export const REVIEW_JSON_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['headline', 'confidence', 'strengths', 'risks', 'actions'],
  properties: {
    headline: { type: 'string', description: 'One-sentence summary grounded in the stats.' },
    confidence: { type: 'string', enum: ['low', 'medium', 'high'] },
    strengths: {
      type: 'array',
      maxItems: MAX_FINDINGS,
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['title', 'detail'],
        properties: {
          title: { type: 'string' },
          detail: { type: 'string' },
          evidence: { type: 'string' },
        },
      },
    },
    risks: { type: 'array', maxItems: MAX_FINDINGS, items: { $ref: '#/properties/strengths/items' } },
    actions: { type: 'array', maxItems: MAX_FINDINGS, items: { $ref: '#/properties/strengths/items' } },
  },
} as const

/** Pull the first balanced JSON object out of a model response. */
export function extractJsonObject(text: string): string | null {
  const start = text.indexOf('{')
  if (start === -1) return null
  let depth = 0
  let inString = false
  let escaped = false
  for (let i = start; i < text.length; i++) {
    const char = text[i]
    if (inString) {
      if (escaped) escaped = false
      else if (char === '\\') escaped = true
      else if (char === '"') inString = false
      continue
    }
    if (char === '"') inString = true
    else if (char === '{') depth++
    else if (char === '}') {
      depth--
      if (depth === 0) return text.slice(start, i + 1)
    }
  }
  return null
}

function asString(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value.trim() : fallback
}

function toConfidence(value: unknown): Confidence {
  return value === 'high' || value === 'medium' || value === 'low' ? value : 'low'
}

function toFindings(value: unknown): ReviewFinding[] {
  if (!Array.isArray(value)) return []
  return value
    .map((item): ReviewFinding | null => {
      if (!item || typeof item !== 'object') return null
      const record = item as Record<string, unknown>
      const title = asString(record.title)
      const detail = asString(record.detail)
      if (!title || !detail) return null
      const evidence = asString(record.evidence)
      return evidence ? { title, detail, evidence } : { title, detail }
    })
    .filter((item): item is ReviewFinding => item !== null)
    .slice(0, MAX_FINDINGS)
}

function toSimilarSetups(value: unknown): SimilarSetup[] {
  if (!Array.isArray(value)) return []
  return value
    .map((item): SimilarSetup | null => {
      if (!item || typeof item !== 'object') return null
      const record = item as Record<string, unknown>
      const note = asString(record.note)
      if (!note) return null
      return {
        note: note.slice(0, 300),
        outcome: Number(record.outcome) || 0,
        when: typeof record.when === 'string' ? record.when : null,
        score: Number(record.score) || 0,
      }
    })
    .filter((item): item is SimilarSetup => item !== null)
    .slice(0, MAX_FINDINGS)
}

/**
 * Parse and normalize a raw model response into a `ReviewResult`.
 * Throws when the response is not usable JSON.
 */
export function normalizeReview(
  raw: unknown,
  stats: EdgeStats,
  similarSetups: SimilarSetup[] = []
): ReviewResult {
  const text = typeof raw === 'string' ? raw : JSON.stringify(raw)
  const json = typeof raw === 'string' ? extractJsonObject(text) : text
  if (!json) throw new Error('AI response did not contain a JSON object')

  let parsed: Record<string, unknown>
  try {
    parsed = JSON.parse(json) as Record<string, unknown>
  } catch {
    throw new Error('AI response contained invalid JSON')
  }

  const headline = asString(parsed.headline) || 'Journal review'
  return {
    headline: headline.slice(0, 240),
    confidence: stats.insufficient ? 'low' : toConfidence(parsed.confidence),
    sampleSize: stats.trades,
    strengths: toFindings(parsed.strengths),
    risks: toFindings(parsed.risks),
    actions: toFindings(parsed.actions),
    similarSetups: toSimilarSetups(parsed.similarSetups).length
      ? toSimilarSetups(parsed.similarSetups)
      : similarSetups,
    disclaimer: DISCLAIMER,
  }
}

/** Deterministic fallback when there is too little data to ask the model. */
export function insufficientDataReview(stats: EdgeStats): ReviewResult {
  return {
    headline: `Only ${stats.trades} trade${stats.trades === 1 ? '' : 's'} on record — too little to judge an edge.`,
    confidence: 'low',
    sampleSize: stats.trades,
    strengths: [],
    risks: [
      {
        title: 'Sample too small',
        detail: `A meaningful review usually needs at least ${stats.minSample} trades. Keep journaling and no dramatic conclusions should be drawn yet.`,
        evidence: `${stats.trades}/${stats.minSample} trades`,
      },
    ],
    actions: [
      {
        title: 'Keep recording',
        detail: 'Log every trade with a short note so patterns and outcomes can be compared later.',
      },
    ],
    similarSetups: [],
    disclaimer: DISCLAIMER,
  }
}
