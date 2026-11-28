// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, render, screen } from '@testing-library/react'
import type { ReactNode } from 'react'

const state = vi.hoisted(() => ({
  // What GET /api/sync answers. The route is covered in
  // `src/lib/__tests__/sync-and-broker-routes.test.ts`; here it is the page's
  // reaction to a refusal that matters.
  syncResponse: {} as Record<string, unknown>,
}))

vi.mock('next/navigation', () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}))

vi.mock('next/link', () => ({
  default: function MockLink({ href, children }: { href: string; children: ReactNode }) {
    return <a href={href}>{children}</a>
  },
}))

vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: {
      getUser: async () => ({ data: { user: { id: 'u1', email: 'free@example.com' } } }),
    },
  },
}))

vi.mock('@/lib/api', () => ({
  authedFetch: async () => ({ ok: false, json: async () => state.syncResponse }),
}))

vi.mock('@/components/toast', () => ({ useToast: () => ({ toast: vi.fn() }) }))
vi.mock('@/components/broker-connect', () => ({ default: () => <div /> }))
vi.mock('@/components/broker-picker', () => ({
  default: () => <div />,
  ServerSuggestions: () => null,
}))

import SyncPage from '@/app/dashboard/sync/page'

beforeEach(() => {
  state.syncResponse = {}
})

afterEach(cleanup)

describe('MT5 sync page', () => {
  it('tells a free account why sync is unavailable, with a way to fix it', async () => {
    state.syncResponse = {
      code: 'upgrade_required',
      error:
        'MT5 auto sync is included from Basic. On the free plan, import your closed trades from the Import page, or choose a plan to sync them automatically.',
    }

    render(<SyncPage />)

    expect(await screen.findByText('Auto sync is not part of your plan')).toBeTruthy()
    expect(screen.getByText(/On the free plan, import your closed trades/)).toBeTruthy()
    expect(screen.getByText('Compare plans')).toBeTruthy()
    expect(screen.getByText('Import history by hand')).toBeTruthy()

    // The setup guide needs a token the server will not issue, so none of it
    // may be on screen: an empty token box is what sent traders to the EA.
    expect(screen.queryByText('Desktop agent token')).toBeNull()
    expect(screen.queryByText('MT5 Expert Advisor')).toBeNull()
    expect(screen.queryByText('Download setup file')).toBeNull()
  })

  it('asks a dead session to sign in instead of printing Unauthorized', async () => {
    state.syncResponse = { error: 'Unauthorized' }

    render(<SyncPage />)

    expect(await screen.findByText('Your session expired')).toBeTruthy()
    expect(screen.getByText('Sign in again to load your sync token.')).toBeTruthy()
    expect(screen.queryByText('Unauthorized')).toBeNull()
  })

  it('shows the token when the plan allows sync', async () => {
    state.syncResponse = { token: 'tok_live_123', isNew: false }

    render(<SyncPage />)

    expect(await screen.findByText('Desktop agent token')).toBeTruthy()
    expect(screen.getByText('tok_live_123')).toBeTruthy()
    expect(screen.queryByText('Auto sync is not part of your plan')).toBeNull()
  })
})
