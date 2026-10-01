import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { isTrialActive, maxTradesForPlan } from '@/lib/subscription'

/**
 * Repairs accounts created before the unlimited 30-day trial change by raising an
 * active trial's allowance to unlimited. Idempotent and safe to call on every import.
 */
export async function POST(req: Request) {
  const user = await getAuthUser(req)
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const supabase = getAdminClient()
  const { data: account, error: readError } = await supabase
    .from('users')
    .select('subscription_status, trial_ends_at, max_trades')
    .eq('id', user.id)
    .single()

  if (readError || !account) {
    return NextResponse.json({ error: 'Account not found' }, { status: 404 })
  }

  if (!isTrialActive(account)) {
    return NextResponse.json({ unlimited: false })
  }

  const trialMax = maxTradesForPlan('free')
  if (account.max_trades !== trialMax) {
    const { error: updateError } = await supabase
      .from('users')
      .update({ max_trades: trialMax, trades_remaining: trialMax })
      .eq('id', user.id)
    if (updateError) return NextResponse.json({ error: updateError.message }, { status: 500 })
  }

  return NextResponse.json({ unlimited: true })
}
