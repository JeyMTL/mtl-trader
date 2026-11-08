import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import { rateLimit } from '@/lib/rate-limit'
import { apiError, apiWarn, logEvent } from '@/lib/log'
import { readJsonBody } from '@/lib/request'
import { checkFeature } from '@/lib/plan-guard'
import {
  AUDIO_TYPES,
  MAX_AUDIO_BYTES,
  TranscriptionUnavailableError,
  transcribeAudio,
} from '@/lib/ai/transcribe'

/**
 * Voice note -> text for the custom backtest compiler.
 *
 * POST { audio: dataUrl } -> { transcript }
 *
 * The transcript is text, not an attachment: the browser drops it into the
 * description box where the trader can read it and fix any word the recogniser
 * missed before a single rule is compiled. Nothing is stored — the recording and
 * the transcript exist for the length of this request, and the description they
 * become is saved only if the trader saves it.
 *
 * Gated like the compile itself, since it is part of the Pro workbench and each
 * call bills the model.
 */

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const maxDuration = 60

const MAX_BODY_BYTES = 4 * 1024 * 1024

function usableAudio(raw: unknown): { mimeType: string; data: string; bytes: number } | null {
  if (typeof raw !== 'string') return null
  const match = /^data:(audio\/[a-z0-9.+-]+);base64,([a-z0-9+/=\s]+)$/i.exec(raw.trim())
  if (!match) return null
  const mimeType = match[1].toLowerCase()
  if (!AUDIO_TYPES.has(mimeType)) return null
  const data = match[2].replace(/\s/g, '')
  const bytes = Math.floor((data.length * 3) / 4)
  if (bytes === 0 || bytes > MAX_AUDIO_BYTES) return null
  return { mimeType, data, bytes }
}

export async function POST(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const limit = await rateLimit(`backtest-transcribe:${user.id}`, 10, 10 * 60 * 1000)
    if (!limit.ok) {
      return NextResponse.json(
        { error: 'Too many recordings. Type the explanation, or try again in a few minutes.' },
        { status: 429, headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) } }
      )
    }

    const gate = await checkFeature(user.id, 'backtest')
    if (!gate.allowed) {
      return NextResponse.json(
        { error: gate.message, code: 'upgrade_required' },
        { status: gate.status }
      )
    }

    const parsed = await readJsonBody<Record<string, unknown>>(req, { maxBytes: MAX_BODY_BYTES })
    if (!parsed.ok) return parsed.response

    const audio = usableAudio(parsed.value.audio)
    if (!audio) {
      return apiWarn(
        'backtest.transcribe.invalid',
        'That recording could not be read. Record up to a minute, or type the explanation instead.',
        400
      )
    }

    let transcript: string
    try {
      transcript = await transcribeAudio({ mimeType: audio.mimeType, data: audio.data })
    } catch (error: unknown) {
      if (error instanceof TranscriptionUnavailableError) {
        return NextResponse.json(
          {
            error:
              'Voice notes need GEMINI_API_KEY. Type the explanation instead, or add the key to enable recording.',
          },
          { status: 503 }
        )
      }
      logEvent('warn', 'backtest.transcribe.provider', { error, userId: user.id })
      const message =
        error instanceof Error && error.message.startsWith('Nothing intelligible')
          ? error.message
          : 'Could not transcribe that recording. Try again, or type the explanation.'
      return NextResponse.json({ error: message }, { status: 502 })
    }

    // Never log the recording or its text — only that it worked, and how big it was.
    logEvent('info', 'backtest.transcribe', {
      userId: user.id,
      bytes: audio.bytes,
      chars: transcript.length,
    })

    return NextResponse.json({ transcript }, { headers: { 'Cache-Control': 'no-store' } })
  } catch (error: unknown) {
    return apiError('backtest.transcribe', error, 500, 'Could not transcribe that recording.')
  }
}
