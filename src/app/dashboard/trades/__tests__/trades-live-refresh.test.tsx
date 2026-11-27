// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, render, screen } from '@testing-library/react'
import type { ReactNode } from 'react'

const state = vi.hoisted(() => ({
  rows: [] as Record<string, unknown>[],
  reads: 0,
  // Handlers registered on the realtime channel, so a test can play the server's
  // part and fire an insert.
  handlers: [] as Array<() => void>,
}))

const channel = {
  on: (_event: string, _filter: unknown, handler: () => void) => {
    state.handlers.push(handler)
    return channel
  },
  subscribe: () => channel,
}

vi.mock('next/link', () => ({
  default: function MockLink({ href, children }: { href: string; children: ReactNode }) {
    return <a href={href}>{children}</a>
  },
}))

vi.mock('@/lib/supabase', () => ({
  supabase: {
    channel: () => channel,
    removeChannel: async () => {},
    rpc: async () => {
      state.reads += 1
      return {
        data: { trades: state.rows, total: state.rows.length, total_pnl: 0 },
        error: null,
      }
    },
    from: () => ({ delete: () => ({ eq: async () => ({ error: null }) }) }),
    auth: { getUser: async () => ({ data: { user: { id: 'u1' } } }) },
  },
}))

import TradesPage from '@/app/dashboard/trades/page'

function trade(id: string, symbol: string) {
  return {
    id,
    symbol,
    type: 'BUY',
    entry_price: 19000,
    exit_price: 19100,
    lot_size: 0.1,
    stop_loss: null,
    take_profit: null,
    pnl: 10,
    commission: 0,
    swap: 0,
    open_time: '2026-11-27T18:00:00+00:00',
    close_time: '2026-11-27T19:38:24+00:00',
    strategy: '',
    notes: null,
    tags: null,
    ticket: null,
    created_at: '2026-11-27T19:38:25+00:00',
  }
}

beforeEach(() => {
  state.rows = []
  state.reads = 0
  state.handlers = []
})

afterEach(cleanup)

describe('Trades list live refresh', () => {
  it('shows a trade journaled while the list is already open', async () => {
    state.rows = [trade('a', 'BTCUSDM')]
    render(<TradesPage />)

    expect((await screen.findAllByText('BTCUSDM')).length).toBeGreaterThan(0)
    const readsBefore = state.reads

    // The supervisor writes the close; realtime fires on the open page.
    state.rows = [trade('b', 'ETHUSDM'), ...state.rows]
    for (const handler of state.handlers) handler()

    // Past the 600 ms coalescing window.
    expect((await screen.findAllByText('ETHUSDM', undefined, { timeout: 3000 })).length)
      .toBeGreaterThan(0)
    expect(state.reads).toBeGreaterThan(readsBefore)
  })

  it('re-reads when the tab comes back to the foreground', async () => {
    state.rows = [trade('a', 'BTCUSDM')]
    render(<TradesPage />)
    expect((await screen.findAllByText('BTCUSDM')).length).toBeGreaterThan(0)
    const readsBefore = state.reads

    state.rows = [trade('c', 'XAUUSDM'), ...state.rows]
    document.dispatchEvent(new Event('visibilitychange'))

    expect((await screen.findAllByText('XAUUSDM', undefined, { timeout: 3000 })).length)
      .toBeGreaterThan(0)
    expect(state.reads).toBeGreaterThan(readsBefore)
  })
})
