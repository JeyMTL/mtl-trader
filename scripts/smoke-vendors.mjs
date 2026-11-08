#!/usr/bin/env node
/**
 * Fail-closed smoke test against a deployed app.
 *
 * This is the part of vendor verification that does not need sandbox
 * credentials: every payment and AI route here has an unauthenticated or
 * unsigned caller in front of it, and what matters most is that such a caller
 * never gets a 200. Sending garbage and asserting a refusal is a real check of
 * the entitlement gates, the signature checks and the ownership checks — it just
 * cannot prove the *happy* path works, which needs real sandbox accounts.
 *
 *   node scripts/smoke-vendors.mjs https://mtl-trader.vercel.app
 *   SMOKE_BASE_URL=... node scripts/smoke-vendors.mjs
 *
 * Exit code is 1 if any route answered with a status it should never give.
 *
 * A 503 that means "this endpoint is not configured" is reported as CONFIG, not
 * as a failure: it is still fail-closed, but it is an operator's problem rather
 * than a bug, and conflating the two trains people to ignore the harness.
 */

const base = (process.argv[2] || process.env.SMOKE_BASE_URL || '').replace(/\/+$/, '')
if (!base) {
  console.error('usage: node scripts/smoke-vendors.mjs <https://deployed-app>')
  process.exit(2)
}

const json = { 'Content-Type': 'application/json' }

const checks = [
  { name: 'health is public', method: 'GET', path: '/api/health', expect: [200] },
  {
    name: 'paddle webhook rejects an unsigned body',
    method: 'POST',
    path: '/api/webhooks/paddle',
    body: { event_type: 'subscription.created', data: { id: 'sub_fake' } },
    headers: json,
    expect: [400, 401, 403, 503],
  },
  {
    name: 'paypal webhook rejects an unsigned body',
    method: 'POST',
    path: '/api/webhooks/paypal',
    body: { event_type: 'PAYMENT.CAPTURE.COMPLETED' },
    headers: json,
    expect: [400, 401, 403, 503],
  },
  {
    name: 'paypal capture needs an owner',
    method: 'POST',
    path: '/api/paypal/capture',
    body: { orderId: 'O-FAKE-ORDER' },
    headers: json,
    expect: [401],
  },
  {
    name: 'google play verification needs an owner',
    method: 'POST',
    path: '/api/billing/google/verify',
    body: { productId: 'basic_month', purchaseToken: 'fake-token' },
    headers: json,
    expect: [401],
  },
  {
    name: 'cancellation needs the subscriber',
    method: 'POST',
    path: '/api/subscription/cancel',
    body: {},
    headers: json,
    expect: [401],
  },
  {
    name: 'card checkout needs the buyer',
    method: 'POST',
    path: '/api/checkout/card',
    body: { priceId: 'pri_fake' },
    headers: json,
    expect: [401],
  },
  {
    name: 'strategy compile needs the Pro account',
    method: 'POST',
    path: '/api/backtest/compile',
    body: { description: 'a strategy description long enough to pass the length check' },
    headers: json,
    expect: [401],
  },
  {
    name: 'voice transcription needs the Pro account',
    method: 'POST',
    path: '/api/backtest/transcribe',
    body: { audio: 'data:audio/wav;base64,AAAA' },
    headers: json,
    expect: [401],
  },
  {
    name: 'account export needs the account',
    method: 'GET',
    path: '/api/account/export',
    expect: [401],
  },
]

let failures = 0

for (const check of checks) {
  const url = `${base}${check.path}`
  let status = 0
  let detail = ''
  try {
    const response = await fetch(url, {
      method: check.method,
      headers: check.headers,
      body: check.body ? JSON.stringify(check.body) : undefined,
      redirect: 'manual',
    })
    status = response.status
    if (!check.expect.includes(status)) {
      detail = (await response.text()).slice(0, 160).replace(/\s+/g, ' ')
    }
  } catch (error) {
    status = -1
    detail = error instanceof Error ? error.message : String(error)
  }

  const ok = check.expect.includes(status)
  if (!ok) failures += 1
  const unconfigured = status === 503
  const verdict = ok ? (unconfigured ? 'CONFIG' : 'PASS') : 'FAIL'
  console.log(
    `${verdict}  ${String(status).padStart(3)}  ${check.name}  (expected ${check.expect.join('/')})${detail ? `\n        ${detail}` : ''}`
  )
}

// Presence only, straight from the deployment's own health probe: this is where
// a disabled webhook or a sandbox key in production becomes visible.
try {
  const health = await (await fetch(`${base}/api/health`)).json()
  console.log('\nDeployment configuration (presence only):')
  console.log(`  ai      ${health.ai?.configured ? health.ai.provider : 'not configured'}`)
  console.log(
    `  paddle  ${health.paddle?.configured ? `${health.paddle.keyEnvironment} key, api ${health.paddle.api}, webhook ${Boolean(health.paddle.webhookSecret)}` : 'not configured'}`
  )
  console.log(
    health.paypal
      ? `  paypal  ${health.paypal.configured ? `${health.paypal.environment} credentials, webhook ${Boolean(health.paypal.webhook)}` : 'credentials missing'}`
      : '  paypal  not reported by this deployment'
  )
} catch (error) {
  console.log(`\n  could not read /api/health: ${error instanceof Error ? error.message : error}`)
}

console.log(
  failures === 0
    ? `\nAll ${checks.length} routes refused what they should refuse.`
    : `\n${failures} of ${checks.length} routes answered unexpectedly.`
)
process.exit(failures === 0 ? 0 : 1)
