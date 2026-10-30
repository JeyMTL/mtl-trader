import { describe, expect, it } from 'vitest'
import {
  formatHourRange,
  formatMinutes,
  hourlySeries,
  pickEdge,
  sessionPeriod,
  timeEdgeReport,
} from '@/lib/edge-window'
import type { TimeStats } from '@/types/journal'

const stats: TimeStats = {
  timezone: 'Europe/London',
  hours: [
    { hour: 8, trades: 5, wins: 4, losses: 1, pnl: 420 },
    { hour: 9, trades: 4, wins: 3, losses: 1, pnl: 180 },
    { hour: 14, trades: 6, wins: 1, losses: 5, pnl: -360 },
    { hour: 22, trades: 1, wins: 1, losses: 0, pnl: 900 },
  ],
  sessions: [
    { session: 'London', first_hour: 8, last_hour: 12, trades: 9, wins: 7, losses: 2, pnl: 600 },
    { session: 'New York', first_hour: 16, last_hour: 20, trades: 6, wins: 2, losses: 4, pnl: -260 },
  ],
  hold: { trades: 12, median_minutes: 95, average_minutes: 120 },
}

describe('edge-window', () => {
  it('labels an hour bucket as a clock range', () => {
    expect(formatHourRange(8)).toBe('08:00–09:00')
    expect(formatHourRange(23)).toBe('23:00–24:00')
    expect(formatHourRange(-1)).toBe('00:00–01:00')
  })

  it('builds a full 24-hour series with empty hours at zero', () => {
    const series = hourlySeries(stats)
    expect(series).toHaveLength(24)
    expect(series[8].pnl).toBe(420)
    expect(series[8].winRate).toBe(80)
    expect(series[3]).toMatchObject({ trades: 0, pnl: 0, label: '03:00–04:00' })
  })

  it('ignores lucky single trades when picking the best window', () => {
    const report = pickEdge(hourlySeries(stats), 3)
    expect(report.best?.label).toBe('08:00–09:00')
    expect(report.worst?.label).toBe('14:00–15:00')
  })

  it('reports sessions best and worst with the entry span', () => {
    const report = timeEdgeReport(stats, 3)
    expect(report.bestSession?.label).toBe('London (08:00–13:00)')
    expect(report.worstSession?.label).toBe('New York (16:00–21:00)')
    expect(report.bestHour?.pnl).toBe(420)
    expect(report.worstHour?.pnl).toBe(-360)
  })

  it('returns no best window when every qualifying window loses', () => {
    const losing = pickEdge(
      [
        { key: 'a', label: 'A', trades: 4, wins: 1, losses: 3, pnl: -20, winRate: 25 },
        { key: 'b', label: 'B', trades: 5, wins: 1, losses: 4, pnl: -80, winRate: 20 },
      ],
      3
    )
    expect(losing.best).toBeNull()
    expect(losing.worst?.key).toBe('b')
  })

  it('formats session rows and hold time', () => {
    const london = sessionPeriod(stats.sessions[0])
    expect(london.trades).toBe(9)
    expect(london.label).toBe('London (08:00–13:00)')
    expect(formatMinutes(95)).toBe('1h 35m')
    expect(formatMinutes(45)).toBe('45m')
    expect(formatMinutes(null)).toBe('—')
  })
})
