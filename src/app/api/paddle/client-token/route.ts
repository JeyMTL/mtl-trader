import { NextResponse } from 'next/server'

/**
 * The Paddle.js client-side token, read at request time.
 *
 * It is served rather than inlined as `NEXT_PUBLIC_*` because a public variable
 * is frozen into the client bundle when the build runs: rotating the token, or
 * saving it only for Preview, then needs a rebuild and fails silently — /pay
 * simply says "not configured" with nothing to point at. Read here instead, the
 * value takes effect on the next request and a wrong scope is visible from
 * `curl` rather than from a browser.
 *
 * This is not a secret. The client-side token can only open checkouts and
 * preview prices, which is why Paddle expects it in the page bundle; the API key
 * is the server-side credential and never appears here.
 *
 * The `NEXT_PUBLIC_` name is still honoured so an older deployment keeps working
 * until it is renamed.
 */

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const NO_STORE = { 'Cache-Control': 'no-store' } as const

export async function GET() {
  const token = (
    process.env.PADDLE_CLIENT_TOKEN ||
    process.env.NEXT_PUBLIC_PADDLE_CLIENT_TOKEN ||
    ''
  ).trim()

  if (!token) {
    // 503 rather than an empty 200: "not configured" is a deployment problem,
    // and the status alone is enough for a check script to assert on.
    return NextResponse.json({ token: null, error: 'not_configured' }, { status: 503, headers: NO_STORE })
  }

  return NextResponse.json({ token, environment: token.startsWith('test_') ? 'sandbox' : 'production' }, {
    headers: NO_STORE,
  })
}
