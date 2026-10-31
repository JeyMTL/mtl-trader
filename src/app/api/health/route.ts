import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

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
      checkedAt: new Date().toISOString(),
    },
    {
      status: healthy ? 200 : 503,
      headers: { 'Cache-Control': 'no-store' },
    }
  )
}

/** A failed request looks different from a refused query; only the former is down. */
function isTransportError(message: string): boolean {
  return /fetch failed|network|ENOTFOUND|ECONNREFUSED|ETIMEDOUT|timeout|socket/i.test(
    message
  )
}
