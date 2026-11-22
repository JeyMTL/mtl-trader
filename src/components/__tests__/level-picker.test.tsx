// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, render, screen, waitFor } from '@testing-library/react'

class StubResizeObserver {
  observe() {}
  unobserve() {}
  disconnect() {}
}

import { LevelPicker, levelDecimals } from '@/components/level-picker'

type MockResponse = { ok: boolean; json: () => Promise<unknown> }

const fetchMock = vi.fn<() => Promise<MockResponse>>(async () => ({
  ok: true,
  json: async () => ({ candles: [] }),
}))

describe('LevelPicker', () => {
  beforeEach(() => {
    vi.stubGlobal('ResizeObserver', StubResizeObserver)
    vi.stubGlobal('fetch', fetchMock)
    fetchMock.mockClear()
  })

  afterEach(() => cleanup())

  it('asks the feed for the trade’s own symbol, suffix and all', async () => {
    render(
      <LevelPicker
        symbol="XAUUSDM"
        side="BUY"
        initial={{ entry: null, stop: null, take: null }}
        onApply={() => {}}
        onClose={() => {}}
      />
    )

    await waitFor(() => expect(screen.getByText(/XAUUSDM/)).toBeTruthy())
    // The route peels the broker suffix; the header keeps the trader's symbol
    // because that is the one they recognise.
    expect(fetchMock).toHaveBeenCalledWith(
      expect.stringContaining('/api/market/candles?symbol=XAUUSDM&interval=M15'),
      expect.anything()
    )
  })

  it('shows the feed’s own refusal instead of an empty chart', async () => {
    fetchMock.mockImplementationOnce(async () => ({
      ok: false,
      json: async () => ({ error: 'No chart data for XAU_USD right now.' }),
    }))

    render(
      <LevelPicker
        symbol="XAUUSD"
        side="BUY"
        initial={{ entry: null, stop: null, take: null }}
        onApply={() => {}}
        onClose={() => {}}
      />
    )

    await waitFor(() =>
      expect(screen.getByText('No chart data for XAU_USD right now.')).toBeTruthy()
    )
  })

  it('cannot apply levels before an entry is pinned', async () => {
    render(
      <LevelPicker
        symbol="EURUSD"
        side="BUY"
        initial={{ entry: null, stop: null, take: null }}
        onApply={() => {}}
        onClose={() => {}}
      />
    )

    const apply = screen.getByRole('button', { name: /Use these levels/i }) as HTMLButtonElement
    expect(apply.disabled).toBe(true)
  })

  it('reads decimals from the price’s own magnitude', () => {
    expect(levelDecimals(1.09846)).toBe(5)
    expect(levelDecimals(157.95)).toBe(2)
    expect(levelDecimals(3595.738)).toBe(2)
  })
})
