import { describe, expect, it } from 'vitest'
import {
  MAX_REASONING_CHARS,
  SUGGESTION_JSON_SCHEMA,
  buildSuggestionMessages,
  normalizeSuggestion,
  strategyCatalog,
} from '@/lib/backtest/suggest'
import { STRATEGIES, getStrategy } from '@/lib/backtest/strategies'

const trade = {
  symbol: 'EURUSD',
  type: 'buy',
  timeframe: 'M5',
  strategy: 'SMA cross',
  notes: 'Price kept rejecting 1.0850 and the fast average turned up right after London opened.',
  tags: ['rejection'],
  pnl: 120,
  close_time: '2026-10-14T09:12:00.000Z',
}

describe('suggestion prompt', () => {
  it('lists every strategy with its legal parameter ranges', () => {
    const catalog = strategyCatalog()
    for (const strategy of STRATEGIES) {
      expect(catalog).toContain(strategy.id)
      for (const spec of strategy.params) {
        expect(catalog).toContain(`${spec.key} ${spec.min}–${spec.max}`)
      }
    }
  })

  it('carries the note and the trade fields into the prompt', () => {
    const messages = buildSuggestionMessages(trade)
    const user = messages.find((message) => message.role === 'user')
    expect(typeof user?.content).toBe('string')
    const text = user?.content as string
    expect(text).toContain('EURUSD')
    expect(text).toContain('1.0850')
    expect(text).toContain('M5')
  })

  it('says so plainly when there is no note', () => {
    const messages = buildSuggestionMessages({ ...trade, notes: null })
    const text = messages.find((message) => message.role === 'user')?.content as string
    expect(text).toMatch(/wrote no note/i)
  })

  it('attaches screenshots as image parts only when they exist', () => {
    const withImage = buildSuggestionMessages(trade, ['data:image/png;base64,AAA'])
    const user = withImage.find((message) => message.role === 'user')
    expect(Array.isArray(user?.content)).toBe(true)
    const parts = user?.content as Array<{ type: string }>
    expect(parts.map((part) => part.type)).toEqual(['text', 'image'])

    const without = buildSuggestionMessages(trade)
    expect(typeof without.find((message) => message.role === 'user')?.content).toBe('string')
  })

  it('never promises the rules are profitable', () => {
    const system = buildSuggestionMessages(trade).find((message) => message.role === 'system')
    expect(system?.content as string).toMatch(/not promising that these rules are profitable/i)
  })
})

describe('normalizeSuggestion', () => {
  it('clamps every parameter into the strategy range', () => {
    const suggestion = normalizeSuggestion({
      strategyId: 'sma_cross',
      params: { fast: 400, slow: 1, atrPeriod: 0, stopAtr: 99, targetAtr: -5 },
      reasoning: 'Trend continuation after a pullback.',
      confidence: 'medium',
    })

    const definition = getStrategy('sma_cross')!
    for (const spec of definition.params) {
      expect(suggestion.params[spec.key], spec.key).toBeGreaterThanOrEqual(spec.min)
      expect(suggestion.params[spec.key], spec.key).toBeLessThanOrEqual(spec.max)
    }
    expect(suggestion.strategyId).toBe('sma_cross')
    expect(suggestion.name).toBe(definition.name)
    expect(suggestion.confidence).toBe('medium')
  })

  it('fills missing parameters with the declared defaults', () => {
    const suggestion = normalizeSuggestion({
      strategyId: 'rsi_reversion',
      params: { period: 9 },
      reasoning: 'Mean reversion.',
      confidence: 'low',
    })
    const definition = getStrategy('rsi_reversion')!
    for (const spec of definition.params) {
      if (spec.key === 'period') expect(suggestion.params.period).toBe(9)
      else expect(suggestion.params[spec.key]).toBe(spec.defaultValue)
    }
  })

  it('drops parameters the strategy does not have', () => {
    const suggestion = normalizeSuggestion({
      strategyId: 'donchian_breakout',
      params: { lookback: 20, fast: 9, slow: 200, nonsense: 1 },
      reasoning: 'Range breakout.',
      confidence: 'high',
    })
    expect(Object.keys(suggestion.params).sort()).toEqual(
      getStrategy('donchian_breakout')!.params.map((spec) => spec.key).sort()
    )
  })

  it('refuses a strategy id the engine cannot run', () => {
    expect(() =>
      normalizeSuggestion({
        strategyId: 'martingale',
        params: {},
        reasoning: 'Doubling down.',
        confidence: 'high',
      })
    ).toThrow(/does not have/)
  })

  it('refuses a reply that is not JSON', () => {
    expect(() => normalizeSuggestion('I would buy here.')).toThrow(/JSON/)
    expect(() => normalizeSuggestion('{"strategyId": ')).toThrow(/JSON/)
  })

  it('accepts a fenced reply and keeps the reasoning', () => {
    const suggestion = normalizeSuggestion(
      '```json\n{"strategyId":"sma_cross","params":{"fast":20,"slow":50},"reasoning":"Fast crossed up.","confidence":"low"}\n```'
    )
    expect(suggestion.reasoning).toBe('Fast crossed up.')
    expect(suggestion.confidence).toBe('low')
  })

  it('caps the reasoning and substitutes one when it is empty', () => {
    const long = normalizeSuggestion({
      strategyId: 'sma_cross',
      params: {},
      reasoning: 'x'.repeat(MAX_REASONING_CHARS + 200),
      confidence: 'low',
    })
    expect(long.reasoning).toHaveLength(MAX_REASONING_CHARS)

    const empty = normalizeSuggestion({
      strategyId: 'sma_cross',
      params: {},
      reasoning: '   ',
      confidence: 'unknown',
    })
    expect(empty.reasoning).toMatch(/without explaining/i)
    expect(empty.confidence).toBe('low')
  })

  it('records how many screenshots were read and always carries the disclaimer', () => {
    const suggestion = normalizeSuggestion(
      {
        strategyId: 'sma_cross',
        params: {},
        reasoning: 'Chart shows a break of the range.',
        confidence: 'medium',
      },
      2
    )
    expect(suggestion.imagesRead).toBe(2)
    expect(suggestion.disclaimer).toMatch(/not a validated edge/i)
  })
})

describe('suggestion schema', () => {
  it('only offers ids the engine can resolve', () => {
    const ids = SUGGESTION_JSON_SCHEMA.properties.strategyId.enum
    for (const id of ids) expect(getStrategy(id), id).not.toBeNull()
    expect(ids).toHaveLength(STRATEGIES.length)
  })
})
