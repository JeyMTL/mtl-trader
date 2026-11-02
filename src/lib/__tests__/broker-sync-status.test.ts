import { describe, expect, it } from 'vitest'
import {
  STALE_PENDING_MS,
  emptyBrokerSyncReport,
  summarizeBrokerSync,
} from '@/lib/broker-sync-status'

const NOW = new Date('2026-11-02T12:00:00Z')
const minutesAgo = (minutes: number) =>
  new Date(NOW.getTime() - minutes * 60 * 1000).toISOString()

describe('broker sync summary', () => {
  it('is idle with no connections', () => {
    expect(summarizeBrokerSync([], NOW)).toEqual(emptyBrokerSyncReport('idle'))
  })

  it('is active when an account is connected and syncing', () => {
    const report = summarizeBrokerSync(
      [
        { status: 'connected', updated_at: minutesAgo(2), last_sync_at: minutesAgo(2) },
        { status: 'disconnected', updated_at: minutesAgo(60) },
      ],
      NOW
    )

    expect(report.verdict).toBe('active')
    expect(report.connected).toBe(1)
    expect(report.connections).toBe(2)
    expect(report.lastSyncAt).toBe(minutesAgo(2))
    expect(report.stalled).toBe(0)
  })

  it('is stalled when queued work has waited out a supervisor cycle', () => {
    const stale = Math.ceil(STALE_PENDING_MS / 60000) + 5
    const report = summarizeBrokerSync(
      [
        { status: 'pending', updated_at: minutesAgo(stale) },
        { status: 'connected', updated_at: minutesAgo(1), last_sync_at: minutesAgo(1) },
      ],
      NOW
    )

    expect(report.verdict).toBe('stalled')
    expect(report.stalled).toBe(1)
    expect(report.pending).toBe(1)
    expect(report.oldestPendingMinutes).toBe(stale)
  })

  it('counts a claimed-but-abandoned row as stalled too', () => {
    const stale = Math.ceil(STALE_PENDING_MS / 60000) + 30
    const report = summarizeBrokerSync(
      [{ status: 'connecting', updated_at: minutesAgo(stale) }],
      NOW
    )

    expect(report.verdict).toBe('stalled')
    expect(report.connecting).toBe(1)
    expect(report.stalled).toBe(1)
  })

  it('is active, not stalled, while a fresh row waits for its turn', () => {
    const report = summarizeBrokerSync(
      [{ status: 'pending', updated_at: minutesAgo(1) }],
      NOW
    )

    expect(report.verdict).toBe('active')
    expect(report.stalled).toBe(0)
    expect(report.oldestPendingMinutes).toBe(1)
  })

  it('treats a missing timestamp as fresh rather than inventing a stall', () => {
    const report = summarizeBrokerSync([{ status: 'pending' }], NOW)
    expect(report.verdict).toBe('active')
    expect(report.stalled).toBe(0)
    expect(report.oldestPendingMinutes).toBe(0)
  })

  it('ignores unparsable timestamps', () => {
    const report = summarizeBrokerSync(
      [{ status: 'connected', updated_at: 'not-a-date', last_sync_at: 'nope' }],
      NOW
    )

    expect(report.lastSyncAt).toBeNull()
    expect(report.verdict).toBe('active')
  })
})
