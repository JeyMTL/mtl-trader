import { NextResponse } from 'next/server'

/**
 * PayPal checkout is closed to new orders.
 *
 * Card subscriptions run through Paddle and bank transfer is approved by hand,
 * so nothing in the product calls this route any more. It answers with a
 * plain explanation instead of creating an order, which also means an old app
 * build or a bookmarked script cannot start a PayPal subscription nobody is
 * watching. The webhook and the capture route stay live: traders who started a
 * PayPal subscription before card checkout keep renewing and keep their access.
 */
export async function POST() {
  return NextResponse.json(
    {
      error:
        'PayPal checkout is no longer offered. Subscribe with card or bank transfer from the pricing page.',
    },
    { status: 410 }
  )
}
