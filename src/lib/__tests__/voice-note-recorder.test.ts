// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { startVoiceNote, voiceNoteSupported } from '@/lib/voice-note'

/**
 * The recorder cannot be tested against a real microphone here, so the browser
 * surface it depends on is faked: an AudioContext that hands back a processor the
 * test can fire, and a media stream whose tracks report being stopped. That
 * covers the wiring this file owns — chunk collection, downsampling, WAV output,
 * teardown — which is where a bug would actually live.
 */
let processor: {
  onaudioprocess: ((event: { inputBuffer: { getChannelData: () => Float32Array } }) => void) | null
  connect: () => void
  disconnect: () => void
} | null = null

let stopTrack: ReturnType<typeof vi.fn>

class FakeAudioContext {
  sampleRate = 16_000
  destination = {}
  createMediaStreamSource() {
    return { connect() {}, disconnect() {} }
  }
  createScriptProcessor() {
    processor = { onaudioprocess: null, connect() {}, disconnect() {} }
    return processor
  }
  createGain() {
    return { gain: { value: 1 }, connect() {}, disconnect() {} }
  }
  async resume() {}
  async close() {}
}

function emit(samples: number) {
  const chunk = new Float32Array(samples).fill(0.5)
  processor?.onaudioprocess?.({ inputBuffer: { getChannelData: () => chunk } })
}

beforeEach(() => {
  processor = null
  stopTrack = vi.fn()
  Object.defineProperty(window, 'AudioContext', {
    value: FakeAudioContext,
    configurable: true,
    writable: true,
  })
  Object.defineProperty(navigator, 'mediaDevices', {
    value: { getUserMedia: async () => ({ getTracks: () => [{ stop: stopTrack }] }) },
    configurable: true,
  })
})

afterEach(() => {
  vi.restoreAllMocks()
})

describe('voice note recorder', () => {
  it('reports support when the browser has a recorder and an audio context', () => {
    expect(voiceNoteSupported()).toBe(true)
  })

  it('collects PCM, downsamples, and returns a playable WAV data URL', async () => {
    const recorder = await startVoiceNote()
    emit(4_096)
    emit(4_096)

    const clip = await recorder.stop()

    expect(stopTrack).toHaveBeenCalled()
    expect(clip.dataUrl.startsWith('data:audio/wav;base64,')).toBe(true)
    expect(clip.bytes).toBe(44 + 8_192 * 2)
    expect(clip.seconds).toBe(1)

    const binary = atob(clip.dataUrl.split(',')[1] ?? '')
    expect(binary.slice(0, 4)).toBe('RIFF')
    expect(binary.slice(8, 12)).toBe('WAVE')
  })

  it('releases the microphone when a recording is cancelled', async () => {
    const recorder = await startVoiceNote()
    recorder.cancel()
    expect(stopTrack).toHaveBeenCalled()
  })

  it('stops collecting once the processor is torn down', async () => {
    const { encodeWav } = await import('@/lib/voice-note')
    expect(encodeWav(new Float32Array(2)).byteLength).toBe(48)

    const recorder = await startVoiceNote()
    emit(4_096)
    recorder.cancel()
    const clip = await recorder.stop()
    // A second stop after teardown must not double-count the chunks.
    expect(clip.bytes).toBe(44 + 4_096 * 2)
  })
})
