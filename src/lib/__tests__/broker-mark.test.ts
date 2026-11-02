import { describe, expect, it } from 'vitest'
import { brokerInitials, brokerMarkColor } from '@/lib/broker-mark'
import { MT5_BROKERS } from '@/lib/mt5-brokers'

describe('broker monograms', () => {
  it('takes the initials of a two-word broker', () => {
    expect(brokerInitials('IC Markets')).toBe('IM')
    expect(brokerInitials('FP Markets')).toBe('FM')
    expect(brokerInitials('MultiBank Group')).toBe('MG')
  })

  it('uses the first two characters of a single-word name', () => {
    expect(brokerInitials('Exness')).toBe('EX')
    expect(brokerInitials('XM')).toBe('XM')
    expect(brokerInitials('easyMarkets')).toBe('EA')
  })

  it('drops punctuation rather than using it as an initial', () => {
    expect(brokerInitials('XS.com')).toBe('XS')
    expect(brokerInitials('Gerchik & Co')).toBe('GC')
  })

  it('never returns an empty mark', () => {
    expect(brokerInitials('')).toBe('?')
    expect(brokerInitials('   ')).toBe('?')
    expect(brokerInitials('###')).toBe('?')
  })

  it('gives every broker in the directory a non-empty mark', () => {
    for (const broker of MT5_BROKERS) {
      expect(brokerInitials(broker.name).length, broker.name).toBeGreaterThan(0)
      expect(brokerInitials(broker.name), broker.name).not.toBe('?')
    }
  })

  it('is stable for a name and varies across names', () => {
    expect(brokerMarkColor('IC Markets')).toBe(brokerMarkColor('IC Markets'))
    expect(brokerMarkColor('IC Markets')).toMatch(/^#[0-9A-F]{6}$/)
    expect(brokerMarkColor('IC Markets')).not.toBe(brokerMarkColor('Exness'))
  })
})
