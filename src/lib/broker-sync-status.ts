/**
 * What the hosted MT5 connection set says about the sync supervisor.
 *
 * The supervisor that logs into brokers lives on our own Windows hosts, outside
 * the Next.js deploy. When it stops, nothing fails loudly: connections sit at
 * `pending`, the customer's card spins, and the app itself is perfectly healthy.
 * `/api/health` reports the verdict this module computes so that state is visible
 * from the outside, without anyone opening the database.
 *
 * Aggregates only — counts, a verdict and timestamps. No broker name, server or
 * account number leaves the table, because the endpoint is public.
 */

export interface BrokerConnectionRow {
  status: string
  /** Last write to the row: when it was queued, claimed or synced. */
  updated_at?: string | null
  last_sync_at?: string | null
}

export type SupervisorVerdict = 'idle' | 'active' | 'stalled' | 'unknown'

export interface BrokerSyncReport {
  /**
   * `stalled` means queued work has gone unclaimed for longer than a supervisor
   * cycle should take — the symptom of a supervisor that is not running.
   * `active` means either work was queued recently or an account synced.
   */
  verdict: SupervisorVerdict
  connections: number
  pending: number
  connecting: number
  connected: number
  /** Rows queued or claimed for longer than [STALE_PENDING_MS]. */
  stalled: number
  lastSyncAt: string | null
  /** Age of the oldest queued/claimed row, in minutes; null when there is none. */
  oldestPendingMinutes: number | null
}

/**
 * Ten minutes. The supervisor sleeps `CYCLE_SECONDS` (default 120s) between
 * passes, so a row older than this has missed several chances to be claimed.
 */
export const STALE_PENDING_MS = 10 * 60 * 1000

export function emptyBrokerSyncReport(
  verdict: SupervisorVerdict = 'unknown'
): BrokerSyncReport {
  return {
    verdict,
    connections: 0,
    pending: 0,
    connecting: 0,
    connected: 0,
    stalled: 0,
    lastSyncAt: null,
    oldestPendingMinutes: null,
  }
}

/** Age of a row, or 0 when the timestamp is missing or unparsable. */
function ageMs(row: BrokerConnectionRow, now: number): number {
  if (!row.updated_at) return 0
  const stamp = new Date(row.updated_at).getTime()
  if (!Number.isFinite(stamp)) return 0
  return Math.max(0, now - stamp)
}

export function summarizeBrokerSync(
  rows: BrokerConnectionRow[],
  now: Date = new Date()
): BrokerSyncReport {
  const nowMs = now.getTime()
  const report = emptyBrokerSyncReport('idle')
  report.connections = rows.length

  let oldestPending: number | null = null
  let lastSync: number | null = null

  for (const row of rows) {
    if (row.status === 'pending') report.pending += 1
    if (row.status === 'connecting') report.connecting += 1
    if (row.status === 'connected') report.connected += 1

    if (row.last_sync_at) {
      const synced = new Date(row.last_sync_at).getTime()
      if (Number.isFinite(synced) && (lastSync === null || synced > lastSync)) {
        lastSync = synced
      }
    }

    if (row.status !== 'pending' && row.status !== 'connecting') continue
    const age = ageMs(row, nowMs)
    if (age > STALE_PENDING_MS) report.stalled += 1
    if (oldestPending === null || age > oldestPending) oldestPending = age
  }

  report.lastSyncAt = lastSync === null ? null : new Date(lastSync).toISOString()
  report.oldestPendingMinutes =
    oldestPending === null ? null : Math.floor(oldestPending / 60000)

  // A stalled row outranks everything: it is the one state that names a cause.
  report.verdict =
    report.stalled > 0
      ? 'stalled'
      : report.pending > 0 || report.connecting > 0 || report.connected > 0
        ? 'active'
        : 'idle'

  return report
}
