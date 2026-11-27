// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, render, screen, within } from '@testing-library/react'

class StubResizeObserver {
  observe() {}
  unobserve() {}
  disconnect() {}
}

vi.stubGlobal('ResizeObserver', StubResizeObserver)

// The view reaches the network only for the AI review and the quota badge; both
// are optional here, so they are stubbed rather than exercised.
vi.mock('@/lib/api', () => ({
  authedFetch: async () => ({ ok: false, json: async () => ({}) }),
}))

vi.mock('@/components/setup-matrix', () => ({ SetupMatrix: () => null }))
vi.mock('@/components/excursion-card', () => ({ ExcursionCard: () => null }))
vi.mock('@/components/onboarding', () => ({ Onboarding: () => null }))

import { AnalyticsView } from '@/components/analytics-view'
import { DashboardView } from '@/components/dashboard-view'
import {
  EMPTY_SUMMARY,
  EMPTY_TIME_STATS,
  type EquityPoint,
  type StrategyStat,
} from '@/types/journal'

function analyticsProps({
  rMultiples = [],
  sessionHeat = [],
  strategyStats = [],
}: {
  rMultiples?: number[]
  sessionHeat?: Array<{ session: string; weekday: number; pnl: number; trades: number }>
  strategyStats?: StrategyStat[]
} = {}) {
  return {
    summary: EMPTY_SUMMARY,
    equity: [] as EquityPoint[],
    symbols: [],
    tagStats: [],
    breakdowns: { weekdays: [], months: [] },
    depositsTotal: 0,
    timeStats: EMPTY_TIME_STATS,
    sessionStats: [],
    sessionStatsMissing: false,
    strategyStats,
    strategyStatsMissing: false,
    rMultiples,
    sessionHeat,
  }
}

afterEach(cleanup)

describe('analytics R-multiple card', () => {
  it('shows the average and the trade count once stops exist', () => {
    render(<AnalyticsView {...analyticsProps({ rMultiples: [2, -1, 0.5, 3.5] })} />)
    expect(screen.getByText('R-multiple distribution')).toBeTruthy()
    expect(screen.getByText('4 closed trades sized against the stop they risked.')).toBeTruthy()
    expect(screen.getByText('Average +1.25R')).toBeTruthy()
  })

  it('asks for a stop instead of drawing an empty histogram', () => {
    render(<AnalyticsView {...analyticsProps()} />)
    expect(screen.getByText('No risk multiples yet')).toBeTruthy()
    expect(screen.queryByText('Average +0.00R')).toBeNull()
  })
})

describe('analytics session heatmap', () => {
  it('labels a cell with its session, weekday and window', () => {
    render(
      <AnalyticsView
        {...analyticsProps({ sessionHeat: [{ session: 'london', weekday: 2, pnl: 120, trades: 3 }] })}
      />
    )
    const cell = screen.getByTitle(/London Tue/)
    expect(cell.textContent).toContain('120')
    expect(cell.getAttribute('title')).toContain('3 trades')
  })

  it('leaves an untraded day visibly empty', () => {
    render(<AnalyticsView {...analyticsProps({ sessionHeat: [] })} />)
    expect(screen.queryByTitle(/London Tue/)).toBeNull()
  })
})

describe('strategy leaderboard', () => {
  const strategies: StrategyStat[] = [
    // The busiest label has the bigger total; the leaderboard ranks the average.
    { strategy: 'Scalping', trades: 10, wins: 6, losses: 4, pnl: 100, win_rate: 60 },
    { strategy: 'Breakout', trades: 2, wins: 2, losses: 0, pnl: 300, win_rate: 100 },
  ]

  it('ranks by what one trade earns', () => {
    render(<AnalyticsView {...analyticsProps({ strategyStats: strategies })} />)
    const card = screen.getByText('Strategy leaderboard').closest('div.bg-surface')
    const table = within(card as HTMLElement).getByRole('table')
    const rows = within(table).getAllByRole('row').slice(1)
    expect(rows[0].textContent).toContain('Breakout')
    expect(rows[0].textContent).toContain('+$150.00')
    expect(rows[1].textContent).toContain('Scalping')
  })

  it('still shows the total beside the per-trade figure', () => {
    render(<AnalyticsView {...analyticsProps({ strategyStats: strategies })} />)
    const card = screen.getByText('Strategy leaderboard').closest('div.bg-surface')
    expect(within(card as HTMLElement).getByText('$300.00')).toBeTruthy()
  })
})

describe('desk equity range', () => {
  function dashboardProps() {
    const equity: EquityPoint[] = [
      { day: '2026-08-01', cumulative: 0, pnl: 0, trades: 0 },
      { day: '2026-09-15', cumulative: 500, pnl: 500, trades: 4 },
      { day: '2026-11-20', cumulative: 800, pnl: 300, trades: 2 },
    ]
    return {
      summary: EMPTY_SUMMARY,
      equity,
      depositsTotal: 1000,
      recentTrades: [],
      preferences: {
        notifications_journal_reminders: false,
        notifications_monthly_overview: true,
      },
      dailyPnl: [],
      timeStats: EMPTY_TIME_STATS,
      journalFeed: [],
      sessionStats: [],
      sessionStatsMissing: false,
    }
  }

  it('offers four windows and starts on the month', () => {
    render(<DashboardView {...dashboardProps()} />)
    for (const label of ['1W', '1M', '3M', 'ALL']) {
      expect(screen.getByRole('tab', { name: label })).toBeTruthy()
    }
    expect(screen.getByRole('tab', { name: '1M' }).getAttribute('aria-selected')).toBe('true')
  })

  it('keeps the window pills off the daily bars', async () => {
    render(<DashboardView {...dashboardProps()} />)
    const daily = screen.getByRole('tab', { name: 'Daily' })
    await daily.click()
    expect(screen.queryByRole('tab', { name: '1W' })).toBeNull()
  })
})
