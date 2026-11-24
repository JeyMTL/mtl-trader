import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { cancelPaddleSubscription } from '@/lib/paddle'
import { apiError, logEvent } from '@/lib/log'
import { readJsonBody } from '@/lib/request'

/**
 * Deletes the caller's account.
 *
 * The data removal is one statement (`delete_account_data`), and every
 * user-owned table references `users(id)` with `ON DELETE CASCADE`, so a
 * half-deleted account is no longer possible. Deleting the auth identity is the
 * only step that cannot be inside that transaction; if it fails the user can
 * retry, because the data function is idempotent.
 *
 * Requires the caller to echo their own email, which stops a stray request (or an
 * XSS payload) from destroying the account on its own.
 *
 * A card subscription is cancelled before anything is deleted. Paddle bills on
 * its own schedule and knows nothing about this account, so deleting the row
 * while the agreement renewed would charge a card for a product the customer can
 * no longer sign in to. If that cancellation cannot be confirmed, the deletion is
 * refused: leaving someone subscribed is recoverable, taking their money with no
 * account to show for it is not.
 */
export async function POST(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    if (!user.email) {
      return NextResponse.json({ error: 'Account has no email address to confirm' }, { status: 400 })
    }

    const parsed = await readJsonBody<{ userId?: unknown; confirmEmail?: unknown }>(req, {
      allowEmpty: true,
      maxBytes: 8 * 1024,
    })
    if (!parsed.ok) return parsed.response
    const body = parsed.value

    if (typeof body.userId === 'string' && body.userId && body.userId !== user.id) {
      return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    }

    const confirmEmail = typeof body.confirmEmail === 'string' ? body.confirmEmail.trim().toLowerCase() : ''
    if (!confirmEmail || confirmEmail !== user.email.toLowerCase()) {
      return NextResponse.json(
        { error: 'Type your account email to confirm deletion' },
        { status: 400 }
      )
    }

    const supabase = getAdminClient()

    // Cancel any live card agreement first. Google Play renewals are not
    // reachable from here — Google owns that agreement and only the customer can
    // stop it — so the page points Play subscribers at the Play Store instead.
    const { data: cardSubscriptions, error: cardLookupError } = await supabase
      .from('billing_subscriptions')
      .select('provider, status, remote_plan_id')
      .eq('user_id', user.id)
      .in('provider', ['paddle', 'paypal'])

    if (cardLookupError) {
      return apiError(
        'account.delete.billing_lookup',
        cardLookupError,
        503,
        'Could not check whether a card subscription is still billing. Please try again.'
      )
    }

    for (const subscription of cardSubscriptions ?? []) {
      if (subscription.status !== 'active') continue

      // A subscription started under the old PayPal checkout renews at PayPal,
      // and nothing here can stop it. Deleting the account would leave it
      // charging with no login attached, so ask for support instead.
      if (subscription.provider === 'paypal') {
        return NextResponse.json(
          {
            error:
              'This account still has a subscription renewing through PayPal. Email support@mtlledger.com to stop it first — nothing was deleted.',
            code: 'cancel_via_support',
          },
          { status: 409 }
        )
      }

      const remoteId = subscription.remote_plan_id
      if (typeof remoteId !== 'string' || !remoteId) {
        return NextResponse.json(
          {
            error:
              'Your card subscription has no billing reference to cancel. Contact support and we will stop it before deleting the account.',
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
                'Card billing is not configured on this server, so the subscription was not stopped. Nothing was deleted — contact support before assuming billing has ended.',
              code: 'cancel_unavailable',
            },
            { status: 502 }
          )
        }
      } catch (error: unknown) {
        return apiError(
          'account.delete.billing_cancel',
          error,
          502,
          'Could not cancel your card subscription, so nothing was deleted. Please try again.'
        )
      }
    }

    // Storage objects do not cascade with the database rows. Remove the
    // journal's photos and voice notes while the attachment paths still exist.
    // A storage failure must never block the deletion itself, so this whole
    // block is best-effort and only logged.
    try {
      const { data: mediaRows } = await supabase
        .from('trade_attachments')
        .select('storage_path')
        .eq('user_id', user.id)
      const mediaPaths = (mediaRows ?? [])
        .map((row: { storage_path: string | null }) => row.storage_path)
        .filter((path): path is string => Boolean(path))
      for (let index = 0; index < mediaPaths.length; index += 500) {
        const { error: storageError } = await supabase.storage
          .from('journal-media')
          .remove(mediaPaths.slice(index, index + 500))
        if (storageError) {
          // The account is still deleted; this is logged so orphans can be swept.
          logEvent('error', 'account.delete.storage', { error: storageError, userId: user.id })
          break
        }
      }
    } catch (storageFailure) {
      logEvent('error', 'account.delete.storage', { error: storageFailure, userId: user.id })
    }

    const { data: result, error: deleteError } = await supabase.rpc('delete_account_data', {
      p_user_id: user.id,
    })

    if (deleteError) {
      return apiError('account.delete', deleteError, 500, 'Could not delete the account data.')
    }
    if (result !== 'deleted' && result !== 'not_found') {
      return apiError('account.delete', new Error(`Unexpected delete result: ${String(result)}`), 500, 'Could not delete the account data.')
    }

    const { error: authError } = await supabase.auth.admin.deleteUser(user.id)
    if (authError) {
      // Data is gone; only the identity remains. A retry finishes the job.
      logEvent('error', 'account.delete.identity', { error: authError, userId: user.id })
      return NextResponse.json(
        { error: 'Your data was deleted, but the sign-in record could not be removed. Please try again.' },
        { status: 500 }
      )
    }

    logEvent('info', 'account.delete', { userId: user.id })
    return NextResponse.json({ success: true })
  } catch (error: unknown) {
    return apiError('account.delete', error, 500, 'Could not delete the account.')
  }
}
