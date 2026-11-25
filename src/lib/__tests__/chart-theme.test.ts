import { describe, expect, it } from 'vitest'

import { paddedDomain } from '@/lib/chart-theme'

describe('paddedDomain', () => {
  it('falls back to a usable range when there is no data', () => {
    expect(paddedDomain([])).toEqual([0, 1])
  })

  it('gives a flat or single-point series a visible band', () => {
    const [min, max] = paddedDomain([1000])
    expect(max - min).toBeGreaterThan(0)
    expect(min).toBeLessThan(1000)
    expect(max).toBeGreaterThan(1000)
  })

  it('pads a real range by the requested share', () => {
    const [min, max] = paddedDomain([1000, 1200])
    expect(min).toBeCloseTo(1000 - 200 * 0.18, 6)
    expect(max).toBeCloseTo(1200 + 200 * 0.18, 6)
  })

  it('never pads by less than five percent', () => {
    const [min, max] = paddedDomain([100, 200], 0)
    expect(min).toBeCloseTo(95, 6)
    expect(max).toBeCloseTo(205, 6)
  })
})
