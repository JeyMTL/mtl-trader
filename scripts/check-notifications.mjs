#!/usr/bin/env node
/**
 * Manually exercises the notifications pipeline end to end and reports exactly
 * what happened. Prints no secrets.
 *
 *   - default       audits which notification env vars are configured
 *   - --send <to>   sends a sample summary email through Resend
 *   - --run         calls the deployed cron endpoint with CRON_SECRET and
 *                   prints the cron's JSON result (emailsSent / skipped / failed)
 *
 * Usage:
 *   node --env-file=.env.local scripts/check-notifications.mjs
 *   node --env-file=.env.local scripts/check-notifications.mjs --send you@example.com
 *   node --env-file=.env.local scripts/check-notifications.mjs --run
 */

const args = process.argv.slice(2)

function flagValue(name) {
  const index = args.indexOf(name)
  return index !== -1 ? args[index + 1] : undefined
}

const sendTo = flagValue('--send')
const runCron = args.includes('--run')

const apiKey = process.env.RESEND_API_KEY
const emailFrom = process.env.EMAIL_FROM
const cronSecret = process.env.CRON_SECRET
const appUrl = (process.env.NEXT_PUBLIC_APP_URL || '').replace(/\/$/, '')

function mask(value) {
  if (!value) return ''
  if (value.length <= 8) return '••••'
  return `${value.slice(0, 4)}…${value.slice(-4)}`
}

function line(label, ok, detail) {
  console.log(`${ok ? '✔' : '✖'} ${label}: ${detail}`)
}

console.log('MTL Trader — notification check\n')

let problems = 0

if (apiKey) {
  line('RESEND_API_KEY', true, `set (${mask(apiKey)})`)
} else {
  problems++
  line('RESEND_API_KEY', false, 'MISSING — the cron returns 503 and sends nothing')
}

if (emailFrom) {
  line('EMAIL_FROM', true, emailFrom)
} else {
  problems++
  line('EMAIL_FROM', false, "MISSING — falls back to onboarding@resend.dev, which Resend only delivers to your own account email")
}

if (cronSecret) {
  line('CRON_SECRET', true, `set (${mask(cronSecret)})`)
} else {
  problems++
  line('CRON_SECRET', false, 'MISSING — the cron fails closed with 401')
}

if (appUrl) {
  line('NEXT_PUBLIC_APP_URL', true, appUrl)
} else {
  problems++
  line('NEXT_PUBLIC_APP_URL', false, 'MISSING — dashboard links in emails fall back to the default app URL')
}

async function sendSampleEmail() {
  console.log(`\n→ Sending a sample summary email to ${sendTo} …`)
  if (!apiKey) {
    console.error('✖ Cannot send: RESEND_API_KEY is not configured.')
    process.exit(1)
  }

  const from = emailFrom || 'MTL Trader <onboarding@resend.dev>'
  const html = `<!doctype html>
<html><body style="margin:0;background:#0d1117;font-family:Arial,Helvetica,sans-serif;color:#c9d1d9">
  <div style="max-width:520px;margin:0 auto;padding:24px">
    <h1 style="font-size:18px;color:#f0f6fc;margin:0 0 4px">MTL Trader</h1>
    <p style="color:#8b949e;margin:0 0 20px">Test notification</p>
    <div style="background:#161b22;border:1px solid #30363d;border-radius:12px;padding:20px">
      <p style="margin:0 0 12px">This is a test from scripts/check-notifications.mjs.</p>
      <p style="margin:0;color:#8b949e">If you can read this, Resend delivery works and the cron can reach your inbox.</p>
    </div>
  </div>
</body></html>`

  let res
  try {
    res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from, to: [sendTo], subject: 'MTL Trader test notification', html }),
    })
  } catch (error) {
    console.error('✖ Could not reach api.resend.com')
    console.error(`   ${error instanceof Error ? error.message : error}`)
    process.exit(1)
  }

  const data = await res.json().catch(() => ({}))
  if (res.ok && data.id) {
    console.log(`✔ Accepted by Resend (id ${data.id})`)
    console.log('  If it does not arrive, check the from-domain is verified and look in spam.')
  } else {
    console.error(`✖ Rejected by Resend (HTTP ${res.status})`)
    console.error(`  Resend said: ${data.message || data.error || 'unknown error'}`)
    process.exit(2)
  }
}

async function runNotificationsCron() {
  console.log('\n→ Calling the notifications cron …')
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
    res = await fetch(`${appUrl}/api/cron/notifications`, {
      headers: { Authorization: `Bearer ${cronSecret}` },
    })
  } catch (error) {
    console.error(`✖ Could not reach ${appUrl}`)
    console.error(`   ${error instanceof Error ? error.message : error}`)
    process.exit(1)
  }

  const body = await res.json().catch(() => ({}))
  if (res.ok) {
    console.log(`✔ Cron ran (HTTP ${res.status})`)
    console.log(`  candidates: ${body.candidates ?? '?'}  sent: ${body.emailsSent ?? '?'}  skipped: ${body.skipped ?? '?'}  failed: ${body.failed ?? '?'}`)
    if (body.emailsSent === 0) {
      console.log('  Nothing sent — expected if no opted-in user had a non-empty window today.')
    }
  } else {
    console.error(`✖ Cron returned HTTP ${res.status}`)
    console.error(`  ${body.error || JSON.stringify(body)}`)
    process.exit(2)
  }
}

if (sendTo) await sendSampleEmail()
if (runCron) await runNotificationsCron()

if (!sendTo && !runCron) {
  console.log('\nConfig audit complete.')
  console.log('Next steps:')
  console.log('  1. node --env-file=.env.local scripts/check-notifications.mjs --send you@example.com')
  console.log('  2. node --env-file=.env.local scripts/check-notifications.mjs --run')
} else if (problems > 0) {
  console.log('\nNote: some configuration was missing — see the ✖ lines above.')
}
