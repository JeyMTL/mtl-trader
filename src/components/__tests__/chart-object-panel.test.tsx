// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen } from '@testing-library/react'

import {
  ChartObjectBar,
  ChartObjectSettings,
  isAlertLine,
  objectName,
  visibleOnInterval,
  styleColour,
  styleFill,
  type ObjectRow,
} from '@/components/chart-object-panel'

const zone: ObjectRow = {
  id: 'row-1',
  kind: 'rectangle',
  points: [
    { t: 1_760_000_000_000, p: 1.25 },
    { t: 1_760_003_600_000, p: 1.26 },
  ],
  text: null,
  style: {},
}

describe('alert lines', () => {
  it('names a flagged level as an alert, and says when it has fired', () => {
    expect(objectName('ray')).toBe('Level')
    expect(objectName('ray', { al: true })).toBe('Alert line')
    expect(objectName('ray', { al: true, fd: true })).toBe('Alert line — fired')
    // The flag only means anything on a level.
    expect(objectName('trend', { al: true })).toBe('Trend line')
  })

  it('tells an alert line from a plain level', () => {
    expect(isAlertLine('ray', { al: true })).toBe(true)
    expect(isAlertLine('ray', {})).toBe(false)
    expect(isAlertLine('rectangle', { al: true })).toBe(false)
  })
})

describe('object visibility by interval', () => {
  it('an object with no list is drawn on every candle size', () => {
    expect(visibleOnInterval(undefined, '5m')).toBe(true)
    expect(visibleOnInterval({}, '1d')).toBe(true)
    expect(visibleOnInterval({ iv: [] }, '1h')).toBe(true)
  })

  it('a list limits the object to the intervals it names', () => {
    expect(visibleOnInterval({ iv: ['1h', '4h'] }, '1h')).toBe(true)
    expect(visibleOnInterval({ iv: ['1h', '4h'] }, '5m')).toBe(false)
  })
})

describe('chart object style helpers', () => {
  it('reads the phone ARGB colour and falls back to the chart mood', () => {
    // 0xFF45D29A is the phone palette's green.
    expect(styleColour({ c: 0xff45d29a }, false)).toBe('#45d29a')
    expect(styleColour({}, true)).toBe('#60a5fa')
    expect(styleColour({}, false)).toBe('#94a3b8')
  })

  it('turns a fill percent into canvas alpha, with the quiet default', () => {
    expect(styleFill({ f: 50 }, '#ffffff', false)).toBe('rgba(255, 255, 255, 0.5)')
    expect(styleFill({}, '#000000', false)).toBe('rgba(0, 0, 0, 0.08)')
    // A percentage outside the slider's range cannot paint the chart over.
    expect(styleFill({ f: 400 }, '#000000', false)).toBe('rgba(0, 0, 0, 1)')
  })

  it('names the objects the way the phone does', () => {
    expect(objectName('rectangle')).toBe('Zone')
    expect(objectName('fib')).toBe('Fib retracement')
  })
})

describe('ChartObjectBar', () => {
  afterEach(() => cleanup())

  it('restyles in one tap and clones without touching the original', () => {
    const onStyle = vi.fn()
    const onClone = vi.fn()
    render(
      <ChartObjectBar
        row={zone}
        onStyle={onStyle}
        onClone={onClone}
        onDelete={() => {}}
        onOpenSettings={() => {}}
      />
    )

    fireEvent.click(screen.getByLabelText('Thicker line'))
    expect(onStyle).toHaveBeenCalledWith({ w: 3 })

    fireEvent.click(screen.getByRole('button', { name: /Dashed/i }))
    expect(onStyle).toHaveBeenCalledWith({ d: true, dt: false })
    fireEvent.click(screen.getByRole('button', { name: /Dotted/i }))
    expect(onStyle).toHaveBeenCalledWith({ dt: true, d: false })

    fireEvent.click(screen.getByTitle('Clone'))
    expect(onClone).toHaveBeenCalled()
  })

  it('offers a fill only for objects that have a body', () => {
    const { rerender } = render(
      <ChartObjectBar
        row={zone}
        onStyle={() => {}}
        onClone={() => {}}
        onDelete={() => {}}
        onOpenSettings={() => {}}
      />
    )
    expect(screen.getByLabelText('Fill opacity')).toBeTruthy()

    rerender(
      <ChartObjectBar
        row={{ ...zone, kind: 'ray', points: [{ t: 0, p: 1.1 }] }}
        onStyle={() => {}}
        onClone={() => {}}
        onDelete={() => {}}
        onOpenSettings={() => {}}
      />
    )
    expect(screen.queryByLabelText('Fill opacity')).toBeNull()
  })
})

describe('ChartObjectSettings', () => {
  afterEach(() => cleanup())

  it('applies style edits only when Ok is pressed', () => {
    const onSave = vi.fn()
    const onClose = vi.fn()
    render(
      <ChartObjectSettings
        row={zone}
        onSave={onSave}
        onClose={onClose}
        onClone={() => {}}
        onDelete={() => {}}
      />
    )

    fireEvent.click(screen.getByText('3px'))
    fireEvent.click(screen.getByRole('button', { name: 'Ok' }))

    expect(onSave).toHaveBeenCalledTimes(1)
    expect(onSave.mock.calls[0][0].style.w).toBe(3)
    // Geometry is untouched by a restyle.
    expect(onSave.mock.calls[0][0].points[0].p).toBe(1.25)
  })

  it('leaves everything alone on Cancel', () => {
    const onSave = vi.fn()
    render(
      <ChartObjectSettings
        row={zone}
        onSave={onSave}
        onClose={() => {}}
        onClone={() => {}}
        onDelete={() => {}}
      />
    )

    fireEvent.click(screen.getByText('4px'))
    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }))
    expect(onSave).not.toHaveBeenCalled()
  })

  it('edits an anchor price and its time from the coordinates tab', () => {
    const onSave = vi.fn()
    render(
      <ChartObjectSettings
        row={zone}
        onSave={onSave}
        onClose={() => {}}
        onClone={() => {}}
        onDelete={() => {}}
      />
    )

    fireEvent.click(screen.getByRole('button', { name: /coordinates/i }))
    fireEvent.change(screen.getByLabelText('Anchor 2 price'), { target: { value: '1.27' } })
    fireEvent.click(screen.getByRole('button', { name: 'Ok' }))

    expect(onSave.mock.calls[0][0].points[1].p).toBe(1.27)
  })
})
