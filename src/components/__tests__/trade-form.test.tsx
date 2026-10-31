// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import type { ReactNode } from 'react'

type Row = Record<string, unknown>

const db = vi.hoisted(() => ({
  inserted: null as Row | null,
  updated: null as Row | null,
  editRow: null as Row | null,
  tradeCount: 0,
  limit: -1,
  push: vi.fn(),
}))

vi.mock('next/navigation', () => ({
  useRouter: () => ({ push: db.push, back: vi.fn(), replace: vi.fn() }),
}))

vi.mock('next/link', () => ({
  default: function MockLink({ href, children }: { href: string; children: ReactNode }) {
    return <a href={href}>{children}</a>
  },
}))

vi.mock('@/lib/supabase', () => {
  const from = (table: string) => {
    if (table === 'users') {
      return {
        select: () => ({
          eq: () => ({
            single: async () => ({
              data: {
                subscription_tier: 'pro',
                subscription_status: 'active',
                trial_ends_at: null,
                current_period_end: null,
              },
              error: null,
            }),
          }),
        }),
      }
    }

    const chain = {
      eq: () => chain,
      single: async () => ({ data: db.editRow, error: null }),
    }

    return {
      select: () => chain,
      insert: (payload: Row) => {
        db.inserted = payload
        // The form reads the new id back so media can be attached.
        return {
          error: null,
          select: () => ({
            single: async () => ({ data: { id: 'trade-1' }, error: null }),
          }),
        }
      },
      update: (payload: Row) => {
        db.updated = payload
        // The form scopes the write to both the id and the owner.
        return { eq: () => ({ eq: async () => ({ error: null }) }) }
      },
    }
  }

  return {
    supabase: {
      auth: {
        getUser: async () => ({ data: { user: { id: 'user-1', email: 'trader@example.com' } } }),
        getSession: async () => ({ data: { session: { access_token: 'token' } } }),
      },
      from,
      // Quota pre-check: the same count the insert trigger uses.
      rpc: async () => ({ data: db.tradeCount, error: null }),
    },
  }
})

vi.mock('@/lib/subscription', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/lib/subscription')>()
  return { ...actual, effectiveMaxTrades: () => db.limit }
})

import { TradeForm } from '@/components/trade-form'

function fill(name: string, value: string) {
  fireEvent.change(screen.getByLabelText(name), { target: { value } })
}

function fillRequired() {
  fill('Symbol', 'EURUSD')
  fill('Entry price', '1.1')
  fill('Exit price', '1.105')
  fill('Size (lots)', '1')
}

describe('TradeForm', () => {
  beforeEach(() => {
    db.inserted = null
    db.updated = null
    db.editRow = null
    db.tradeCount = 0
    db.limit = -1
    db.push.mockClear()
  })

  afterEach(() => {
    cleanup()
  })

  it('computes P&L, pips and risk in the live ticket', () => {
    render(<TradeForm mode="create" />)

    fill('Symbol', 'EURUSD')
    fill('Entry price', '1.1000')
    fill('Exit price', '1.1050')
    fill('Size (lots)', '1')

    expect(screen.getByText('+$500.00')).toBeTruthy()
    expect(screen.getByText(/\+50\.0 pips/)).toBeTruthy()
  })

  it('refuses to save without the required prices and size', () => {
    render(<TradeForm mode="create" />)

    fireEvent.click(screen.getByRole('button', { name: /Log trade/i }))

    expect(screen.getByText('A symbol is required.')).toBeTruthy()
    expect(screen.getByText('Entry, exit and size must all be greater than zero.')).toBeTruthy()
    expect(db.inserted).toBeNull()
  })

  it('suggests tags from the note and saves the chosen ones', async () => {
    render(<TradeForm mode="create" />)
    fillRequired()

    fireEvent.change(screen.getByLabelText(/What was the setup/i), {
      target: { value: 'London breakout, followed the plan and waited for the retest' },
    })

    fireEvent.click(screen.getByRole('button', { name: 'breakout' }))
    fireEvent.click(screen.getByRole('button', { name: /Log trade/i }))

    await waitFor(() => expect(db.inserted).not.toBeNull())
    expect(db.inserted?.tags).toEqual(['breakout'])
    expect(db.inserted?.pnl).toBeCloseTo(500)
    expect(db.push).toHaveBeenCalledWith('/dashboard/trades')
  })

  it('loads an existing trade and keeps its tags on update', async () => {
    db.editRow = {
      symbol: 'XAUUSD',
      type: 'SELL',
      entry_price: 2400,
      exit_price: 2390,
      lot_size: 0.5,
      stop_loss: null,
      take_profit: null,
      commission: 0,
      swap: 0,
      strategy: 'Reversal',
      notes: 'Took the reversal',
      tags: ['reversal', 'target-hit'],
      open_time: null,
      close_time: null,
    }

    render(<TradeForm mode="edit" tradeId="trade-1" />)

    await waitFor(() => expect((screen.getByLabelText('Symbol') as HTMLInputElement).value).toBe('XAUUSD'))
    expect(screen.getByText('reversal')).toBeTruthy()

    fireEvent.click(screen.getByRole('button', { name: /Save changes/i }))

    await waitFor(() => expect(db.updated).not.toBeNull())
    expect(db.updated?.tags).toEqual(['reversal', 'target-hit'])
    expect(db.updated?.pnl).toBeCloseTo(500)
  })

  it('explains the monthly quota instead of saving', async () => {
    db.limit = 2
    db.tradeCount = 2

    render(<TradeForm mode="create" />)
    fillRequired()
    fireEvent.click(screen.getByRole('button', { name: /Log trade/i }))

    await waitFor(() => expect(screen.getByText(/Monthly limit reached/i)).toBeTruthy())
    expect(db.inserted).toBeNull()
  })
})
