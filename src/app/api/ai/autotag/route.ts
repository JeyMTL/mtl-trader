import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import { rateLimit } from '@/lib/rate-limit'
import { suggestTags } from '@/lib/ai/autotag'

/**
 * POST /api/ai/autotag
 *   Deterministic, free tag suggestions from a trade note. No model call — it is
 *   safe to invoke on every keystroke or on import.
 */

export const dynamic = 'force-dynamic'

export async function POST(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const limit = rateLimit(`ai-autotag:${user.id}`, 60, 60 * 1000)
    if (!limit.ok) {
      return NextResponse.json(
        { error: 'Too many requests.' },
        { status: 429, headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) } }
      )
    }

    const body = (await req.json().catch(() => ({}))) as { note?: unknown }
    if (typeof body.note !== 'string') {
      return NextResponse.json({ error: 'Expected a note string' }, { status: 400 })
    }

    return NextResponse.json({ tags: suggestTags(body.note) })
  } catch (error: unknown) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Unknown error' },
      { status: 500 }
    )
  }
}
