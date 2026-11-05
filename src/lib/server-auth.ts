import { createClient, type SupabaseClient } from '@supabase/supabase-js'

let adminClient: SupabaseClient | null = null

export function getAdminClient(): SupabaseClient {
  if (adminClient) return adminClient

  // Fail with the missing variable named, instead of a provider error that
  // says nothing about configuration.
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !serviceRoleKey) {
    throw new Error(
      'Supabase admin client is not configured. Set NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.'
    )
  }

  adminClient = createClient(url, serviceRoleKey)
  return adminClient
}

function isSameOrigin(req: Request, origin: string): boolean {
  try {
    if (origin === new URL(req.url).origin) return true
    const appUrl = process.env.NEXT_PUBLIC_APP_URL
    if (appUrl && origin === new URL(appUrl).origin) return true
  } catch {
    // A malformed Origin or request URL is not same-origin by definition.
  }
  return false
}

export async function getAuthUser(req: Request) {
  const authHeader = req.headers.get('Authorization')

  if (authHeader && authHeader.startsWith('Bearer ')) {
    const token = authHeader.slice('Bearer '.length)
    const { data: { user }, error } = await getAdminClient().auth.getUser(token)
    if (error || !user || !user.email_confirmed_at) return null
    return user
  }

  // Cookie-authenticated mutations must come from this origin. Cookies are
  // SameSite=Lax today, which already blocks a cross-site POST, but that is a
  // cookie attribute rather than a check in the code: if it is ever changed to
  // SameSite=None for an embed, this is what still refuses the request. Browsers
  // send Origin on every non-GET request; non-browser callers (the agent, curl)
  // omit it and are unaffected because they do not carry the cookie either.
  const method = req.method.toUpperCase()
  const origin = req.headers.get('origin')
  if (origin && method !== 'GET' && method !== 'HEAD' && !isSameOrigin(req, origin)) {
    return null
  }

  // Same-origin calls made from server components carry the cookie session, not
  // a bearer token. Imported lazily so `next/headers` is never loaded for tests
  // or for the bearer path.
  const { createServerSupabase } = await import('@/lib/supabase-server')
  const supabase = await createServerSupabase()
  if (!supabase) return null
  const { data: { user } } = await supabase.auth.getUser()
  if (!user || !user.email_confirmed_at) return null
  return user
}

export async function requireAdmin(req: Request) {
  const user = await getAuthUser(req)
  if (!user) return { user: null, error: 'Unauthorized' }
  const { data, error } = await getAdminClient()
    .from('users')
    .select('is_admin')
    .eq('id', user.id)
    .single()
  if (error || !data || data.is_admin !== true) {
    return { user: null, error: 'Forbidden' }
  }
  return { user, error: null }
}
