#!/usr/bin/env node
/**
 * Audits the payment configuration and can verify it end to end. Prints no
 * secrets.
 *
 *   - default      audits which payment env vars are configured
 *   - --verify     validates the PayPal credentials against the API and reports
 *                  which endpoint (sandbox/live) they belong to
 *   - --reconcile  calls the deployed /api/admin/reconcile cron with CRON_SECRET
 *                  and prints the JSON result
 *
 * Usage:
 *   node --env-file=.env.local scripts/check-payments.mjs
 *   node --env-file=.env.local scripts/check-payments.mjs --verify
 *   node --env-file=.env.local scripts/check-payments.mjs --reconcile
 */

const args = process.argv.slice(2)
const verify = args.includes('--verify')
const reconcile = args.includes('--reconcile')

const clientId = process.env.PAYPAL_CLIENT_ID
const clientSecret = process.env.PAYPAL_CLIENT_SECRET
const paypalBase = process.env.PAYPAL_API_BASE || 'https://api-m.paypal.com'
const webhookId = process.env.PAYPAL_WEBHOOK_ID
const appUrl = (process.env.NEXT_PUBLIC_APP_URL || '').replace(/\/$/, '')
const cronSecret = process.env.CRON_SECRET

const bank = {
  name: process.env.BANK_NAME,
  accountName: process.env.BANK_ACCOUNT_NAME,
  accountNumber: process.env.BANK_ACCOUNT_NUMBER,
  branch: process.env.BANK_BRANCH,
}

function mask(value) {
  if (!value) return ''
  if (value.length <= 8) return '••••'
  return `${value.slice(0, 4)}…${value.slice(-4)}`
}

function line(label, ok, detail) {
  console.log(`${ok ? '✔' : '✖'} ${label}: ${detail}`)
}

console.log('MTL Trader — payment check\n')

let problems = 0

if (clientId && clientSecret) {
  line('PAYPAL_CLIENT_ID / PAYPAL_CLIENT_SECRET', true, `set (${mask(clientId)})`)
} else {
  problems++
  line('PAYPAL_CLIENT_ID / PAYPAL_CLIENT_SECRET', false, 'MISSING — checkout and capture cannot work')
}

line(
  'PAYPAL_API_BASE',
  true,
  `${paypalBase} (${paypalBase.includes('sandbox') ? 'SANDBOX' : 'LIVE'})`
)

if (webhookId) {
  line('PAYPAL_WEBHOOK_ID', true, `set (${mask(webhookId)})`)
} else {
  problems++
  line('PAYPAL_WEBHOOK_ID', false, 'MISSING — the signature-verified webhook fallback is disabled')
}

if (appUrl) {
  line('NEXT_PUBLIC_APP_URL', true, appUrl)
} else {
  problems++
  line('NEXT_PUBLIC_APP_URL', false, 'MISSING — PayPal return/cancel URLs cannot be built')
}

if (cronSecret) {
  line('CRON_SECRET', true, `set (${mask(cronSecret)})`)
} else {
  problems++
  line('CRON_SECRET', false, 'MISSING — the reconcile cron fails closed with 401')
}

const bankConfigured = Boolean(bank.name && bank.accountName && bank.accountNumber)
if (bankConfigured) {
  line('BANK_*', true, `configured${bank.branch ? '' : ' (branch omitted)'}`)
} else {
  line('BANK_*', false, 'not configured — the payment page shows a "contact support" message')
}

async function verifyPayPal() {
  console.log(`\n→ Verifying PayPal credentials against ${paypalBase} …`)
  if (!clientId || !clientSecret) {
    console.error('✖ Cannot verify: PAYPAL_CLIENT_ID / PAYPAL_CLIENT_SECRET are not configured.')
    process.exit(1)
  }

  const auth = Buffer.from(`${clientId}:${clientSecret}`).toString('base64')
  let res
  try {
    res = await fetch(`${paypalBase}/v1/oauth2/token`, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${auth}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: 'grant_type=client_credentials',
    })
  } catch (error) {
    console.error(`✖ Could not reach ${paypalBase}`)
    console.error(`   ${error instanceof Error ? error.message : error}`)
    process.exit(1)
  }

  const data = await res.json().catch(() => ({}))
  if (res.ok && data.access_token) {
    const environment = paypalBase.includes('sandbox') ? 'SANDBOX' : 'LIVE'
    console.log(`✔ Credentials are VALID against ${environment} (${paypalBase})`)
    console.log(`  Client ID: ${mask(clientId)} (masked)`)
    if (data.scope) {
      console.log(`  Granted scopes: ${String(data.scope).split(' ').filter(Boolean).length}`)
    }
    if (!webhookId) {
      console.log('\n  Next: create the webhook in the PayPal dashboard and set PAYPAL_WEBHOOK_ID.')
    }
  } else {
    console.error(`✖ Credentials were REJECTED by ${paypalBase} (HTTP ${res.status})`)
    console.error(`  PayPal said: ${data.error_description || data.error || 'unknown error'}`)
    process.exit(2)
  }
}

async function runReconcile() {
  console.log('\n→ Calling the reconcile cron …')
  if (!cronSecret) {
    console.error('✖ Cannot run: CRON_SECRET is not configured.')
    process.exit(1)
  }
  if (!appUrl) {
    console.error('✖ Cannot run: NEXT_PUBLIC_APP_URL is not configured.')
    process.exit(1)
  }

  let res
  try {
    res = await fetch(`${appUrl}/api/admin/reconcile`, {
      headers: { Authorization: `Bearer ${cronSecret}` },
    })
  } catch (error) {
    console.error(`✖ Could not reach ${appUrl}`)
    console.error(`   ${error instanceof Error ? error.message : error}`)
    process.exit(1)
  }

  const body = await res.json().catch(() => ({}))
  if (res.ok) {
    console.log(`✔ Reconcile ran (HTTP ${res.status})`)
    console.log(`  ${JSON.stringify(body)}`)
  } else {
    console.error(`✖ Reconcile returned HTTP ${res.status}`)
    console.error(`  ${body.error || JSON.stringify(body)}`)
    process.exit(2)
  }
}

if (verify) await verifyPayPal()
if (reconcile) await runReconcile()

if (!verify && !reconcile) {
  console.log('\nConfig audit complete.')
  console.log('Next steps:')
  console.log('  1. node --env-file=.env.local scripts/check-payments.mjs --verify')
  console.log('  2. node --env-file=.env.local scripts/check-payments.mjs --reconcile')
} else if (problems > 0) {
  console.log('\nNote: some configuration was missing — see the ✖ lines above.')
}
