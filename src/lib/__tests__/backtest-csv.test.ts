import { describe, expect, it } from 'vitest'
import { parseBarsCsv } from '@/lib/backtest/csv'

const header = '<DATE>\t<TIME>\t<OPEN>\t<HIGH>\t<LOW>\t<CLOSE>\t<TICKVOL>\t<VOL>\t<SPREAD>'

function mt5Rows(count: number, start = 0): string {
  const rows: string[] = []
  for (let index = start; index < start + count; index += 1) {
    const hour = String(index % 24).padStart(2, '0')
    const day = String(1 + Math.floor(index / 24)).padStart(2, '0')
    rows.push(`2026.10.${day}\t${hour}:00:00\t100\t101\t99\t100.5\t10\t0\t2`)
  }
  return rows.join('\n')
}

describe('bar CSV import', () => {
  it('reads an MT5 tab-separated export', () => {
    const csv = `${header}\n${mt5Rows(60)}`
    const bars = parseBarsCsv(csv)

    expect(bars).toHaveLength(60)
    expect(bars[0]).toMatchObject({ open: 100, high: 101, low: 99, close: 100.5 })
    // 2026.10.01 00:00 UTC
    expect(new Date(bars[0]!.time).toISOString()).toBe('2026-10-01T00:00:00.000Z')
  })

  it('reads semicolon-separated ISO data without a time column', () => {
    const rows = ['date;open;high;low;close;volume']
    for (let index = 0; index < 55; index += 1) {
      const minute = String(index % 60).padStart(2, '0')
      rows.push(`2026-10-01T10:${minute}:00Z;1.1;1.2;1.0;1.15;120`)
    }
    const bars = parseBarsCsv([...new Set(rows)].join('\n'))
    expect(bars.length).toBeGreaterThanOrEqual(50)
    expect(bars[0]!.close).toBe(1.15)
  })

  it('applies a timezone offset to every timestamp', () => {
    const bars = parseBarsCsv(`${header}\n${mt5Rows(60)}`, {
      timezoneOffsetMinutes: 180,
    })
    expect(new Date(bars[0]!.time).toISOString()).toBe('2026-09-30T21:00:00.000Z')
  })

  it('rejects a file with no header', () => {
    const data = '2026.10.01\t10:00:00\t100\t101\t99\t100\n2026.10.01\t10:01:00\t100\t101\t99\t100'
    expect(() => parseBarsCsv(data)).toThrow(/header/i)
  })

  it('rejects a bar whose high is below its low, naming the row', () => {
    const broken = `${header}\n2026.10.01\t10:00:00\t100\t99\t101\t100`
    expect(() => parseBarsCsv(broken)).toThrow(/Row 2: high/)
  })

  it('rejects out-of-order timestamps instead of sorting them', () => {
    const csv = [
      header,
      '2026.10.01\t10:01:00\t100\t101\t99\t100',
      '2026.10.01\t10:00:00\t100\t101\t99\t100',
    ].join('\n')
    expect(() => parseBarsCsv(csv)).toThrow(/chronological/)
  })

  it('keeps the last copy of a duplicated timestamp', () => {
    const rows = [header]
    for (let index = 0; index < 60; index += 1) {
      rows.push(`2026-10-01T10:00:00Z\t10:00:00\t100\t101\t99\t${100 + index / 100}`)
    }
    // Enough distinct bars after the duplicate to clear the 50-bar floor.
    for (let index = 1; index <= 55; index += 1) {
      const stamp = new Date(Date.UTC(2026, 9, 11, 0, index)).toISOString()
      rows.push(`${stamp}\t00:00:00\t100\t101\t99\t100`)
    }
    const bars = parseBarsCsv(rows.join('\n'))
    expect(bars[0]!.close).toBe(100.59)
    expect(bars).toHaveLength(56)
  })

  it('refuses a range that is too short to mean anything', () => {
    const csv = `${header}\n${mt5Rows(10)}`
    expect(() => parseBarsCsv(csv)).toThrow(/at least 50/)
  })

  it('stops at the bar cap', () => {
    const csv = `${header}\n${mt5Rows(60)}`
    expect(() => parseBarsCsv(csv, { maxBars: 40 })).toThrow(/more than 40 bars/)
  })
})
