import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { checkRpcs } from '@/lib/health-rpcs'
import {
  emptyBrokerSyncReport,
  summarizeBrokerSync,
  type BrokerConnectionRow,
  type BrokerSyncReport,
} from '@/lib/broker-sync-status'
import { getAdminClient } from '@/lib/server-auth'
import { resolveProviderConfig } from '@/lib/ai/providers'
import { annualPriceCollisions, paddleEnvironment, priceIdFor } from '@/lib/paddle'

/**
 * Liveness and configuration probe.
 *
 * Answers "is this deployment wired up and can it reach its database", which is
 * what a deploy gate or uptime monitor needs. It reports only whether each
 * variable is *present* — never a value, prefix or length — so the endpoint is
 * safe to leave public.
 *
 * Returns 503 when a required piece is missing, so a monitor can alert on the
 * status code alone instead of parsing the body.
 */
export async function GET() {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anonKey =
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY

  const config = {
    supabaseUrl: Boolean(supabaseUrl),
    supabaseAnonKey: Boolean(anonKey),
    // Not required for reading pages, but profile creation and the cron routes
    // depend on it, so a deployment without it is only half working.
    serviceRoleKey: Boolean(serviceRoleKey),
  }

  let database: 'ok' | 'unreachable' | 'unknown' = 'unknown'

  if (supabaseUrl && anonKey) {
    try {
      const client = createClient(supabaseUrl, anonKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      })
      // An anonymous read of an RLS-protected table answers 200 with no rows.
      // Any real response proves the project is reachable and the key is at
      // least well-formed; only a transport failure counts as down.
      const { error } = await client
        .from('users')
        .select('id', { count: 'exact', head: true })
        .limit(1)
      database = error && isTransportError(error.message) ? 'unreachable' : 'ok'
    } catch {
      database = 'unreachable'
    }
  }

  const avatars = await checkAvatarsBucket(supabaseUrl)
  // Per-function schema check: a database that has not had the latest migration
  // applied otherwise looks healthy while one panel renders empty.
  const migrations = await checkRpcs(supabaseUrl, anonKey)
  // The hosted-sync supervisor is infrastructure outside this deploy, so its
  // absence is invisible here unless the connection set is read.
  const sync = await checkBrokerSync()

  const healthy =
    config.supabaseUrl && config.supabaseAnonKey && database === 'ok'

  return NextResponse.json(
    {
      status: healthy ? 'ok' : 'degraded',
      commit:
        process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 7) ??
        process.env.GIT_COMMIT_SHA?.slice(0, 7) ??
        null,
      database,
      config,
      // Reported, but deliberately not part of `status`: a missing bucket breaks
      // avatar uploads while the journal itself keeps working, so it must not
      // page anyone. The deploy gate surfaces it instead.
      // Presence only, never a value or a prefix: `hostedSync` tells the deploy
      // gate — and anyone debugging — whether SYNC_CREDENTIAL_KEY actually
      // reached this deployment. Without it a missing key surfaces only as a
      // 503 when a customer tries to connect, which is too late to be useful.
      features: { avatars, hostedSync: Boolean(process.env.SYNC_CREDENTIAL_KEY) },
      // Which provider this deployment resolved, never a key or a prefix of one.
      // `configured: false` is a valid deployment (the review answers 503), but
      // the name matters: "configured and Gemini" and "configured and Sonnet"
      // cost very different money, and this is where a misconfigured one shows
      // up instead of when a customer taps Review.
      ai: aiProvider(),
      // Presence only, never a value. The expensive go-live mistake is a
      // sandbox key left in production: it takes test cards and grants real
      // access, and nothing else in the app can tell the two apart.
      paddle: paddleStatus(),
      // Same rule as `paddle`: presence only. Without PAYPAL_WEBHOOK_ID (or the
      // client credentials) the webhook cannot verify a signature and answers
      // 503, so the durable upgrade path is disabled and the success-page
      // capture is the only way an order gets applied. Nothing else in the app
      // says so, which is exactly why it belongs here.
      paypal: paypalStatus(),
      // Like `features`, reported but not part of `status`: a pending migration
      // is a known, fixable state, and paging every fifteen minutes until
      // someone pastes SQL would train the alert away. `missing` names the file.
      migrations,
      // Same rule as `migrations`: reported, not part of `status`. A supervisor
      // that is not running breaks automatic sync and nothing else, and paging
      // the uptime monitor for infrastructure would train the alert away.
      sync,
      checkedAt: new Date().toISOString(),
    },
    {
      status: healthy ? 200 : 503,
      headers: { 'Cache-Control': 'no-store' },
    }
  )
}

/**
 * The AI provider resolved from this deployment's environment.
 *
 * Reported separately from `features` because it carries a name, not a boolean.
 */
function aiProvider(): { configured: boolean; provider: string | null } {
  const config = resolveProviderConfig()
  return { configured: Boolean(config), provider: config?.provider ?? null }
}

/**
 * Paddle config, read the way the payment routes read it.
 *
 * `keyEnvironment` comes from the key's own prefix, `api` from
 * PADDLE_ENVIRONMENT: a `pdl_sdbx_` key with `api: production` is a live
 * deployment that cannot take a single payment, and this is where that shows up
 * instead of in a customer's failed checkout.
 */
function paddleStatus() {
  const key = (process.env.PADDLE_API_KEY || '').trim()
  const clientToken = (
    process.env.PADDLE_CLIENT_TOKEN ||
    process.env.NEXT_PUBLIC_PADDLE_CLIENT_TOKEN ||
    ''
  ).trim()

  return {
    configured: Boolean(key),
    keyEnvironment: key.startsWith('pdl_live_')
      ? 'live'
      : key.startsWith('pdl_sdbx_')
        ? 'sandbox'
        : key
          ? 'unknown'
          : null,
    api: paddleEnvironment(),
    webhookSecret: Boolean((process.env.PADDLE_WEBHOOK_SECRET || '').trim()),
    clientToken: Boolean(clientToken),
    prices: {
      basic: Boolean(priceIdFor('basic', 'month')),
      pro: Boolean(priceIdFor('pro', 'month')),
      basicAnnual: Boolean(priceIdFor('basic', 'year')),
      proAnnual: Boolean(priceIdFor('pro', 'year')),
    },
    // Plan ids whose yearly price id is also a monthly one. Empty is correct:
    // a yearly price is its own catalogue entry, and reusing a monthly id means
    // Paddle charges a month's price for a year that the webhook then refuses.
    // Plan ids only, never a price id, so this stays safe to publish.
    annualReusesMonthlyPrice: annualPriceCollisions(['basic', 'pro']),
  }
}

/**
 * PayPal config: three separate facts, none of them a value.
 *
 * Whether checkout can authenticate at all, whether the webhook is registered
 * (without it the signature check cannot run and the route fails closed), and
 * which environment the credentials point at — a sandbox app in production takes
 * no real money, and that is invisible from every other surface.
 */
function paypalStatus() {
  const clientId = (process.env.PAYPAL_CLIENT_ID || '').trim()
  const clientSecret = (process.env.PAYPAL_CLIENT_SECRET || '').trim()
  const base = (process.env.PAYPAL_API_BASE || '').trim()

  return {
    configured: Boolean(clientId && clientSecret),
    environment: base.includes('sandbox') ? 'sandbox' : 'live',
    webhook: Boolean((process.env.PAYPAL_WEBHOOK_ID || '').trim()),
  }
}

/**
 * Proves the `avatars` bucket exists without a key: a public-bucket request
 * answers "Object not found" when the bucket is there and "Bucket not found"
 * when the migration has not been applied. That is the difference between a
 * half-rolled-out feature and a healthy deployment.
 */
async function checkAvatarsBucket(
  supabaseUrl: string | undefined
): Promise<'ready' | 'missing' | 'unknown'> {
  if (!supabaseUrl) return 'unknown'
  try {
    const response = await fetch(
      `${supabaseUrl.replace(/\/+$/, '')}/storage/v1/object/public/avatars/__health-probe__`,
      { cache: 'no-store', signal: AbortSignal.timeout(5000) }
    )
    const body = await response.text()
    if (/bucket not found/i.test(body)) return 'missing'
    if (/object not found/i.test(body) || response.ok) return 'ready'
    return 'unknown'
  } catch {
    return 'unknown'
  }
}

/**
 * Aggregates over `broker_connections`, read with the service role because RLS
 * keeps the rows private.
 *
 * Only counts, a verdict and timestamps are returned: this endpoint is public,
 * and a broker name, server or account number is the customer's business. A
 * failed read reports `unknown` rather than pretending everything is idle.
 */
async function checkBrokerSync(): Promise<BrokerSyncReport> {
  try {
    const { data, error } = await getAdminClient()
      .from('broker_connections')
      .select('status, updated_at, last_sync_at')
      .limit(1000)

    if (error) return emptyBrokerSyncReport('unknown')
    return summarizeBrokerSync((data ?? []) as BrokerConnectionRow[])
  } catch {
    return emptyBrokerSyncReport('unknown')
  }
}

/** A failed request looks different from a refused query; only the former is down. */
function isTransportError(message: string): boolean {
  return /fetch failed|network|ENOTFOUND|ECONNREFUSED|ETIMEDOUT|timeout|socket/i.test(
    message
  )
}
