import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { checkRpcs } from '@/lib/health-rpcs'

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
      // Like `features`, reported but not part of `status`: a pending migration
      // is a known, fixable state, and paging every fifteen minutes until
      // someone pastes SQL would train the alert away. `missing` names the file.
      migrations,
      checkedAt: new Date().toISOString(),
    },
    {
      status: healthy ? 200 : 503,
      headers: { 'Cache-Control': 'no-store' },
    }
  )
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

/** A failed request looks different from a refused query; only the former is down. */
function isTransportError(message: string): boolean {
  return /fetch failed|network|ENOTFOUND|ECONNREFUSED|ETIMEDOUT|timeout|socket/i.test(
    message
  )
}
