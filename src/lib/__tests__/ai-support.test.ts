import { describe, it, expect, vi } from 'vitest'
import { hashPayload, stableStringify } from '@/lib/ai/cache'
import { compareOutcome } from '@/lib/ai/outcomes'
import { mergeTags, suggestTags } from '@/lib/ai/autotag'
import { createProvider, parseDataUrl, resolveProviderConfig } from '@/lib/ai/providers'
import type { TradeRecord } from '@/lib/ai/types'

describe('cache hashing', () => {
  it('is independent of object key order', () => {
    expect(hashPayload({ a: 1, b: 2 })).toBe(hashPayload({ b: 2, a: 1 }))
  })

  it('is sensitive to array order and values', () => {
    expect(hashPayload([1, 2])).not.toBe(hashPayload([2, 1]))
    expect(stableStringify({ a: undefined, b: 1 })).toBe('{"b":1}')
  })
})

describe('compareOutcome', () => {
  it('splits trades before and after the review and reports improvement', () => {
    const reviewedAt = new Date('2026-06-10T00:00:00Z')
    const trades: TradeRecord[] = [
      { pnl: 100, close_time: '2026-06-01T10:00:00Z' },
      { pnl: -50, close_time: '2026-06-02T10:00:00Z' },
      { pnl: 80, close_time: '2026-06-11T10:00:00Z' },
      { pnl: 60, close_time: '2026-06-12T10:00:00Z' },
    ]
    const result = compareOutcome(trades, reviewedAt)
    expect(result.beforeTrades).toBe(2)
    expect(result.afterTrades).toBe(2)
    expect(result.beforeWinRate).toBe(50)
    expect(result.afterWinRate).toBe(100)
    expect(result.winRateDelta).toBe(50)
    expect(result.improved).toBe(true)
  })

  it('treats trades without timestamps as recent', () => {
    const result = compareOutcome([{ pnl: 5 }], new Date('2026-06-10T00:00:00Z'))
    expect(result.afterTrades).toBe(1)
  })
})

describe('auto-tagging', () => {
  it('suggests tags from note keywords', () => {
    const tags = suggestTags('London breakout, stayed patient and followed the plan')
    expect(tags).toContain('breakout')
    expect(tags).toContain('patient')
    expect(tags).toContain('plan-followed')
    expect(tags).toContain('london-session')
  })

  it('returns nothing for empty notes and caps the count', () => {
    expect(suggestTags('')).toEqual([])
    expect(suggestTags('breakout pullback reversal range trend momentum scalp', 3)).toHaveLength(3)
  })

  it('merges and de-duplicates tags', () => {
    expect(mergeTags(['Breakout'], ['breakout', 'scalp'], 5)).toEqual(['breakout', 'scalp'])
  })
})

describe('resolveProviderConfig', () => {
  it('returns null when nothing is configured', () => {
    expect(resolveProviderConfig({})).toBeNull()
  })

  it('selects OpenAI by default when an OpenAI key exists', () => {
    const config = resolveProviderConfig({ OPENAI_API_KEY: 'k' })
    expect(config?.provider).toBe('openai')
    expect(config?.model).toBe('gpt-4o-mini')
  })

  it('selects Anthropic when only that key exists', () => {
    const config = resolveProviderConfig({ ANTHROPIC_API_KEY: 'k' })
    expect(config?.provider).toBe('anthropic')
    expect(config?.baseUrl).toContain('anthropic')
  })

  it('honors an explicit provider, base URL, and model', () => {
    const config = resolveProviderConfig({
      AI_PROVIDER: 'openai-compatible',
      AI_API_KEY: 'k',
      AI_BASE_URL: 'https://llm.example.com/v1',
      AI_MODEL: 'custom-model',
    })
    expect(config?.provider).toBe('openai-compatible')
    expect(config?.baseUrl).toBe('https://llm.example.com/v1')
    expect(config?.model).toBe('custom-model')
  })
})

describe('createProvider (openai)', () => {
  const config = {
    provider: 'openai' as const,
    apiKey: 'key',
    baseUrl: 'https://api.example.com/v1',
    model: 'text-model',
    visionModel: 'vision-model',
  }

  it('returns the assistant content on success', async () => {
    const fakeFetch = vi.fn<(url: string, init?: RequestInit) => Promise<Response>>(
      async () => new Response(JSON.stringify({ choices: [{ message: { content: 'hello' } }] }), { status: 200 })
    )
    const provider = createProvider(config, fakeFetch)
    const out = await provider.complete([{ role: 'user', content: 'hi' }])
    expect(out).toBe('hello')
    expect(fakeFetch).toHaveBeenCalledWith('https://api.example.com/v1/chat/completions', expect.anything())
  })

  it('throws with the provider message on failure', async () => {
    const fakeFetch = vi.fn<(url: string, init?: RequestInit) => Promise<Response>>(
      async () => new Response(JSON.stringify({ error: { message: 'quota exceeded' } }), { status: 429 })
    )
    const provider = createProvider(config, fakeFetch)
    await expect(provider.complete([{ role: 'user', content: 'hi' }])).rejects.toThrow('quota exceeded')
  })

  it('uses the vision model when an image part is present', async () => {
    const fakeFetch = vi.fn<(url: string, init?: RequestInit) => Promise<Response>>(
      async () => new Response(JSON.stringify({ choices: [{ message: { content: 'ok' } }] }), { status: 200 })
    )
    const provider = createProvider(config, fakeFetch)
    await provider.complete([
      { role: 'user', content: [{ type: 'text', text: 'chart?' }, { type: 'image', dataUrl: 'data:image/png;base64,AAAA' }] },
    ])
    const init = fakeFetch.mock.calls[0][1] as RequestInit
    const body = JSON.parse(init.body as string)
    expect(body.model).toBe('vision-model')
  })
})

describe('parseDataUrl', () => {
  it('parses a base64 data URL', () => {
    expect(parseDataUrl('data:image/png;base64,QUJD')).toEqual({ mediaType: 'image/png', data: 'QUJD' })
  })

  it('rejects non-data URLs', () => {
    expect(parseDataUrl('https://example.com/a.png')).toBeNull()
  })
})
