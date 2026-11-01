import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'
import { createServerClient } from '@supabase/ssr'
import type { SupabaseClient, User } from '@supabase/supabase-js'

/**
 * Server-side Supabase client for server components and route handlers.
 *
 * It reads the same cookie session the browser client writes, so a page can be
 * rendered with the user's data before any markup reaches the browser — the
 * dashboard no longer has to ship the whole journal to the client to compute a
 * win rate.
 *
 * Cookie writes are wrapped in try/catch because Server Components cannot set
 * cookies. Refreshing the session is `src/proxy.ts`'s job; here a failed write
 * simply means the current request keeps the session it already has.
 */

export function isSupabaseConfigured(): boolean {
  return Boolean(
    process.env.NEXT_PUBLIC_SUPABASE_URL &&
    (process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY)
  )
}

export async function createServerSupabase(): Promise<SupabaseClient | null> {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
  if (!url || !key) return null

  const cookieStore = await cookies()

  return createServerClient(url, key, {
    cookies: {
      getAll() {
        return cookieStore.getAll()
      },
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options)
          }
        } catch {
          // Server Components cannot mutate cookies; middleware refreshes the session.
        }
      },
    },
  })
}

/** The authenticated user for this request, or null. */
export async function getServerUser(): Promise<User | null> {
  const supabase = await createServerSupabase()
  if (!supabase) return null
  const { data: { user } } = await supabase.auth.getUser()
  return user ?? null
}

/**
 * Redirects to the login page when there is no verified session. Used by the
 * server-rendered dashboard pages so an unauthenticated request never renders
 * account data (the proxy refreshes the cookie, this is what actually gates).
 */
export async function requireServerUser(): Promise<User> {
  const supabase = await createServerSupabase()
  if (!supabase) redirect('/auth/login')
  const { data: { user } } = await supabase.auth.getUser()
  if (!user || !user.email_confirmed_at) redirect('/auth/login')
  return user
}
