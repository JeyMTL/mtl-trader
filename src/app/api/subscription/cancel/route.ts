import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { cancelAtPeriodEndFields } from '@/lib/subscription'
import { cancelPaddleSubscription } from '@/lib/paddle'
import { apiError } from '@/lib/log'
import { readJsonBody } from '@/lib/request'

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
    const parsed = await readJsonBody<{ userId?: unknown }>(req, { allowEmpty: true, maxBytes: 8 * 1024 })
    if (!parsed.ok) return parsed.response
    const body = parsed.value
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

    // Google Play renewals cannot be stopped from here: Google owns the billing
    // agreement, and this route has no Play API call that cancels it. Setting
    // the local flag would tell the customer billing had stopped while Google
    // kept charging them, so refuse and send them to the Play Store instead.
    const { data: googleSubscription, error: googleLookupError } = await supabase
      .from('google_play_subscriptions')
      .select('state, expires_at')
      .eq('user_id', authUser.id)
      .maybeSingle()

    // A database error is not "no Google subscription". The table is new, so a
    // deployment that has not applied its migration legitimately has none; any
    // other lookup failure could hide an active Play agreement and must not be
    // treated as permission to record a cancellation here.
    if (googleLookupError && googleLookupError.code !== '42P01') {
      return apiError(
        'subscription.cancel.google_lookup',
        googleLookupError,
        503,
        'Could not check whether Google Play bills this subscription. Please try again.'
      )
    }

    const googleExpiry = googleSubscription?.expires_at
      ? new Date(googleSubscription.expires_at).getTime()
      : null
    const googleStillRenews =
      googleSubscription &&
      (googleSubscription.state === 'SUBSCRIPTION_STATE_ACTIVE' ||
        googleSubscription.state === 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD') &&
      // A missing or unreadable expiry fails closed: assuming Google has stopped
      // renewing would let this route claim a cancellation it cannot perform.
      (googleExpiry === null || !Number.isFinite(googleExpiry) || googleExpiry > Date.now())

    if (googleStillRenews) {
      return NextResponse.json(
        {
          error:
            'This subscription is billed by Google Play. Cancel it in the Play Store under Payments & subscriptions; access here continues until Google reports the paid period has ended.',
          code: 'manage_in_play_store',
        },
        { status: 409 }
      )
    }

    // A card subscription keeps charging until Paddle is told to stop, so
    // cancel remotely before recording the local flag. If that call fails the
    // request fails: recording the cancel while the card keeps being billed is
    // the one outcome a customer would never forgive.
    const { data: cardSubscriptions, error: cardLookupError } = await supabase
      .from('billing_subscriptions')
      .select('provider, status, remote_plan_id')
      .eq('user_id', authUser.id)
      .eq('provider', 'paddle')

    // Same rule as Google: a failed lookup cannot prove there is no live card
    // agreement, so it must not fall through to a local cancellation.
    if (cardLookupError) {
      return apiError(
        'subscription.cancel.card_lookup',
        cardLookupError,
        503,
        'Could not check the card subscription. Please try again.'
      )
    }

    for (const subscription of cardSubscriptions ?? []) {
      if (subscription.status !== 'active') continue
      const remoteId = subscription.remote_plan_id
      if (typeof remoteId !== 'string' || !remoteId) {
        return NextResponse.json(
          {
            error:
              'This card subscription has no Paddle reference to cancel. Contact support before assuming billing has stopped.',
            code: 'cancel_unavailable',
          },
          { status: 502 }
        )
      }
      try {
        const cancelled = await cancelPaddleSubscription(remoteId)
        if (!cancelled) {
          return NextResponse.json(
            {
              error:
                'Card billing is not configured on this server, so the subscription was not stopped. Contact support before assuming billing has ended.',
              code: 'cancel_unavailable',
            },
            { status: 502 }
          )
        }
      } catch (error: unknown) {
        return apiError(
          'subscription.cancel.paddle',
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
