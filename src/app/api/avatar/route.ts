import { createHash } from 'node:crypto'
import { NextResponse } from 'next/server'

/**
 * Gravatar lookup for an email address.
 *
 * The hash is computed here so no client bundle needs an MD5 implementation.
 * `d=404` makes Gravatar answer 404 when the address has no picture, which lets
 * the caller fall back to initials instead of drawing a generic placeholder
 * blob that implies an account exists.
 */
export function GET(req: Request) {
  const params = new URL(req.url).searchParams
  const email = (params.get('email') || '').trim().toLowerCase()
  const rawSize = Number(params.get('s'))
  const size = Number.isFinite(rawSize)
    ? Math.min(Math.max(Math.round(rawSize), 16), 512)
    : 96

  if (!email || !email.includes('@')) {
    return new NextResponse('A valid email is required', { status: 400 })
  }

  const hash = createHash('md5').update(email).digest('hex')

  return NextResponse.redirect(
    `https://www.gravatar.com/avatar/${hash}?s=${size}&d=404`,
    {
      status: 302,
      headers: { 'Cache-Control': 'public, max-age=3600' },
    }
  )
}
