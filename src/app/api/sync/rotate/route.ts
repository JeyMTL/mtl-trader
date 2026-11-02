import { NextResponse } from 'next/server'
import { randomBytes } from 'node:crypto'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { rateLimit } from '@/lib/rate-limit'
import { apiError, logEvent } from '@/lib/log'
import { checkFeature } from '@/lib/plan-guard'

/**
 * Rotates the MT5 agent token.
 *
 * The sync page has always had a "Rotate" button pointing at this route, but the
 * route did not exist, so a leaked token could never be revoked. Rotating
 * invalidates the old token immediately.
 */
export async function POST(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const limit = await rateLimit(`sync-rotate:${user.id}`, 5, 60 * 60 * 1000)
    if (!limit.ok) {
      return NextResponse.json(
        { error: 'Too many token rotations. Please try again later.' },
        { status: 429, headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) } }
      )
    }

    const gate = await checkFeature(user.id, 'sync')
    if (!gate.allowed) {
      return NextResponse.json(
        { error: gate.message, code: 'upgrade_required' },
        { status: gate.status }
      )
    }

    const token = randomBytes(32).toString('hex')
    const { error } = await getAdminClient()
      .from('users')
      .update({ agent_token: token })
      .eq('id', user.id)

    if (error) {
      return apiError('sync.rotate', error, 500, 'Could not rotate the sync token.')
    }

    logEvent('info', 'sync.rotate', { userId: user.id })
    return NextResponse.json({ token, rotated: true })
  } catch (error: unknown) {
    return apiError('sync.rotate', error, 500, 'Could not rotate the sync token.')
  }
}
