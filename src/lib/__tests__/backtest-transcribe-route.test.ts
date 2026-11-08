import { beforeEach, describe, expect, it, vi } from 'vitest'

const mocks = vi.hoisted(() => ({
  transcribe: vi.fn(),
  gate: { allowed: true, status: 200, message: '', reason: 'ok' } as {
    allowed: boolean
    status: number
    message: string
    reason: string
  },
  limit: { ok: true, remaining: 9, retryAfterMs: 0 },
  user: { id: 'user-1' } as { id: string } | null,
}))

vi.mock('@/lib/server-auth', () => ({
  getAuthUser: vi.fn(async () => mocks.user),
  getAdminClient: vi.fn(),
}))
vi.mock('@/lib/plan-guard', () => ({ checkFeature: vi.fn(async () => mocks.gate) }))
vi.mock('@/lib/rate-limit', () => ({ rateLimit: vi.fn(async () => mocks.limit) }))
vi.mock('@/lib/ai/transcribe', async () => {
  const actual = await vi.importActual<typeof import('@/lib/ai/transcribe')>('@/lib/ai/transcribe')
  return { ...actual, transcribeAudio: mocks.transcribe }
})

import { POST } from '@/app/api/backtest/transcribe/route'
import { TranscriptionUnavailableError } from '@/lib/ai/transcribe'

const AUDIO = `data:audio/wav;base64,${'A'.repeat(400)}`

function post(body: unknown): Request {
  return new Request('https://app.test/api/backtest/transcribe', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}

beforeEach(() => {
  mocks.transcribe.mockReset()
  mocks.transcribe.mockResolvedValue('a fair value gap only counts when it is unfilled')
  mocks.user = { id: 'user-1' }
  mocks.gate = { allowed: true, status: 200, message: '', reason: 'ok' }
  mocks.limit = { ok: true, remaining: 9, retryAfterMs: 0 }
})

describe('POST /api/backtest/transcribe', () => {
  it('returns the transcript as text', async () => {
    const response = await POST(post({ audio: AUDIO }))
    expect(response.status).toBe(200)
    await expect(response.json()).resolves.toEqual({
      transcript: 'a fair value gap only counts when it is unfilled',
    })
    expect(mocks.transcribe).toHaveBeenCalledWith({
      mimeType: 'audio/wav',
      data: 'A'.repeat(400),
    })
  })

  it('refuses an audio format the model cannot read, before spending a call', async () => {
    // WebM is what MediaRecorder produces on Chrome; the recorder here avoids it.
    const response = await POST(post({ audio: `data:audio/webm;base64,${'A'.repeat(400)}` }))
    expect(response.status).toBe(400)
    expect(mocks.transcribe).not.toHaveBeenCalled()
  })

  it('tells the user to type instead when no key can transcribe', async () => {
    mocks.transcribe.mockRejectedValueOnce(new TranscriptionUnavailableError())
    const response = await POST(post({ audio: AUDIO }))
    expect(response.status).toBe(503)
    const body = (await response.json()) as { error: string }
    expect(body.error).toContain('GEMINI_API_KEY')
  })

  it('surfaces silence as an error rather than an empty transcript', async () => {
    mocks.transcribe.mockRejectedValueOnce(
      new Error('Nothing intelligible was in that recording. Try again, closer to the microphone.')
    )
    const response = await POST(post({ audio: AUDIO }))
    expect(response.status).toBe(502)
    const body = (await response.json()) as { error: string }
    expect(body.error).toContain('Nothing intelligible')
  })

  it('requires an account', async () => {
    mocks.user = null
    const response = await POST(post({ audio: AUDIO }))
    expect(response.status).toBe(401)
  })

  it('is part of the paid workbench', async () => {
    mocks.gate = { allowed: false, status: 402, message: 'Pro only', reason: 'pro_required' }
    const response = await POST(post({ audio: AUDIO }))
    expect(response.status).toBe(402)
  })

  it('rate limits recordings', async () => {
    mocks.limit = { ok: false, remaining: 0, retryAfterMs: 30_000 }
    const response = await POST(post({ audio: AUDIO }))
    expect(response.status).toBe(429)
    expect(response.headers.get('Retry-After')).toBe('30')
  })
})
