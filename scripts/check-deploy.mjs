#!/usr/bin/env node
/**
 * Deploy smoke check.
 *
 * Asks a running deployment whether it is actually wired up, using the same
 * `/api/health` endpoint a monitor would poll, and exits non-zero when the app
 * reports itself degraded. That makes it usable as a deploy gate:
 *
 *   node scripts/check-deploy.mjs https://your-domain
 *   node scripts/check-deploy.mjs http://localhost:3999
 *
 * With no argument it falls back to NEXT_PUBLIC_APP_URL.
 */

const base = (process.argv[2] || process.env.NEXT_PUBLIC_APP_URL || '')
  .trim()
  .replace(/\/+$/, '')

function line(label, ok, detail = '') {
  console.log(`${ok ? '✔' : '✖'} ${label}${detail ? ` — ${detail}` : ''}`)
}

async function main() {
  if (!base) {
    console.error('✖ Give a URL or set NEXT_PUBLIC_APP_URL')
    return 2
  }

  let response
  try {
    response = await fetch(`${base}/api/health`, {
      headers: { 'cache-control': 'no-cache' },
      signal: AbortSignal.timeout(20000),
    })
  } catch (error) {
    console.error(`✖ could not reach ${base}: ${error.message}`)
    return 1
  }

  const body = await response.json().catch(() => null)
  if (!body) {
    console.error(
      `✖ ${base}/api/health did not return JSON (HTTP ${response.status})`
    )
    return 1
  }

  console.log(`${base} — HTTP ${response.status}`)
  line('status', body.status === 'ok', body.status)
  line('database', body.database === 'ok', body.database)
  line('supabase url', Boolean(body.config?.supabaseUrl))
  line('anon key', Boolean(body.config?.supabaseAnonKey))
  line(
    'service role key',
    Boolean(body.config?.serviceRoleKey),
    body.config?.serviceRoleKey
      ? ''
      : 'profile creation and the cron routes will fail'
  )
  if (body.features?.avatars) {
    line(
      'avatars bucket',
      body.features.avatars === 'ready',
      body.features.avatars === 'ready'
        ? ''
        : body.features.avatars === 'missing'
          ? 'migration not applied — uploads will fail'
          : 'could not be determined'
    )
  }
  if (body.migrations) {
    const { status, checked, missing = [], unknown = [] } = body.migrations
    line(
      'database functions',
      status === 'ok',
      `${checked} probed${status === 'pending' ? ` — ${missing.length} missing` : ''}`
    )
    // Printed rather than folded into the exit code: a pending migration is
    // fixable in a minute, and failing the gate would leave the deploy-gate job
    // red for something the app tolerates.
    for (const entry of missing) {
      console.log(`    ✖ ${entry.rpc} is missing — apply supabase/migrations/${entry.migration}`)
      console.log(`      without it: ${entry.usedBy}`)
    }
    if (unknown.length > 0) {
      console.log(`    ? could not probe: ${unknown.join(', ')}`)
    }
  }
  if (body.sync) {
    const { verdict, connected = 0, pending = 0, stalled = 0, lastSyncAt } =
      body.sync
    // Printed, not part of the exit code: the sync supervisor runs on our own
    // Windows host, outside this deploy, and the app is healthy without it.
    line(
      'sync supervisor',
      verdict !== 'stalled' && verdict !== 'unknown',
      verdict === 'stalled'
        ? `${stalled} connection(s) unclaimed for over 10 minutes — is supervisor/mt5_supervisor.py running?`
        : verdict === 'unknown'
          ? 'could not be read'
          : `${connected} connected · ${pending} queued${lastSyncAt ? ` · last sync ${lastSyncAt}` : ''}`
    )
  }
  if (body.ai) {
    // Printed, not part of the exit code: no AI key is a valid deployment, and
    // the review explains itself with a 503. The provider name is the useful bit.
    line(
      'ai provider',
      body.ai.configured,
      body.ai.provider ?? 'not configured — the review answers 503'
    )
  }
  if (body.commit) console.log(`  commit ${body.commit}`)

  return response.ok && body.status === 'ok' ? 0 : 1
}

// Assigning exitCode instead of calling process.exit lets Node close the fetch
// socket first. A hard exit while that socket is still open asserts in libuv on
// Windows and reports a bogus 127 as the script's status.
process.exitCode = await main()
