import { NextResponse, type NextRequest } from 'next/server'
import { createServerClient } from '@supabase/ssr'

/**
 * Refreshes the Supabase session on every page request.
 *
 * Sessions live in cookies, and an access token is short-lived (one hour). The
 * browser client renews it only when it is awake and making a call, so a user
 * who leaves a dashboard tab open overnight comes back to a cookie the server
 * no longer accepts: server components then render as signed-out even though the
 * browser still holds a session, and the request that writes the profile or
 * reads a page fails. This runs first on every navigation and rotates the
 * cookie, so the server and the browser never disagree about who is signed in.
 *
 * Next 16 renamed the `middleware` file convention to `proxy`; this is the same
 * hook under the current name (`middleware.ts` still works but warns on build).
 *
 * API routes are deliberately excluded: every one of them authenticates with a
 * bearer token and never reads this cookie, so refreshing there would add a
 * Supabase round trip to each call and fix nothing.
 */
export default async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request })

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const key =
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY

  // A deployment missing its Supabase variables must still serve its marketing
  // pages instead of failing every request in here.
  if (!url || !key) return response

  const supabase = createServerClient(url, key, {
    cookies: {
      getAll() {
        return request.cookies.getAll()
      },
      setAll(cookiesToSet) {
        // The request is mutated as well as the response: a server component
        // rendered later in this same request must see the fresh token, not the
        // one that was just replaced.
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

  // getUser() is the call that actually refreshes an expired token and hands the
  // new cookies to setAll — getSession() only reads what is already there, so on
  // its own the session would still expire mid-visit. The result is unused: this
  // file refreshes, it does not gate. Redirecting to login from here would trap
  // a user whose profile write failed behind a page they can never reach.
  await supabase.auth.getUser()

  return response
}

export const config = {
  matcher: [
    // Everything except API routes, build output and static assets: a page with
    // no cookie to refresh should not pay for a Supabase round trip.
    '/((?!api|_next/static|_next/image|_next/webpack-hmr|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|avif|ico|woff|woff2|ttf|otf|map|txt|xml|webmanifest)$).*)',
  ],
}
