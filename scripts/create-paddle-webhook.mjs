#!/usr/bin/env node
/**
 * Creates the notification destination this app needs, or reports the one that
 * already exists.
 *
 *   node --env-file=.env.live scripts/create-paddle-webhook.mjs --dry-run
 *   node --env-file=.env.live scripts/create-paddle-webhook.mjs
 *
 * The dashboard path for this moved: Paddle's own docs now say
 * Events → Notifications (older guides still say Developer Tools →
 * Notifications, which is why it can be hard to find). This script is the
 * alternative when the menu will not cooperate.
 *
 * `--dry-run` only reads, so it is safe to point at an account that already has
 * a destination. Running for real is idempotent on the URL: an existing active
 * destination for the same endpoint is reported instead of duplicated — Paddle
 * allows only 10 active destinations.
 */

const ENDPOINT =
  (process.env.PADDLE_WEBHOOK_URL || '').trim() ||
  'https://mtl-trader.vercel.app/api/webhooks/paddle'

const EVENTS = ['transaction.completed', 'subscription.canceled', 'adjustment.created']
const DESCRIPTION = 'MTL Trader — subscriptions and refunds'

const dryRun = process.argv.includes('--dry-run')

/**
 * Event names, whichever shape the API returns.
 *
 * The list endpoint has been seen to return `subscribed_events` as objects
 * rather than strings, which made a string comparison report every event as
 * missing on a destination that was subscribed to all 56 of them.
 */
const eventNames = (value) =>
  (Array.isArray(value) ? value : [])
    .map((entry) => (typeof entry === 'string' ? entry : entry?.name ?? ''))
    .filter(Boolean)

const key = (process.env.PADDLE_API_KEY || '').trim()
if (!key) {
  console.log('PADDLE_API_KEY is not set. Run with --env-file=.env.live.')
  process.exitCode = 2
} else {
  const base =
    (process.env.PADDLE_ENVIRONMENT || '').toLowerCase() === 'production'
      ? 'https://api.paddle.com'
      : 'https://sandbox-api.paddle.com'

  async function call(path, init = {}) {
    const response = await fetch(`${base}${path}`, {
      ...init,
      headers: {
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
        ...(init.headers || {}),
      },
      signal: AbortSignal.timeout(20000),
    })
    const body = await response.json().catch(() => ({}))
    return { status: response.status, body }
  }

  const existing = await call('/notification-settings?per_page=100')
  if (existing.status !== 200) {
    console.log(`Could not list destinations: HTTP ${existing.status}`)
    console.log(existing.body?.error?.detail || '')
    process.exitCode = 1
  } else {
    const rows = existing.body?.data ?? []
    const match = rows.find((row) => (row.destination || '').trim() === ENDPOINT)

    console.log(`\n  ${base}`)
    console.log(`  ${rows.length} destination${rows.length === 1 ? '' : 's'} on this account:`)
    for (const row of rows) {
      const state = row.active === false ? 'inactive' : 'active'
      const count = eventNames(row.subscribed_events).length
      console.log(`    ${row.id}  ${state}  ${row.destination}  (${count} events)`)
    }

    if (match) {
      console.log(`\n  This endpoint is already registered as ${match.id}.`)
      const events = eventNames(match.subscribed_events)
      const missing = EVENTS.filter((event) => !events.includes(event))
      if (missing.length > 0) {
        console.log(`  Subscribed events missing: ${missing.join(', ')}`)
        console.log('  Add them in Events → Notifications → the destination → Edit.')
      } else {
        console.log('  All three events this app needs are subscribed.')
      }
      if (match.endpoint_secret_key) {
        console.log(`  Secret key: ${match.endpoint_secret_key}`)
      } else {
        console.log('  The API did not return the secret for an existing destination.')
        console.log('  Copy it from Events → Notifications → the destination, or rotate it there.')
      }
      process.exitCode = 0
    } else if (dryRun) {
      console.log(`\n  No destination for ${ENDPOINT} yet — a real run would create it.`)
      process.exitCode = 0
    } else {
      const created = await call('/notification-settings', {
        method: 'POST',
        body: JSON.stringify({
          description: DESCRIPTION,
          type: 'url',
          destination: ENDPOINT,
          subscribed_events: EVENTS,
          api_version: 1,
        }),
      })

      if (created.status >= 200 && created.status < 300) {
        const row = created.body?.data ?? {}
        console.log(`\n  Created ${row.id} → ${ENDPOINT}`)
        console.log(`  Events: ${EVENTS.join(', ')}`)
        console.log(`\n  PADDLE_WEBHOOK_SECRET=${row.endpoint_secret_key ?? '(not returned)'}`)
        console.log('\n  Paste that into Vercel as PADDLE_WEBHOOK_SECRET, Production scope.')
        process.exitCode = 0
      } else {
        console.log(`\n  Creating the destination failed: HTTP ${created.status}`)
        console.log(created.body?.error?.detail || '')
        process.exitCode = 1
      }
    }
  }
}
