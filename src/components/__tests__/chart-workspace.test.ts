import { describe, expect, it } from 'vitest'
import { mergeSymbolDrawings, type ChartDrawingRow } from '@/components/chart-workspace'

/**
 * The desk re-reads the shared table every few seconds. The merge is what stops
 * that read from disturbing anything a trader is doing at the same moment: other
 * symbols keep their state, a row the phone deleted disappears, and an object
 * that is still being inserted is not wiped out from under the pointer.
 */

function row(
  id: string,
  symbol: string,
  price = 1.1,
  editedAtMs: number | null = null
): ChartDrawingRow {
  return {
    id,
    symbol,
    kind: 'ray',
    points: [{ t: 1_760_000_000_000, p: price }],
    text: null,
    style: {},
    editedAtMs,
  }
}

describe('mergeSymbolDrawings', () => {
  it('replaces one symbol and leaves the others alone', () => {
    const current = [row('a', 'EUR_USD'), row('b', 'XAU_USD')]
    const incoming = [row('a', 'EUR_USD', 1.2), row('c', 'EUR_USD')]

    const merged = mergeSymbolDrawings(current, incoming, 'EUR_USD')

    expect(merged.filter((item) => item.symbol === 'EUR_USD').map((item) => item.id)).toEqual([
      'a',
      'c',
    ])
    expect(merged.find((item) => item.symbol === 'XAU_USD')?.id).toBe('b')
    expect(merged.find((item) => item.id === 'a')?.points[0].p).toBe(1.2)
  })

  it('drops an object the phone deleted', () => {
    const current = [row('a', 'EUR_USD'), row('b', 'EUR_USD')]

    const merged = mergeSymbolDrawings(current, [row('a', 'EUR_USD')], 'EUR_USD')

    expect(merged.map((item) => item.id)).toEqual(['a'])
  })

  it('keeps an object that is still being saved', () => {
    const current = [row('local-123', 'EUR_USD'), row('a', 'EUR_USD')]

    const merged = mergeSymbolDrawings(current, [row('a', 'EUR_USD')], 'EUR_USD')

    expect(merged.map((item) => item.id).sort()).toEqual(['a', 'local-123'])
  })

  it('keeps an optimistic object even when the read comes back empty', () => {
    const merged = mergeSymbolDrawings([row('local-9', 'EUR_USD')], [], 'EUR_USD')

    expect(merged.map((item) => item.id)).toEqual(['local-9'])
  })

  it('keeps the later edit when the read is older', () => {
    const mine = row('a', 'EUR_USD', 1.3000, 2_000)
    const theirs = row('a', 'EUR_USD', 1.1000, 1_000)

    const merged = mergeSymbolDrawings([mine], [theirs], 'EUR_USD')

    expect(merged[0].points[0].p).toBe(1.3000)
  })

  it('takes the other device\'s version when it is newer', () => {
    const mine = row('a', 'EUR_USD', 1.3000, 1_000)
    const theirs = row('a', 'EUR_USD', 1.1000, 2_000)

    const merged = mergeSymbolDrawings([mine], [theirs], 'EUR_USD')

    expect(merged[0].points[0].p).toBe(1.1000)
    expect(merged[0].editedAtMs).toBe(2_000)
  })

  it('prefers the server version when neither side carries an edit time', () => {
    const merged = mergeSymbolDrawings(
      [row('a', 'EUR_USD', 1.3000)],
      [row('a', 'EUR_USD', 1.1000)],
      'EUR_USD'
    )

    expect(merged[0].points[0].p).toBe(1.1000)
  })
})
