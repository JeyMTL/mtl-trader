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
  if (body.commit) console.log(`  commit ${body.commit}`)

  return response.ok && body.status === 'ok' ? 0 : 1
}

// Assigning exitCode instead of calling process.exit lets Node close the fetch
// socket first. A hard exit while that socket is still open asserts in libuv on
// Windows and reports a bogus 127 as the script's status.
process.exitCode = await main()
