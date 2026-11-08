import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { rateLimit } from '@/lib/rate-limit'
import { apiError } from '@/lib/log'

/**
 * Returns everything the app stores about the caller as a JSON download.
 *
 * Trading history is personal financial data, so users need a way to take it
 * with them without asking support — that is also the GDPR portability
 * requirement that applies to this kind of data.
 */
export async function GET(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const limit = await rateLimit(`account-export:${user.id}`, 5, 60 * 60 * 1000)
    if (!limit.ok) {
      return NextResponse.json(
        { error: 'Too many export requests. Please try again later.' },
        { status: 429, headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) } }
      )
    }

    const supabase = getAdminClient()
    const userId = user.id

    const [profile, trades, deposits, paymentRequests, paymentEvents, reviews, journalMedia] = await Promise.all([
      supabase.from('users').select('*').eq('id', userId).maybeSingle(),
      supabase.from('trades').select('*').eq('user_id', userId).order('close_time', { ascending: true }),
      supabase.from('deposits').select('*').eq('user_id', userId).order('created_at', { ascending: true }),
      supabase.from('payment_requests').select('*').eq('user_id', userId).order('created_at', { ascending: true }),
      supabase.from('payment_events').select('*').eq('user_id', userId).order('created_at', { ascending: true }),
      supabase.from('ai_reviews').select('*').eq('user_id', userId).order('created_at', { ascending: true }),
      supabase.from('trade_attachments').select('*').eq('user_id', userId).order('created_at', { ascending: true }),
    ])

    const failure = [profile, trades, deposits, paymentRequests, paymentEvents, reviews, journalMedia]
      .find((result) => result.error)
    if (failure?.error) {
      return apiError('account.export', failure.error, 500, 'Could not prepare your export.')
    }

    // Never export server-side credentials such as the sync agent token or the
    // billing customer id: a data export is not a secrets backup, and a leaked
    // download must not hand over write access to the account. Strip them from
    // a copy instead of naming columns, so the export keeps working as the
    // profile grows.
    const safeProfile = profile.data ? { ...profile.data } : null
    if (safeProfile) {
      delete safeProfile.agent_token
      delete safeProfile.stripe_customer_id
    }

    const payload = {
      exportedAt: new Date().toISOString(),
      account: {
        id: userId,
        email: user.email,
        profile: safeProfile,
      },
      trades: trades.data ?? [],
      deposits: deposits.data ?? [],
      paymentRequests: paymentRequests.data ?? [],
      paymentEvents: paymentEvents.data ?? [],
      aiReviews: reviews.data ?? [],
      // Attachment metadata, including the private storage path. The files
      // themselves remain in the journal-media bucket.
      journalMedia: journalMedia.data ?? [],
    }

    const filename = `mtl-trader-export-${new Date().toISOString().slice(0, 10)}.json`

    return new NextResponse(JSON.stringify(payload, null, 2), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Content-Disposition': `attachment; filename="${filename}"`,
        'Cache-Control': 'no-store',
      },
    })
  } catch (error: unknown) {
    return apiError('account.export', error, 500, 'Could not prepare your export.')
  }
}
