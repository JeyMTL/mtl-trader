// @vitest-environment jsdom
import { describe, expect, it } from 'vitest'

import { focusableWithin, nextFocusTarget } from '@/lib/a11y'
import {
  objectState,
  objectSummary,
  type ObjectRow,
} from '@/components/chart-object-panel'

function row(partial: Partial<ObjectRow> & Pick<ObjectRow, 'kind'>): ObjectRow {
  return {
    id: 'o1',
    points: [],
    text: null,
    ...partial,
  }
}

const price = (value: number) => value.toFixed(2)
const time = (ms: number) => `t${ms}`

describe('dialog focus order', () => {
  it('wraps forward at the end and backward at the start', () => {
    const a = document.createElement('button')
    const b = document.createElement('button')
    const c = document.createElement('button')
    const items = [a, b, c]

    expect(nextFocusTarget(items, c, false)).toBe(a)
    expect(nextFocusTarget(items, a, true)).toBe(c)
    expect(nextFocusTarget(items, b, false)).toBe(c)
  })

  it('enters the list at the nearer end when focus is outside it', () => {
    const a = document.createElement('button')
    const b = document.createElement('button')
    expect(nextFocusTarget([a, b], document.body, false)).toBe(a)
    expect(nextFocusTarget([a, b], null, true)).toBe(b)
    expect(nextFocusTarget([], a, false)).toBeNull()
  })

  it('collects only what can actually hold focus', () => {
    const root = document.createElement('div')
    root.innerHTML = `
      <button id="first">One</button>
      <button id="off" disabled>Two</button>
      <input id="hidden" type="hidden" />
      <input id="check" type="checkbox" />
      <select id="pick"><option>a</option></select>
      <div id="skip" tabindex="-1">skip</div>
      <div hidden><button id="nested">not reachable</button></div>
      <button id="last" aria-hidden="true">decorative</button>
    `
    const ids = focusableWithin(root).map((element) => element.id)
    expect(ids).toEqual(['first', 'check', 'pick'])
  })
})

describe('object list text', () => {
  it('describes a level by its price', () => {
    const level = row({ kind: 'ray', points: [{ t: 0, p: 1.0845 }] })
    expect(objectSummary(level, price, time)).toBe('1.08')
    expect(objectState(level.style, '1h')).toEqual([])
  })

  it('describes a zone by its price and time span', () => {
    const zone = row({
      kind: 'rectangle',
      points: [
        { t: 1000, p: 1.07 },
        { t: 2000, p: 1.09 },
      ],
    })
    expect(objectSummary(zone, price, time)).toBe('1.07 to 1.09, t1000 to t2000')
  })

  it('collapses a flat shape to one price', () => {
    const flat = row({
      kind: 'rectangle',
      points: [
        { t: 1000, p: 1.08 },
        { t: 2000, p: 1.08 },
      ],
    })
    expect(objectSummary(flat, price, time)).toBe('1.08, t1000 to t2000')
  })

  it('says a vertical line by its time alone', () => {
    expect(objectSummary(row({ kind: 'vline', points: [{ t: 5000, p: 0 }] }), price, time)).toBe(
      't5000'
    )
  })

  it('survives an object with no anchors', () => {
    expect(objectSummary(row({ kind: 'trend' }), price, time)).toBe('No anchors')
  })

  it('reads the states a screen reader would otherwise never hear', () => {
    expect(objectState({ al: true }, '1h')).toEqual(['alert armed'])
    expect(objectState({ al: true, fd: true, lk: true, hd: true }, '1h')).toEqual([
      'alert fired',
      'locked',
      'hidden',
    ])
    expect(objectState({ iv: ['15m'] }, '1h')).toEqual(['not drawn on 1h'])
    expect(objectState(undefined, '1h')).toEqual([])
  })
})
