import { afterEach, describe, it, expect, vi } from 'vitest'
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

  it('falls back to the Gemini free tier when only that key exists', () => {
    const config = resolveProviderConfig({ GEMINI_API_KEY: 'free-key' })
    expect(config?.provider).toBe('gemini')
    // No trailing slash: the adapters append `/chat/completions`.
    expect(config?.baseUrl).toBe('https://generativelanguage.googleapis.com/v1beta/openai')
    expect(config?.model).toBe('gemini-3.6-flash')
    // Vision is on the same model on the free tier.
    expect(config?.visionModel).toBe('gemini-3.6-flash')
  })

  it('prefers a paid key over the free tier, with no code change', () => {
    const config = resolveProviderConfig({ GEMINI_API_KEY: 'free-key', OPENAI_API_KEY: 'paid-key' })
    expect(config?.provider).toBe('openai')
  })

  it('honors an explicit AI_PROVIDER=gemini and a pinned model', () => {
    const config = resolveProviderConfig({
      AI_PROVIDER: 'gemini',
      GEMINI_API_KEY: 'free-key',
      GEMINI_MODEL: 'gemini-pinned',
    })
    expect(config?.provider).toBe('gemini')
    expect(config?.model).toBe('gemini-pinned')
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

describe('createProvider (gemini)', () => {
  const config = resolveProviderConfig({ GEMINI_API_KEY: 'free-key' })
  if (!config) throw new Error('expected a gemini config')

  it('posts to the OpenAI-compatible chat endpoint with a bearer key', async () => {
    const fakeFetch = vi.fn<(url: string, init?: RequestInit) => Promise<Response>>(
      async () => new Response(JSON.stringify({ choices: [{ message: { content: 'ok' } }] }), { status: 200 })
    )
    const provider = createProvider(config, fakeFetch)
    await provider.complete([{ role: 'user', content: 'hi' }], { json: true })

    const [url, init] = fakeFetch.mock.calls[0]
    expect(url).toBe('https://generativelanguage.googleapis.com/v1beta/openai/chat/completions')
    expect((init?.headers as Record<string, string>).Authorization).toBe('Bearer free-key')
  })

  it('asks for low reasoning and a ceiling the thinking cannot eat', async () => {
    const fakeFetch = vi.fn<(url: string, init?: RequestInit) => Promise<Response>>(
      async () => new Response(JSON.stringify({ choices: [{ message: { content: '{}' } }] }), { status: 200 })
    )
    await createProvider(config, fakeFetch).complete([{ role: 'user', content: 'hi' }], {
      json: true,
      maxTokens: 700,
    })

    const body = JSON.parse((fakeFetch.mock.calls[0][1] as RequestInit).body as string)
    expect(body.reasoning_effort).toBe('low')
    expect(body.response_format).toEqual({ type: 'json_object' })
    // A caller's smaller budget must not clip the reply behind the thinking.
    expect(body.max_tokens).toBeGreaterThanOrEqual(2000)
  })

  it('leaves the OpenAI request shape untouched', async () => {
    const fakeFetch = vi.fn<(url: string, init?: RequestInit) => Promise<Response>>(
      async () => new Response(JSON.stringify({ choices: [{ message: { content: 'ok' } }] }), { status: 200 })
    )
    const openai = resolveProviderConfig({ OPENAI_API_KEY: 'k' })
    if (!openai) throw new Error('expected an openai config')
    await createProvider(openai, fakeFetch).complete([{ role: 'user', content: 'hi' }])

    const body = JSON.parse((fakeFetch.mock.calls[0][1] as RequestInit).body as string)
    expect(body.reasoning_effort).toBeUndefined()
    expect(body.max_tokens).toBe(900)
  })
})

describe('provider timeouts', () => {
  const config = {
    provider: 'openai' as const,
    apiKey: 'key',
    baseUrl: 'https://api.example.com/v1',
    model: 'm',
    visionModel: 'm',
  }

  afterEach(() => {
    delete process.env.AI_TIMEOUT_MS
  })

  it('fails a hung request with a readable error instead of holding the socket', async () => {
    // A saturated model on an OpenAI-compatible gateway never answers. The
    // adapter must give up rather than leave the review spinning.
    process.env.AI_TIMEOUT_MS = '30'
    const fakeFetch = vi.fn<(url: string, init?: RequestInit) => Promise<Response>>(
      (_url, init) =>
        new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener('abort', () => {
            const error = new Error('This operation was aborted')
            error.name = 'AbortError'
            reject(error)
          })
        })
    )

    await expect(
      createProvider(config, fakeFetch).complete([{ role: 'user', content: 'hi' }])
    ).rejects.toThrow(/did not answer within/)
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
