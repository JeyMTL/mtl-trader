import { describe, expect, it } from 'vitest'
import { downsample, encodeWav, VOICE_SAMPLE_RATE } from '@/lib/voice-note'

function text(bytes: Uint8Array, offset: number, length: number): string {
  return String.fromCharCode(...Array.from(bytes.slice(offset, offset + length)))
}

describe('encodeWav', () => {
  it('writes a mono 16-bit PCM header that matches the sample count', () => {
    const samples = new Float32Array([0, 0.5, -0.5])
    const wav = encodeWav(samples, 16_000)
    const view = new DataView(wav.buffer, wav.byteOffset, wav.byteLength)

    expect(wav.byteLength).toBe(44 + samples.length * 2)
    expect(text(wav, 0, 4)).toBe('RIFF')
    expect(text(wav, 8, 4)).toBe('WAVE')
    expect(text(wav, 12, 4)).toBe('fmt ')
    expect(text(wav, 36, 4)).toBe('data')
    expect(view.getUint32(4, true)).toBe(36 + samples.length * 2)
    expect(view.getUint16(20, true)).toBe(1) // PCM
    expect(view.getUint16(22, true)).toBe(1) // mono
    expect(view.getUint32(24, true)).toBe(16_000)
    expect(view.getUint32(28, true)).toBe(32_000) // byte rate
    expect(view.getUint16(34, true)).toBe(16) // bits
    expect(view.getUint32(40, true)).toBe(samples.length * 2)
  })

  it('converts samples to signed 16-bit without losing the sign', () => {
    const wav = encodeWav(new Float32Array([0, 0.5, -0.5]), VOICE_SAMPLE_RATE)
    const view = new DataView(wav.buffer, wav.byteOffset, wav.byteLength)
    expect(view.getInt16(44, true)).toBe(0)
    expect(view.getInt16(46, true)).toBe(Math.round(0.5 * 0x7fff))
    expect(view.getInt16(48, true)).toBe(Math.round(-0.5 * 0x8000))
  })

  it('clamps values beyond the representable range instead of wrapping', () => {
    const wav = encodeWav(new Float32Array([4, -4]), VOICE_SAMPLE_RATE)
    const view = new DataView(wav.buffer, wav.byteOffset, wav.byteLength)
    expect(view.getInt16(44, true)).toBe(0x7fff)
    expect(view.getInt16(46, true)).toBe(-0x8000)
  })
})

describe('downsample', () => {
  it('averages each window rather than picking one sample', () => {
    const input = new Float32Array([0, 1, 0, 1, 0, 1, 0, 1])
    expect(Array.from(downsample(input, 4, 2))).toEqual([0.5, 0.5, 0.5, 0.5])
  })

  it('leaves the signal alone when no reduction is needed', () => {
    const input = new Float32Array([0.25, -0.25])
    expect(Array.from(downsample(input, 16_000, 16_000))).toEqual([0.25, -0.25])
  })
})
