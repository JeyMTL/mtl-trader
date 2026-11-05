import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { googlePlayConfigured } from '@/lib/google-play'
import { syncGoogleSubscription } from '@/lib/google-billing'
import { apiError, apiWarn, logEvent } from '@/lib/log'
import { readJsonBody } from '@/lib/request'

/**
 * Verifies a Google Play purchase and applies the plan it paid for.
 *
 *   POST { purchaseToken }  -> check that purchase and grant its period
 *   POST {}                 -> re-check the purchase already stored for this
 *                              account (used on app start, so a renewal or a
 *                              purchase made on another device is picked up)
 *
 * The route never decides anything itself: `syncGoogleSubscription` asks Google
 * what the token is worth and the database records the resulting period. A caller
 * who posts a token belonging to someone else learns only that it is not theirs,
 * because the plan is applied to the *authenticated* user, not the token's owner.
 */

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function POST(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    if (!googlePlayConfigured()) {
      return NextResponse.json(
        { error: 'Google Play billing is not configured yet.' },
        { status: 503 }
      )
    }

    const parsed = await readJsonBody<{ purchaseToken?: unknown; productId?: unknown }>(req, {
      allowEmpty: true,
      maxBytes: 8 * 1024,
    })
    if (!parsed.ok) return parsed.response
    const body = parsed.value

    let purchaseToken =
      typeof body.purchaseToken === 'string' && body.purchaseToken.trim()
        ? body.purchaseToken.trim()
        : null

    if (!purchaseToken) {
      const { data } = await getAdminClient()
        .from('google_play_subscriptions')
        .select('purchase_token')
        .eq('user_id', user.id)
        .maybeSingle()
      purchaseToken = typeof data?.purchase_token === 'string' ? data.purchase_token : null
    }

    // No purchase anywhere: a free or trial account opening the paywall. Not an
    // error — the app only uses it to decide whether to refresh the plan.
    if (!purchaseToken) {
      return NextResponse.json(
        { status: 'none', planId: null, expiresAt: null, provider: 'google' },
        { headers: { 'Cache-Control': 'no-store' } }
      )
    }

    const result = await syncGoogleSubscription({
      userId: user.id,
      purchaseToken,
      productId: typeof body.productId === 'string' ? body.productId : null,
    })

    if (result.status === 'ignored') {
      return apiWarn(
        'billing.google.unknown_product',
        'That Play purchase does not match a plan here.',
        400,
        { userId: user.id, productId: body.productId ?? null }
      )
    }

    logEvent('info', 'billing.google.verify', {
      userId: user.id,
      status: result.status,
      planId: result.planId,
      applied: result.applied,
    })

    return NextResponse.json(
      { ...result, provider: 'google' },
      { headers: { 'Cache-Control': 'no-store' } }
    )
  } catch (error: unknown) {
    return apiError(
      'billing.google.verify',
      error,
      502,
      'Could not check the Google Play purchase. Please try again.'
    )
  }
}
