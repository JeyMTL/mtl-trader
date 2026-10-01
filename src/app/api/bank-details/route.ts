import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import { getBankDetails } from '@/lib/bank'

/**
 * Returns the configured bank-transfer details to a signed-in user. Kept on the
 * server so the details are deployment configuration, not shipped in the bundle.
 */
export async function GET(req: Request) {
  const user = await getAuthUser(req)
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const bank = getBankDetails()
  if (!bank) {
    return NextResponse.json({ error: 'Bank transfer is not configured for this deployment' }, { status: 503 })
  }

  return NextResponse.json({ bank })
}
