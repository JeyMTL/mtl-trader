import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import { apiError } from '@/lib/log'
import { MT5_BROKERS, searchMt5Brokers } from '@/lib/mt5-brokers'

/**
 * The MT5 broker directory.
 *
 * `GET /api/brokers` returns every broker; `?q=ic` returns the matches in rank
 * order. The web form imports the same module directly, so this exists for
 * clients that cannot — the mobile app's broker picker above all.
 *
 * Signed-in only: the list is small, but leaving it open turns the endpoint into
 * a free scraping target for no benefit.
 */

export const runtime = 'nodejs'

export async function GET(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const { searchParams } = new URL(req.url)
    // Bounded inputs: the query is a search term, not a payload.
    const query = (searchParams.get('q') ?? '').slice(0, 60)
    const limit = Math.min(
      Math.max(Number.parseInt(searchParams.get('limit') ?? '', 10) || 100, 1),
      100
    )

    const brokers = searchMt5Brokers(query, limit)

    return NextResponse.json(
      { brokers, total: MT5_BROKERS.length },
      { headers: { 'Cache-Control': 'private, max-age=3600' } }
    )
  } catch (error: unknown) {
    return apiError('brokers.list', error, 500, 'Could not load the broker list.')
  }
}
