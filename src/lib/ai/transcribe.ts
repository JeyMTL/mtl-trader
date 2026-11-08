/**
 * Speech to text, for the voice notes that feed the custom backtest compiler.
 *
 * A trader explaining "what I actually count as a fair value gap" speaks more
 * fluently than they type, and the nuance that makes a setup theirs is exactly
 * the part that gets lost in a short paragraph. There is no separate speech
 * vendor here: Gemini takes audio inline in the same generative call the text
 * models use, so the only new requirement is a key this app already holds.
 *
 * Transcription is deliberately its own capability. Anthropic has no audio
 * input and there is no OpenAI account in this project, so this needs
 * GEMINI_API_KEY even when the review provider is something else — and when the
 * key is absent the caller is told, rather than having the recording quietly
 * dropped.
 */

import { GEMINI_BASE_URL, GEMINI_DEFAULT_MODEL } from './providers'
import type { FetchLike } from './providers'

/**
 * Audio formats Gemini accepts inline. WebM/Opus (what MediaRecorder produces on
 * Chrome) is deliberately absent: the browser encoder here writes PCM WAV so the
 * upload never depends on which recorder a browser happens to ship.
 */
export const AUDIO_TYPES = new Set([
  'audio/wav',
  'audio/x-wav',
  'audio/mpeg',
  'audio/mp3',
  'audio/ogg',
  'audio/mp4',
  'audio/m4a',
  'audio/x-m4a',
  'audio/aac',
  'audio/flac',
  'audio/aiff',
])

/** A minute of 16 kHz mono speech is ~1.9 MB; this is the ceiling regardless. */
export const MAX_AUDIO_BYTES = 3 * 1024 * 1024
/** The transcript becomes the compile description, which is capped at 4,000. */
export const MAX_TRANSCRIPT_CHARS = 4_000

export interface TranscriptionConfig {
  apiKey: string
  baseUrl: string
  model: string
}

/** Thrown when no key can transcribe. The route turns this into a 503. */
export class TranscriptionUnavailableError extends Error {
  constructor() {
    super('Voice notes need a Gemini key.')
    this.name = 'TranscriptionUnavailableError'
  }
}

/**
 * Resolves the native Gemini endpoint from the compatibility one.
 *
 * `resolveProviderConfig` returns Gemini's OpenAI-compatible base because that is
 * what the review speaks; audio parts are only accepted on the native
 * `generateContent` endpoint, so the `/openai` suffix comes off here.
 */
export function transcriptionConfig(
  env: Record<string, string | undefined> = process.env
): TranscriptionConfig | null {
  const apiKey = env.GEMINI_API_KEY
  if (!apiKey) return null

  const compat = env.GEMINI_BASE_URL || GEMINI_BASE_URL
  const explicit = env.GEMINI_NATIVE_BASE_URL
  const baseUrl = (explicit || compat).replace(/\/+$/, '').replace(/\/openai$/, '')

  // Never `AI_MODEL` here: that name may hold an Anthropic model, which this
  // endpoint does not know.
  const model =
    env.GEMINI_TRANSCRIBE_MODEL || env.GEMINI_VISION_MODEL || env.GEMINI_MODEL || GEMINI_DEFAULT_MODEL

  return { apiKey, baseUrl, model }
}

const INSTRUCTIONS = [
  'Transcribe this recording verbatim into plain text.',
  'It is a trader explaining a strategy, or what they count as a valid setup, possibly while looking at a chart.',
  'Keep their words and trading terms exactly as spoken — for example "fair value gap", "liquidity sweep", "displacement", "fair value gap midpoint".',
  'Do not correct, summarise, reorder or add anything, and do not describe the audio.',
  'Output only the transcript, with no preamble and no quotation marks.',
  'If nothing intelligible was said, output exactly: NO SPEECH',
].join(' ')

async function errorText(response: Response): Promise<string> {
  try {
    const text = await response.text()
    try {
      const parsed = JSON.parse(text) as { error?: { message?: string } }
      if (parsed.error?.message) return parsed.error.message
    } catch {
      // fall through to the raw body
    }
    return text.slice(0, 300) || `HTTP ${response.status}`
  } catch {
    return `HTTP ${response.status}`
  }
}

/**
 * Transcribes one recording.
 *
 * The audio is sent as inline data (base64) rather than through the Files API:
 * a minute of speech is well under the inline ceiling, and a two-step upload
 * would leave an orphaned file behind for every failed compile.
 */
export async function transcribeAudio(
  audio: { mimeType: string; data: string },
  options: {
    fetchImpl?: FetchLike
    env?: Record<string, string | undefined>
    signal?: AbortSignal
    timeoutMs?: number
  } = {}
): Promise<string> {
  const config = transcriptionConfig(options.env)
  if (!config) throw new TranscriptionUnavailableError()

  const fetchImpl = options.fetchImpl ?? fetch
  const timeout = AbortSignal.timeout(options.timeoutMs ?? 45_000)
  const signal = options.signal ? AbortSignal.any([options.signal, timeout]) : timeout

  let response: Response
  try {
    response = await fetchImpl(
      `${config.baseUrl}/models/${config.model}:generateContent`,
      {
        method: 'POST',
        headers: { 'x-goog-api-key': config.apiKey, 'Content-Type': 'application/json' },
        signal,
        body: JSON.stringify({
          contents: [
            {
              role: 'user',
              parts: [{ inline_data: { mime_type: audio.mimeType, data: audio.data } }, { text: INSTRUCTIONS }],
            },
          ],
          generationConfig: { temperature: 0, maxOutputTokens: 2048 },
        }),
      }
    )
  } catch (error: unknown) {
    if (error instanceof Error && (error.name === 'AbortError' || error.name === 'TimeoutError')) {
      throw new Error('The transcription did not answer in time. Try a shorter recording.')
    }
    throw error
  }

  if (!response.ok) throw new Error(`Transcription failed: ${await errorText(response)}`)

  const data = (await response.json()) as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>
  }
  const text = (data.candidates?.[0]?.content?.parts ?? [])
    .map((part) => part.text ?? '')
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim()

  if (!text) throw new Error('The recording came back empty. Try again, or type the explanation.')
  if (/^no speech$/i.test(text)) {
    throw new Error('Nothing intelligible was in that recording. Try again, closer to the microphone.')
  }

  return text.slice(0, MAX_TRANSCRIPT_CHARS)
}
