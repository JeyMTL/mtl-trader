#!/usr/bin/env node
/**
 * Pre-flight for Paddle, sandbox or live.
 *
 *   node --env-file=.env.live scripts/check-paddle-live.mjs --live
 *   node --env-file=.env.live scripts/check-paddle-live.mjs --catalogue
 *
 * `--catalogue` lists the account's active prices and prints the four env lines,
 * matched by interval and amount, so no `pri_…` id is ever copied by hand — that
 * copy is how a monthly id ends up in a yearly slot.
 *
 * The default run only reads. Nothing here creates a transaction or charges a
 * card, because the point is to find the half-swapped deployment *before* a
 * customer does:
 *
 *   - a live key with `PADDLE_ENVIRONMENT` unset calls sandbox-api.paddle.com
 *     and 401s on every checkout;
 *   - a yearly slot holding a monthly price id charges $12 and then the webhook
 *     refuses to grant a year (`amount_mismatch`), so the customer pays for
 *     nothing.
 *
 * Exit codes: 0 ready, 1 a real problem, 2 cannot check (variables absent).
 *
 * The work happens inside `main()` and the code is returned rather than calling
 * `process.exit()`: an abrupt exit while undici still holds a socket trips a
 * libuv assertion on Windows and reports 127 instead of the real result.
 */

const args = new Set(process.argv.slice(2))
const expect = args.has('--live') ? 'live' : args.has('--sandbox') ? 'sandbox' : null

/** Must match `src/lib/plans.ts`; the plans-consistency test guards that side. */
const PLANS = {
  basic: { month: 1200, year: 12000 },
  pro: { month: 2900, year: 29000 },
}

const PRICE_VARS = [
  { plan: 'basic', interval: 'month', envVar: 'PADDLE_PRICE_BASIC' },
  { plan: 'pro', interval: 'month', envVar: 'PADDLE_PRICE_PRO' },
  { plan: 'basic', interval: 'year', envVar: 'PADDLE_PRICE_BASIC_ANNUAL' },
  { plan: 'pro', interval: 'year', envVar: 'PADDLE_PRICE_PRO_ANNUAL' },
]

const CURRENCY = (process.env.PADDLE_CURRENCY || 'USD').toUpperCase()

/** Real misconfiguration: a wrong interval, a wrong amount, a key/env mismatch. */
const faults = []
const notes = []
/** Variables this process could not see — which is not proof the deployment lacks them. */
const absent = []

function ok(label, detail) {
  console.log(`  ok    ${label.padEnd(34)} ${detail ?? ''}`.trimEnd())
}

function bad(label, detail) {
  faults.push(`${label}: ${detail}`)
  console.log(`  FAIL  ${label.padEnd(34)} ${detail ?? ''}`.trimEnd())
}

/**
 * A variable this shell cannot see.
 *
 * Kept apart from `bad` on purpose: a local `.env` that was never filled in is
 * not the same finding as a deployment wired to the wrong price, and reporting
 * both as "NOT ready" sends people hunting for a bug in the app.
 */
function absentVar(envVar, consequence) {
  absent.push(envVar)
  console.log(`  FAIL  ${envVar.padEnd(34)} ${consequence}`)
}

function info(label, detail) {
  notes.push(`${label}: ${detail}`)
  console.log(`  note  ${label.padEnd(34)} ${detail ?? ''}`.trimEnd())
}

function env(name) {
  return (process.env[name] || '').trim()
}

function short(value) {
  return value.length <= 14 ? value : `${value.slice(0, 14)}…`
}

function money(cents, currency) {
  return `${(Number(cents) / 100).toFixed(2)} ${currency}`
}

async function get(base, path, key) {
  const response = await fetch(`${base}${path}`, {
    headers: { Authorization: `Bearer ${key}` },
    cache: 'no-store',
    signal: AbortSignal.timeout(15000),
  })
  const body = await response.json().catch(() => ({}))
  return { status: response.status, body }
}

async function main() {
  const key = env('PADDLE_API_KEY')
  if (!key) {
    console.log('PADDLE_API_KEY is not set. Run with --env-file=.env.live (or .env.local).')
    return 2
  }

  const keyEnvironment = key.startsWith('pdl_live_')
    ? 'live'
    : key.startsWith('pdl_sdbx_')
      ? 'sandbox'
      : 'unknown'

  const declared = env('PADDLE_ENVIRONMENT').toLowerCase() === 'production' ? 'live' : 'sandbox'
  const explicitBase = env('PADDLE_API_BASE')
  const base = explicitBase
    ? explicitBase.replace(/\/+$/, '')
    : declared === 'live'
      ? 'https://api.paddle.com'
      : 'https://sandbox-api.paddle.com'

  console.log('\nPaddle pre-flight')
  console.log(`  key ends in ${keyEnvironment}, PADDLE_ENVIRONMENT says ${declared}`)
  console.log(`  requests would go to ${base}\n`)

  if (keyEnvironment === 'unknown') {
    bad('key prefix', 'not a pdl_live_ or pdl_sdbx_ key')
  } else if (keyEnvironment !== declared) {
    bad(
      'key vs environment',
      `a ${keyEnvironment} key with PADDLE_ENVIRONMENT=${declared === 'live' ? 'production' : 'unset'} — every checkout would fail`
    )
  } else {
    ok('key matches environment', `${keyEnvironment} · ${short(key)}`)
  }

  if (keyEnvironment === 'live' && base !== 'https://api.paddle.com') {
    bad('api base', `${base} with a live key`)
  } else {
    ok('api base', base)
  }

  if (expect && expect !== keyEnvironment) {
    bad('expected environment', `--${expect} was asked for, the key is ${keyEnvironment}`)
  }

  /**
   * `--catalogue` lists the active prices and hands back the env lines.
   *
   * Copying four ids out of a dashboard by hand is how a monthly id ends up in a
   * yearly slot, so the mapping is derived from interval + amount instead.
   */
  if (args.has('--catalogue')) {
    if (faults.length > 0) {
      console.log('\nRESULT: fix the environment first — this key cannot list the catalogue.')
      return 1
    }

    const { status, body } = await get(base, '/prices?status=active&per_page=100', key)
    if (status !== 200) {
      const detail = body?.error?.detail || `HTTP ${status}`
      console.log(`\nRESULT: cannot list prices — ${detail}`)
      if (status === 403) console.log('        the key needs Prices: Read for this.')
      return 1
    }

    const rows = (body?.data ?? []).map((price) => ({
      id: price.id,
      interval: price.billing_cycle?.interval ?? 'one-off',
      cents: Number(price.unit_price?.amount ?? -1),
      currency: price.unit_price?.currency_code ?? '?',
    }))

    console.log(`\n  ${rows.length} active price${rows.length === 1 ? '' : 's'} in this catalogue:`)
    for (const row of rows) {
      const per = row.interval === 'year' ? 'yr' : 'mo'
      console.log(`    ${row.id}  ${money(row.cents, row.currency)}/${per}  ${row.interval}`)
    }

    const claimed = new Set()
    const unmatched = []
    console.log('\n  env lines for the four this app sells:')
    for (const want of PRICE_VARS) {
      const cents = PLANS[want.plan][want.interval]
      const hit = rows.find(
        (row) => !claimed.has(row.id) && row.interval === want.interval && row.cents === cents
      )
      if (!hit) {
        unmatched.push(`${want.envVar} (${money(cents, CURRENCY)}/${want.interval})`)
        console.log(
          `    MISSING  ${want.envVar}  — no ${money(cents, CURRENCY)}/${want.interval} price exists`
        )
        continue
      }
      claimed.add(hit.id)
      console.log(`    ${want.envVar}=${hit.id}`)
    }

    console.log('')
    if (unmatched.length > 0) {
      console.log(`RESULT: ${unmatched.length} of 4 missing from the catalogue:`)
      for (const line of unmatched) console.log(`  - ${line}`)
      return 1
    }
    console.log(
      `RESULT: all four prices found on ${base} — paste the four lines above into the environment.`
    )
    return 0
  }

  // The webhook secret is per destination: the sandbox one will not verify live
  // events, and a failed verification means a paid customer is never upgraded.
  if (env('PADDLE_WEBHOOK_SECRET')) ok('webhook secret', 'set')
  else absentVar('PADDLE_WEBHOOK_SECRET', 'not in this environment')

  // Server-side checkout needs no client token; it is only reported so nobody
  // goes hunting for a "missing" variable that the app never reads.
  if (env('PADDLE_CLIENT_TOKEN') || env('NEXT_PUBLIC_PADDLE_CLIENT_TOKEN')) {
    ok('client token', 'set (not used by the server-side checkout)')
  } else {
    info('client token', 'absent — fine, checkouts are created server-side')
  }

  const seen = new Map()

  for (const { plan, interval, envVar } of PRICE_VARS) {
    const priceId = env(envVar)
    const card = interval === 'year' ? 'yr' : 'mo'
    const expected = PLANS[plan][interval]

    if (!priceId) {
      absentVar(envVar, 'not in this environment — the cadence cannot be sold')
      continue
    }
    if (seen.has(priceId)) {
      bad(envVar, `reuses the id of ${seen.get(priceId)} — one price cannot be two plans`)
      continue
    }
    seen.set(priceId, `${plan}/${interval}`)

    const { status, body } = await get(base, `/prices/${priceId}`, key)
    if (status !== 200) {
      const detail = body?.error?.detail || `HTTP ${status}`
      bad(
        envVar,
        status === 401
          ? `401 — the key and the api base disagree (${detail})`
          : `${short(priceId)} ${detail}`
      )
      continue
    }

    const price = body?.data ?? {}
    const actualInterval = price.billing_cycle?.interval ?? null
    const cents = Number(price.unit_price?.amount ?? -1)
    const currency = price.unit_price?.currency_code ?? '?'
    const label = `${envVar} (${plan}/${interval})`
    const problems = []

    if (actualInterval !== interval) problems.push(`bills ${actualInterval ?? 'one-off'}`)
    if (cents !== expected) {
      problems.push(`costs ${money(cents, currency)}, catalogue says ${money(expected, CURRENCY)}`)
    }
    if (currency !== CURRENCY) problems.push(`in ${currency}`)
    if (price.status !== 'active') problems.push(`status ${price.status}`)

    if (problems.length > 0) bad(label, `${short(priceId)} ${problems.join(', ')}`)
    else ok(label, `${short(priceId)} ${money(cents, currency)}/${card}`)
  }

  // A local shell is not the deployment. Say so once, plainly, so an empty
  // `.env` is not mistaken for a broken production configuration.
  if (absent.length > 0) {
    const plural = absent.length === 1 ? '' : 's'
    console.log(`\n  ${absent.length} variable${plural} absent from the environment this script read:`)
    console.log(`    ${absent.join(', ')}`)
    console.log('  That is not proof the deployment lacks them. Pull its values, then re-run:')
    console.log('    vercel env pull .env.live')
    console.log('    node --env-file=.env.live scripts/check-paddle-live.mjs --sandbox')
  }

  console.log('')
  if (faults.length > 0) {
    console.log(`RESULT: NOT ready — ${faults.length} problem${faults.length === 1 ? '' : 's'}:`)
    for (const fault of faults) console.log(`  - ${fault}`)
    return 1
  }
  if (absent.length > 0) {
    const plural = absent.length === 1 ? '' : 's'
    console.log(
      `RESULT: cannot check — ${absent.length} variable${plural} absent here, and nothing found that is wrong.`
    )
    return 2
  }
  console.log(`RESULT: ready for ${keyEnvironment} payments.`)
  if (notes.length > 0) {
    console.log(`       (${notes.length} note${notes.length === 1 ? '' : 's'}, not blocking)`)
  }
  return 0
}

main().then(
  (code) => {
    process.exitCode = code
  },
  (error) => {
    console.error(error)
    process.exitCode = 1
  }
)
