#!/usr/bin/env node
/**
 * Verifies the session buckets against the data, not just the schema.
 *
 * `trade_page(p_session => …)` and `session_stats()` both bucket trades by the
 * UTC hour of their open time. A schema check (does the function exist?) cannot
 * tell you whether the boundaries are right, and an off-by-one — 09:00 counted
 * as Asian, say — is invisible until a customer notices their numbers moving.
 *
 * This reads the trader's own rows, buckets them here with the same windows, and
 * compares that against what both RPCs answer. It needs a real session, because
 * both functions key on `auth.uid()`; the service-role key carries no user and
 * would answer zero.
 *
 *   node --env-file=.env.local scripts/check-session-filter.mjs --token=<access token>
 *   # or export SUPABASE_ACCESS_TOKEN
 *
 * Get a token from a signed-in browser console:
 *   JSON.parse(localStorage.getItem('sb-<project-ref>-auth-token')).access_token
 *
 * Exits 0 when every session matches, 1 when one does not, 2 when it cannot run.
 */

const url = (process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL || '')
  .trim()
  .replace(/\/+$/, '')

const key = (
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
  process.env.SUPABASE_ANON_KEY ||
  ''
).trim()

const tokenArg = process.argv.find((arg) => arg.startsWith('--token='))
const token = (
  tokenArg ? tokenArg.slice('--token='.length) : process.env.SUPABASE_ACCESS_TOKEN || ''
).trim()

/** The windows shared with the SQL and the Flutter client. Half-open, UTC. */
const WINDOWS = {
  asian: { firstHour: 0, lastHour: 9 },
  london: { firstHour: 7, lastHour: 16 },
  newyork: { firstHour: 12, lastHour: 21 },
  sydney: { firstHour: 21, lastHour: 6 },
}

const SESSIONS = ['asian', 'london', 'newyork', 'sydney']

function inSession(hour, window) {
  if (window.firstHour < window.lastHour) {
    return hour >= window.firstHour && hour < window.lastHour
  }
  return hour >= window.firstHour || hour < window.lastHour
}

function round2(value) {
  return Math.round(value * 100) / 100
}

async function request(path, { method = 'GET', body } = {}) {
  const response = await fetch(`${url}${path}`, {
    method,
    headers: {
      apikey: key,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  const payload = await response.json().catch(() => null)
  if (!response.ok) {
    const detail = payload?.message || payload?.error || `HTTP ${response.status}`
    if (payload?.code === 'PGRST202' || /could not find the function/i.test(detail)) {
      throw new Error(
        `${detail} — apply supabase/migrations/20261104_trade_page_session_filter.sql ` +
          'and 20261105_session_stats.sql first.'
      )
    }
    throw new Error(detail)
  }
  return payload
}

async function main() {
  if (!url) {
    console.error('✖ Set NEXT_PUBLIC_SUPABASE_URL (or SUPABASE_URL)')
    return 2
  }
  if (!key) {
    console.error('✖ Set NEXT_PUBLIC_SUPABASE_ANON_KEY (or SUPABASE_ANON_KEY)')
    return 2
  }
  if (!token) {
    console.error(
      '✖ Give a user access token with --token=<jwt> (or SUPABASE_ACCESS_TOKEN).\n' +
        '  auth.uid() is what these functions filter by, so an anonymous or service key cannot test them.'
    )
    return 2
  }

  // Every open time this trader owns, paged because PostgREST caps one response.
  const rows = []
  for (let page = 0; page < 200; page++) {
    const batch = await request(
      `/rest/v1/trades?select=open_time,pnl&order=created_at.desc&limit=1000&offset=${page * 1000}`
    )
    if (!Array.isArray(batch) || batch.length === 0) break
    rows.push(...batch)
    if (batch.length < 1000) break
  }

  const expected = Object.fromEntries(
    SESSIONS.map((session) => [session, { trades: 0, pnl: 0 }])
  )
  for (const row of rows) {
    if (!row.open_time) continue
    const hour = new Date(row.open_time).getUTCHours()
    const pnl = Number(row.pnl) || 0
    for (const session of SESSIONS) {
      if (!inSession(hour, WINDOWS[session])) continue
      expected[session].trades += 1
      expected[session].pnl += pnl
    }
  }

  const aggregate = await request('/rest/v1/rpc/session_stats')
  const statsBySession = Object.fromEntries(
    (Array.isArray(aggregate) ? aggregate : []).map((row) => [row.session, row])
  )

  console.log(`checked ${rows.length} trades against ${url}\n`)
  console.log('session   rows   pnl(rows)   filter(total/pnl)   aggregate(trades/pnl)   win rate  result')

  let mismatches = 0
  for (const session of SESSIONS) {
    const filtered = await request('/rest/v1/rpc/trade_page', {
      method: 'POST',
      body: { p_limit: 1, p_offset: 0, p_filter: 'all', p_session: session },
    })
    const stats = statsBySession[session] ?? {}
    const want = expected[session]

    const pageTotal = Number(filtered?.total ?? 0)
    const pagePnl = round2(Number(filtered?.total_pnl ?? 0))
    const aggTrades = Number(stats.trades ?? 0)
    const aggPnl = round2(Number(stats.pnl ?? 0))
    const aggWins = Number(stats.wins ?? 0)
    const winRate = aggTrades > 0 ? `${Math.round((aggWins / aggTrades) * 100)}%` : '—'

    const ok =
      pageTotal === want.trades &&
      aggTrades === want.trades &&
      Math.abs(pagePnl - round2(want.pnl)) < 0.011 &&
      Math.abs(aggPnl - round2(want.pnl)) < 0.011
    if (!ok) mismatches += 1

    console.log(
      [
        session.padEnd(9),
        String(want.trades).padStart(4),
        round2(want.pnl).toFixed(2).padStart(10),
        `${pageTotal} / ${pagePnl.toFixed(2)}`.padStart(18),
        `${aggTrades} / ${aggPnl.toFixed(2)}`.padStart(22),
        winRate.padStart(8),
        ok ? '✔' : '✖',
      ].join('  ')
    )
  }

  console.log('')
  if (mismatches > 0) {
    console.error(`✖ ${mismatches} session(s) disagree with the rows they should describe`)
    return 1
  }
  console.log('✔ every session matches the rows it should describe')
  return 0
}

process.exitCode = await main().catch((error) => {
  console.error(`✖ ${error.message}`)
  return 2
})
