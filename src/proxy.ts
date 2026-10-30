import { NextResponse, type NextRequest } from 'next/server'
import { createServerClient } from '@supabase/ssr'

/**
 * Auth guard and session refresh for the dashboard.
 *
 * Next.js 16 renamed the middleware convention to `proxy`. This runs before any
 * dashboard route renders, so an unauthenticated request is redirected at the
 * edge instead of being sent to the client and bounced by a `useEffect`.
 *
 * It also refreshes the Supabase session cookies: server components cannot write
 * cookies, so without this a long-lived tab would lose its session on the next
 * server render.
 */
export async function proxy(request: NextRequest) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY

  // Unconfigured deployment: let the page render its own configuration error.
  if (!url || !key) return NextResponse.next()

  let response = NextResponse.next({ request })

  const supabase = createServerClient(url, key, {
    cookies: {
      getAll() {
        return request.cookies.getAll()
      },
      setAll(cookiesToSet) {
        for (const { name, value } of cookiesToSet) {
          request.cookies.set(name, value)
        }
        response = NextResponse.next({ request })
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options)
        }
      },
    },
  })

  const { data: { user } } = await supabase.auth.getUser()

  if (!user || !user.email_confirmed_at) {
    const login = request.nextUrl.clone()
    login.pathname = '/auth/login'
    login.search = ''
    if (!user) login.searchParams.set('next', request.nextUrl.pathname)
    return NextResponse.redirect(login)
  }

  return response
}

export const config = {
  matcher: ['/dashboard/:path*'],
}
