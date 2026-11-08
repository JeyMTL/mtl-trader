import { describe, expect, it } from 'vitest'
import {
  TranscriptionUnavailableError,
  transcribeAudio,
  transcriptionConfig,
} from '@/lib/ai/transcribe'

function reply(body: unknown, ok = true): Response {
  return new Response(JSON.stringify(body), {
    status: ok ? 200 : 502,
    headers: { 'Content-Type': 'application/json' },
  })
}

describe('transcriptionConfig', () => {
  it('needs a Gemini key even when another provider answers reviews', () => {
    expect(transcriptionConfig({ ANTHROPIC_API_KEY: 'sk-ant' })).toBeNull()
  })

  it('turns the compatibility base URL into the native one', () => {
    const config = transcriptionConfig({ GEMINI_API_KEY: 'k' })
    expect(config?.baseUrl).toBe('https://generativelanguage.googleapis.com/v1beta')
    expect(config?.model).toBe('gemini-3.6-flash')
  })

  it('honours an explicit native base URL', () => {
    expect(
      transcriptionConfig({ GEMINI_API_KEY: 'k', GEMINI_NATIVE_BASE_URL: 'https://example.test/v1/' })
        ?.baseUrl
    ).toBe('https://example.test/v1')
  })

  it('never picks up a non-Gemini model name', () => {
    const config = transcriptionConfig({
      GEMINI_API_KEY: 'k',
      AI_MODEL: 'claude-3-5-sonnet-latest',
      GEMINI_MODEL: 'gemini-3.6-flash',
    })
    expect(config?.model).toBe('gemini-3.6-flash')
  })
})

describe('transcribeAudio', () => {
  it('sends the audio inline and returns the cleaned transcript', async () => {
    const calls: Array<{ url: string; body: Record<string, unknown> }> = []
    const transcript = await transcribeAudio(
      { mimeType: 'audio/wav', data: 'AAAA' },
      {
        env: { GEMINI_API_KEY: 'k' },
        fetchImpl: async (url, init) => {
          calls.push({ url, body: JSON.parse(String(init?.body)) as Record<string, unknown> })
          return reply({ candidates: [{ content: { parts: [{ text: '  a fair value gap  ' }] } }] })
        },
      }
    )

    expect(transcript).toBe('a fair value gap')
    expect(calls[0]?.url).toBe(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent'
    )
    const contents = calls[0]?.body.contents as Array<{ parts: Array<Record<string, unknown>> }>
    expect(contents[0]?.parts[0]).toEqual({
      inline_data: { mime_type: 'audio/wav', data: 'AAAA' },
    })
    expect(String(contents[0]?.parts[1]?.text)).toContain('Transcribe this recording verbatim')
  })

  it('refuses to run with no key at all', async () => {
    await expect(
      transcribeAudio({ mimeType: 'audio/wav', data: 'AAAA' }, { env: {} })
    ).rejects.toBeInstanceOf(TranscriptionUnavailableError)
  })

  it('turns silence into a sentence the trader can act on', async () => {
    await expect(
      transcribeAudio(
        { mimeType: 'audio/wav', data: 'AAAA' },
        {
          env: { GEMINI_API_KEY: 'k' },
          fetchImpl: async () => reply({ candidates: [{ content: { parts: [{ text: 'NO SPEECH' }] } }] }),
        }
      )
    ).rejects.toThrow(/Nothing intelligible/)
  })

  it('treats an empty reply as a failure rather than an empty description', async () => {
    await expect(
      transcribeAudio(
        { mimeType: 'audio/wav', data: 'AAAA' },
        {
          env: { GEMINI_API_KEY: 'k' },
          fetchImpl: async () => reply({ candidates: [{ content: { parts: [{ text: '   ' }] } }] }),
        }
      )
    ).rejects.toThrow(/came back empty/)
  })

  it('surfaces the provider error text when the request is rejected', async () => {
    await expect(
      transcribeAudio(
        { mimeType: 'audio/wav', data: 'AAAA' },
        {
          env: { GEMINI_API_KEY: 'k' },
          fetchImpl: async () => reply({ error: { message: 'API key not valid' } }, false),
        }
      )
    ).rejects.toThrow(/API key not valid/)
  })
})
