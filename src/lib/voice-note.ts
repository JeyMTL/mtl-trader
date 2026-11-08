/**
 * Voice notes for the strategy compiler, recorded in the browser as 16 kHz mono
 * WAV.
 *
 * `MediaRecorder` would be less code, but it produces WebM/Opus on Chrome and
 * MP4/AAC on Safari, and the transcription model accepts WAV, MP3, AIFF, AAC,
 * OGG and FLAC — not WebM. Encoding PCM to WAV here removes that lottery: any
 * browser that can record at all sends a format the server can read.
 *
 * The one-minute cap is really a payload cap. 16 kHz mono 16-bit speech is
 * 32 KB/s, so a full note is ~1.9 MB before base64 — which is what keeps a
 * recording and a couple of charts inside one request.
 */

export const MAX_VOICE_SECONDS = 60
export const VOICE_SAMPLE_RATE = 16_000

export interface VoiceClip {
  dataUrl: string
  seconds: number
  bytes: number
}

export interface VoiceRecorder {
  stop(): Promise<VoiceClip>
  cancel(): void
}

/**
 * Averages each window instead of picking one sample, so downsampling a voice
 * does not fold high frequencies back in as noise the model has to read through.
 */
export function downsample(input: Float32Array, from: number, to: number): Float32Array {
  if (to <= 0 || from <= 0 || to >= from) return input.slice()
  const ratio = from / to
  const length = Math.floor(input.length / ratio)
  const out = new Float32Array(length)
  for (let index = 0; index < length; index += 1) {
    const start = Math.floor(index * ratio)
    const end = Math.min(input.length, Math.floor((index + 1) * ratio))
    let sum = 0
    for (let cursor = start; cursor < end; cursor += 1) sum += input[cursor] ?? 0
    out[index] = sum / Math.max(1, end - start)
  }
  return out
}

/** Canonical 44-byte RIFF/WAVE header around 16-bit mono PCM. */
export function encodeWav(samples: Float32Array, sampleRate: number = VOICE_SAMPLE_RATE): Uint8Array {
  const bytes = new Uint8Array(44 + samples.length * 2)
  const view = new DataView(bytes.buffer)
  const ascii = (offset: number, text: string) => {
    for (let index = 0; index < text.length; index += 1) view.setUint8(offset + index, text.charCodeAt(index))
  }

  const dataLength = samples.length * 2
  ascii(0, 'RIFF')
  view.setUint32(4, 36 + dataLength, true)
  ascii(8, 'WAVE')
  ascii(12, 'fmt ')
  view.setUint32(16, 16, true) // fmt chunk size
  view.setUint16(20, 1, true) // PCM
  view.setUint16(22, 1, true) // mono
  view.setUint32(24, sampleRate, true)
  view.setUint32(28, sampleRate * 2, true) // byte rate
  view.setUint16(32, 2, true) // block align
  view.setUint16(34, 16, true) // bits per sample
  ascii(36, 'data')
  view.setUint32(40, dataLength, true)

  for (let index = 0; index < samples.length; index += 1) {
    const value = Math.max(-1, Math.min(1, samples[index] ?? 0))
    view.setInt16(44 + index * 2, Math.round(value < 0 ? value * 0x8000 : value * 0x7fff), true)
  }
  return bytes
}

function toBase64(bytes: Uint8Array): string {
  // Chunked because spreading a megabyte of numbers into one call overflows the
  // argument limit in every engine that implements it.
  const chunk = 0x8000
  let binary = ''
  for (let index = 0; index < bytes.length; index += chunk) {
    binary += String.fromCharCode(...Array.from(bytes.subarray(index, index + chunk)))
  }
  return btoa(binary)
}

function audioContextCtor(): typeof AudioContext | null {
  if (typeof window === 'undefined') return null
  const candidate =
    window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext
  return candidate ?? null
}

export function voiceNoteSupported(): boolean {
  if (typeof navigator === 'undefined') return false
  return Boolean(navigator.mediaDevices?.getUserMedia) && audioContextCtor() !== null
}

/**
 * Opens the microphone and starts collecting PCM.
 *
 * The processor is routed through a silent gain node rather than straight to the
 * destination: a `ScriptProcessorNode` only fires while connected, and letting
 * it play back what the microphone hears would be a feedback loop.
 */
export async function startVoiceNote(): Promise<VoiceRecorder> {
  if (!voiceNoteSupported()) {
    throw new Error('This browser cannot record audio. Type the explanation instead.')
  }
  const Ctor = audioContextCtor()
  if (!Ctor) throw new Error('This browser cannot record audio. Type the explanation instead.')

  const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
  const context = new Ctor()
  try {
    await context.resume()
  } catch {
    // Already running in most browsers; a resume that fails is not fatal.
  }

  const source = context.createMediaStreamSource(stream)
  const processor = context.createScriptProcessor(4096, 1, 1)
  const silencer = context.createGain()
  silencer.gain.value = 0

  const chunks: Float32Array[] = []
  const ceiling = MAX_VOICE_SECONDS * context.sampleRate * 2 // runaway guard only

  processor.onaudioprocess = (event) => {
    if (chunks.length * 4096 >= ceiling) return
    chunks.push(new Float32Array(event.inputBuffer.getChannelData(0)))
  }

  source.connect(processor)
  processor.connect(silencer)
  silencer.connect(context.destination)

  let closed = false
  const teardown = () => {
    if (closed) return
    closed = true
    processor.onaudioprocess = null
    try {
      source.disconnect()
      processor.disconnect()
      silencer.disconnect()
    } catch {
      // Already disconnected; nothing to release.
    }
    stream.getTracks().forEach((track) => track.stop())
    void context.close().catch(() => undefined)
  }

  return {
    async stop() {
      teardown()
      const total = chunks.reduce((sum, chunk) => sum + chunk.length, 0)
      const merged = new Float32Array(total)
      let offset = 0
      for (const chunk of chunks) {
        merged.set(chunk, offset)
        offset += chunk.length
      }
      const pcm = downsample(merged, context.sampleRate, VOICE_SAMPLE_RATE).subarray(
        0,
        MAX_VOICE_SECONDS * VOICE_SAMPLE_RATE
      )
      const wav = encodeWav(pcm, VOICE_SAMPLE_RATE)
      return {
        dataUrl: `data:audio/wav;base64,${toBase64(wav)}`,
        seconds: Math.round(pcm.length / VOICE_SAMPLE_RATE),
        bytes: wav.length,
      }
    },
    cancel() {
      teardown()
    },
  }
}
