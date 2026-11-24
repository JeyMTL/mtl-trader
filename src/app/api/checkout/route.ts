import { NextResponse } from 'next/server'

/**
 * PayPal checkout is closed to new orders.
 *
 * Card subscriptions run through Paddle, so nothing in the product calls this
 * route any more. It answers with a
 * plain explanation instead of creating an order, which also means an old app
 * build or a bookmarked script cannot start a PayPal subscription nobody is
 * watching. The webhook and the capture route stay live: traders who started a
 * PayPal subscription before card checkout keep renewing and keep their access.
 */
export async function POST() {
  return NextResponse.json(
    {
      error:
        'PayPal checkout is no longer offered. Subscribe with a card from the pricing page.',
    },
    { status: 410 }
  )
}
