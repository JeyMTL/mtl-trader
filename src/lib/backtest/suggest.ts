/**
 * Turning a journal entry into a backtest starting point.
 *
 * The model is given a trade's own notes and screenshots and answers one narrow
 * question: which of the fixed strategies, at which parameters, best expresses
 * what the trader says they saw? It never invents rules — it picks from a closed
 * menu, and every number it returns is clamped into that strategy's declared
 * range by `normalizeParams`. So a hallucinated `fast: 400` becomes the maximum
 * the slider allows, and an invented strategy id is rejected outright rather
 * than simulated.
 *
 * A screenshot is read here and nowhere else: the engine replays prices, and an
 * image carries none. This is the bridge between the two.
 */

import { extractJsonObject } from '@/lib/ai/schema'
import type { PromptMessage } from '@/lib/ai/types'
import { STRATEGIES, getStrategy, normalizeParams } from './strategies'

/** Two charts is plenty of evidence and twice the tokens of one. */
export const MAX_SUGGEST_IMAGES = 2
export const MAX_NOTES_CHARS = 1_500
export const MAX_REASONING_CHARS = 600

export const SUGGESTION_DISCLAIMER =
  'A starting point chosen by a model from your own notes and screenshots — not a validated edge, and not advice. Run it, then check the out-of-sample window before believing anything.'

export type SuggestionConfidence = 'low' | 'medium' | 'high'

/** The trade fields the suggestion actually reasons over. */
export interface SuggestionTrade {
  symbol?: string | null
  type?: string | null
  timeframe?: string | null
  strategy?: string | null
  notes?: string | null
  tags?: string[] | null
  pnl?: number | null
  close_time?: string | null
}

export interface StrategySuggestion {
  strategyId: string
  name: string
  /** Clamped to the strategy's declared ranges — safe to run as-is. */
  params: Record<string, number>
  reasoning: string
  confidence: SuggestionConfidence
  /** How many screenshots the model actually received. */
  imagesRead: number
  disclaimer: string
}

export const SUGGESTION_JSON_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['strategyId', 'params', 'reasoning', 'confidence'],
  properties: {
    strategyId: {
      type: 'string',
      enum: STRATEGIES.map((strategy) => strategy.id),
      description: 'The id of the strategy whose rules are closest to the trader’s description.',
    },
    params: {
      type: 'object',
      description: 'Every parameter of the chosen strategy, inside its allowed range.',
      additionalProperties: { type: 'number' },
    },
    reasoning: {
      type: 'string',
      description: 'Two sentences tying the chosen rules to the notes and the chart, if one was attached.',
    },
    confidence: { type: 'string', enum: ['low', 'medium', 'high'] },
  },
} as const

/** The menu, with each parameter's range, so the model can only pick legal values. */
export function strategyCatalog(): string {
  return STRATEGIES.map((strategy) => {
    const params = strategy.params
      .map((spec) => `${spec.key} ${spec.min}–${spec.max} (default ${spec.defaultValue})`)
      .join(', ')
    return `- ${strategy.id} — ${strategy.name}: ${strategy.description} Parameters: ${params}`
  }).join('\n')
}

function noteBlock(trade: SuggestionTrade): string {
  const notes = (trade.notes ?? '').trim()
  if (!notes) {
    return 'The trader wrote no note for this trade. Say so plainly and keep your confidence low.'
  }
  return `The trader’s own note:\n${notes.slice(0, MAX_NOTES_CHARS)}`
}

function describeTrade(trade: SuggestionTrade): string {
  const rows = [
    `Symbol: ${trade.symbol || 'unknown'}`,
    `Timeframe: ${trade.timeframe || 'unknown'}`,
    `Side: ${trade.type || 'unknown'}`,
    `Strategy label typed in the journal: ${(trade.strategy || '').trim() || '(none)'}`,
    `Result: ${Number(trade.pnl ?? 0).toFixed(2)}`,
  ]
  if (trade.tags?.length) rows.push(`Tags: ${trade.tags.join(', ')}`)
  if (trade.close_time) rows.push(`Closed: ${trade.close_time.slice(0, 10)}`)
  return rows.join('\n')
}

export function buildSuggestionMessages(
  trade: SuggestionTrade,
  images: string[] = []
): PromptMessage[] {
  const system = [
    'You translate a trader’s own written reasoning into the closest rule set a backtester can simulate.',
    'You are not judging the trade, not predicting the market, and not promising that these rules are profitable.',
    'Choose exactly one strategy from this fixed menu, by id:',
    strategyCatalog(),
    images.length > 0
      ? `${images.length} chart screenshot(s) are attached. Describe only what is visible — trend or range, candle size, where price rejected — and say so if the image is unclear or is not a chart.`
      : 'No screenshot is attached; work from the written note alone.',
    'Every parameter must sit inside its stated range. Prefer conventional round values over invented precision.',
    'If the note describes something none of these strategies do (news, order flow, discretionary management), say that in the reasoning and pick the closest strategy anyway, with low confidence.',
    'Reply with a single JSON object and nothing else, matching this shape:',
    JSON.stringify({
      strategyId: 'one of the ids above',
      params: { parameter: 0 },
      reasoning: 'two sentences grounded in the note and the screenshot',
      confidence: 'low | medium | high',
    }),
  ].join('\n')

  const user = `${describeTrade(trade)}\n\n${noteBlock(trade)}\n\nReturn the JSON object now.`

  if (images.length > 0) {
    return [
      { role: 'system', content: system },
      {
        role: 'user',
        content: [
          { type: 'text', text: user },
          ...images.map((dataUrl) => ({ type: 'image' as const, dataUrl })),
        ],
      },
    ]
  }

  return [
    { role: 'system', content: system },
    { role: 'user', content: user },
  ]
}

function asString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : ''
}

function toConfidence(value: unknown): SuggestionConfidence {
  return value === 'high' || value === 'medium' ? value : 'low'
}

/**
 * Parse the model reply into something runnable.
 *
 * Throws a message the route can show as-is when the reply is unusable, because
 * a silent fallback to default parameters would look like the model's answer and
 * be trusted as one.
 */
export function normalizeSuggestion(raw: unknown, imagesRead = 0): StrategySuggestion {
  const text = typeof raw === 'string' ? raw : JSON.stringify(raw)
  const json = typeof raw === 'string' ? extractJsonObject(text) : text
  if (!json) {
    throw new Error('The suggestion did not come back as JSON. Try again.')
  }

  let parsed: Record<string, unknown>
  try {
    parsed = JSON.parse(json) as Record<string, unknown>
  } catch {
    throw new Error('The suggestion contained invalid JSON. Try again.')
  }

  const definition = getStrategy(asString(parsed.strategyId))
  if (!definition) {
    throw new Error('The suggestion named a strategy this backtester does not have. Try again.')
  }

  const params = normalizeParams(definition, parsed.params)
  const reasoning = asString(parsed.reasoning).slice(0, MAX_REASONING_CHARS)

  return {
    strategyId: definition.id,
    name: definition.name,
    params,
    reasoning: reasoning || 'The model chose these rules without explaining why.',
    confidence: toConfidence(parsed.confidence),
    imagesRead,
    disclaimer: SUGGESTION_DISCLAIMER,
  }
}
