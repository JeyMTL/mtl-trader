/**
 * Which database functions this app depends on, and whether this deployment can
 * reach them.
 *
 * A half-migrated database is the failure mode that looks like a code bug: the
 * dashboard renders, the journal loads, and one panel is silently empty because
 * an RPC was never created. `/api/health` answers for the *deployment*; this
 * answers for the *schema*, per function, with the file to apply when one is
 * missing.
 *
 * Presence is judged on the argument names the app actually sends, not on the
 * bare function name. A renamed or dropped argument breaks every caller exactly
 * as a missing function does, and PostgREST reports both the same way, so
 * treating them as one is the honest answer: the app is broken either way.
 *
 * Nothing here executes a function. Every probe is sent as the anonymous role,
 * which holds no `EXECUTE` on any of them, so the expected answer is
 * "permission denied" and that is read as "present". The arguments are harmless
 * on purpose — a nil uuid, an unknown plan, a one-second window — because if a
 * future migration ever grants one of these to `anon`, the probe must still not
 * be able to change anything.
 */

const NIL_UUID = '00000000-0000-0000-0000-000000000000'

export interface RpcProbe {
  rpc: string
  /** Migration that creates it — what to apply when the probe says missing. */
  migration: string
  /** What stops working without it, in a reader's terms. */
  usedBy: string
  /** The argument names the app sends. */
  args: Record<string, unknown>
}

const CORE = '20261026_billing_lifecycle_and_scale.sql'

export const RPC_PROBES: readonly RpcProbe[] = [
  // ---------------------------------------------------------------- reads
  { rpc: 'trade_summary', migration: CORE, usedBy: 'dashboard, analytics, phone KPI strip', args: {} },
  { rpc: 'equity_curve', migration: CORE, usedBy: 'equity chart on dashboard and analytics', args: {} },
  { rpc: 'deposits_total', migration: CORE, usedBy: 'balance and drawdown maths', args: {} },
  { rpc: 'trade_breakdowns', migration: CORE, usedBy: 'weekday and monthly P&L charts', args: {} },
  { rpc: 'symbol_stats', migration: CORE, usedBy: 'performance by symbol', args: { p_limit: 1 } },
  { rpc: 'daily_pnl', migration: CORE, usedBy: 'calendar and daily P&L chart', args: { p_from: '2026-01-01', p_to: '2026-01-02' } },
  { rpc: 'day_trades', migration: CORE, usedBy: 'a day in the calendar', args: { p_day: '2026-01-01' } },
  { rpc: 'latest_trade_day', migration: CORE, usedBy: 'calendar opens on the last traded month', args: {} },
  { rpc: 'month_trade_count', migration: '20261031_month_trade_count.sql', usedBy: 'trade form and import quota display', args: {} },
  { rpc: 'tag_stats', migration: '20261027_trade_tags.sql', usedBy: 'performance by tag', args: { p_limit: 1 } },
  { rpc: 'time_stats', migration: '20261028_journal_media_and_time_stats.sql', usedBy: 'time edge report', args: {} },
  { rpc: 'journal_feed', migration: '20261028_journal_media_and_time_stats.sql', usedBy: 'latest journal entries', args: { p_limit: 1 } },
  {
    rpc: 'trade_page',
    migration: '20261104_trade_page_session_filter.sql',
    usedBy: 'trade log, its CSV export and the session filter',
    args: { p_limit: 1, p_offset: 0, p_search: null, p_filter: 'all', p_session: null },
  },
  { rpc: 'session_stats', migration: '20261105_session_stats.sql', usedBy: 'session strip, dashboard and analytics sessions', args: {} },
  { rpc: 'strategy_stats', migration: '20261107_strategy_stats.sql', usedBy: 'performance by strategy on analytics', args: { p_limit: 1 } },

  // ---------------------------------------------------- server-only, mutating
  // Probed for existence with arguments that make each one return early.
  { rpc: 'check_rate_limit', migration: CORE, usedBy: 'rate limiting on the public routes', args: { p_key: 'health-probe', p_limit: 1, p_window_ms: 1000 } },
  { rpc: 'sweep_rate_limits', migration: CORE, usedBy: 'reconcile cron', args: {} },
  { rpc: 'expire_lapsed_subscriptions', migration: CORE, usedBy: 'reconcile cron', args: {} },
  {
    rpc: 'apply_paid_order',
    migration: CORE,
    usedBy: 'PayPal capture, webhook and reconcile',
    args: { p_user_id: NIL_UUID, p_provider: 'probe', p_provider_event_id: 'probe', p_plan_id: 'probe', p_amount: 0 },
  },
  {
    rpc: 'revoke_paid_order',
    migration: CORE,
    usedBy: 'refunds, reversals and disputes',
    args: { p_user_id: NIL_UUID, p_provider: 'probe', p_provider_event_id: 'probe', p_plan_id: 'probe', p_amount: 0 },
  },
  {
    rpc: 'review_bank_payment_request',
    migration: '20260916_harden_payment_requests.sql',
    usedBy: 'admin approve and reject of bank transfers',
    args: { p_request_id: NIL_UUID, p_reviewer_id: NIL_UUID, p_action: 'approve' },
  },
  {
    rpc: 'delete_account_data',
    migration: CORE,
    usedBy: 'account deletion',
    args: { p_user_id: NIL_UUID },
  },
  {
    rpc: 'notification_trades',
    migration: CORE,
    usedBy: 'daily and weekly email summaries',
    args: { p_user_id: NIL_UUID, p_since: '2026-01-01T00:00:00.000Z' },
  },
]

export type RpcStatus = 'ready' | 'missing' | 'unknown'

export interface RpcReport {
  status: 'ok' | 'pending' | 'unknown'
  checked: number
  /** Functions this deployment answered for, by name. */
  ready: string[]
  /** Functions that do not exist with the argument names the app sends. */
  missing: { rpc: string; migration: string; usedBy: string }[]
  /** Functions that could not be reached — a network problem, not a schema one. */
  unknown: string[]
}

/**
 * Maps one PostgREST response onto a verdict.
 *
 * `PGRST202` covers both "no such function" and "no function with these
 * arguments", which is why the probe sends the app's real argument list: either
 * cause means a broken caller. A permission error is the *successful* case, since
 * the anonymous role is not meant to execute these.
 */
export function classifyRpcProbe(status: number, body: unknown): RpcStatus {
  const record = (body ?? {}) as { code?: unknown; message?: unknown }
  const code = typeof record.code === 'string' ? record.code : ''
  const message = typeof record.message === 'string' ? record.message : ''

  if (code === 'PGRST202' || /could not find the function/i.test(message)) {
    return 'missing'
  }
  if (status === 401 || status === 403 || code === '42501') return 'ready'
  if (status === 404) return 'missing'
  // Resolved and then refused by Postgres for any other reason (bad argument
  // type, RLS, a constraint): the function is there, which is the question.
  if (status >= 200) return 'ready'
  return 'unknown'
}

async function probe(
  base: string,
  anonKey: string,
  probe: RpcProbe
): Promise<RpcStatus> {
  try {
    const response = await fetch(`${base}/rest/v1/rpc/${probe.rpc}`, {
      method: 'POST',
      headers: {
        apikey: anonKey,
        Authorization: `Bearer ${anonKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(probe.args),
      cache: 'no-store',
      signal: AbortSignal.timeout(5000),
    })
    const body = await response.json().catch(() => null)
    return classifyRpcProbe(response.status, body)
  } catch {
    return 'unknown'
  }
}

/** Probes every dependency in parallel; a slow one cannot hold up the rest. */
export async function checkRpcs(
  supabaseUrl: string | undefined,
  anonKey: string | undefined
): Promise<RpcReport> {
  if (!supabaseUrl || !anonKey) {
    return { status: 'unknown', checked: 0, ready: [], missing: [], unknown: [] }
  }

  const base = supabaseUrl.replace(/\/+$/, '')
  const results = await Promise.all(
    RPC_PROBES.map(async (entry) => ({
      entry,
      status: await probe(base, anonKey, entry),
    }))
  )

  const report: RpcReport = {
    status: 'ok',
    checked: results.length,
    ready: [],
    missing: [],
    unknown: [],
  }

  for (const { entry, status } of results) {
    if (status === 'ready') {
      report.ready.push(entry.rpc)
    } else if (status === 'missing') {
      report.missing.push({
        rpc: entry.rpc,
        migration: entry.migration,
        usedBy: entry.usedBy,
      })
    } else {
      report.unknown.push(entry.rpc)
    }
  }

  report.status =
    report.missing.length > 0
      ? 'pending'
      : report.unknown.length > 0
        ? 'unknown'
        : 'ok'

  return report
}
