import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { cancelAtPeriodEndFields } from '@/lib/subscription'
import { cancelRemoteSubscription } from '@/lib/flutterwave'
import { apiError } from '@/lib/log'

/**
 * Cancels the renewal of the current paid period.
 *
 * Access continues until `current_period_end` — the user paid for that time and
 * the daily expiry job is what actually downgrades the account. This replaces
 * the old behaviour, which revoked access the instant someone cancelled.
 */
export async function POST(req: Request) {
  try {
    const authUser = await getAuthUser(req)
    if (!authUser) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    // The body is optional; the authenticated user is the source of truth.
    const body = await req.json().catch(() => ({})) as { userId?: unknown }
    if (typeof body.userId === 'string' && body.userId && body.userId !== authUser.id) {
      return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    }

    const supabase = getAdminClient()

    const { data: user, error: userError } = await supabase
      .from('users')
      .select('id, subscription_tier, subscription_status, current_period_end, cancel_at_period_end')
      .eq('id', authUser.id)
      .single()

    if (userError || !user) {
      return NextResponse.json({ error: 'Account not found' }, { status: 404 })
    }

    if (user.subscription_tier === 'free' || user.subscription_status !== 'active') {
      return NextResponse.json({ error: 'No active subscription' }, { status: 400 })
    }

    if (user.cancel_at_period_end) {
      return NextResponse.json({
        success: true,
        alreadyScheduled: true,
        accessUntil: user.current_period_end,
      })
    }

    // A Flutterwave card subscription keeps charging until the gateway is told
    // to stop, so cancel remotely before recording the local flag.
    const { data: cardSubscription } = await supabase
      .from('billing_subscriptions')
      .select('status')
      .eq('user_id', authUser.id)
      .eq('provider', 'flutterwave')
      .maybeSingle()

    if (cardSubscription?.status === 'active' && authUser.email) {
      try {
        await cancelRemoteSubscription(authUser.email)
      } catch (error: unknown) {
        return apiError(
          'subscription.cancel.flutterwave',
          error,
          502,
          'Could not stop the card subscription. Please try again.'
        )
      }
    }

    const { error: updateError } = await supabase
      .from('users')
      .update(cancelAtPeriodEndFields())
      .eq('id', authUser.id)

    if (updateError) {
      return apiError('subscription.cancel', updateError, 500, 'Could not cancel the subscription.')
    }

    return NextResponse.json({
      success: true,
      accessUntil: user.current_period_end,
      message: 'Your subscription will not renew. Access continues until the end of the paid period.',
    })
  } catch (error: unknown) {
    return apiError('subscription.cancel', error, 500, 'Could not cancel the subscription.')
  }
}
