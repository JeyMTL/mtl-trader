import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'

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

  const trialEndsAt = account.trial_ends_at ? new Date(account.trial_ends_at) : null
  const trialActive = account.subscription_status === 'trial' && trialEndsAt && trialEndsAt > new Date()
  if (!trialActive) {
    return NextResponse.json({ unlimited: false })
  }

  if (account.max_trades !== -1) {
    const { error: updateError } = await supabase
      .from('users')
      .update({ max_trades: -1, trades_remaining: -1 })
      .eq('id', user.id)
    if (updateError) return NextResponse.json({ error: updateError.message }, { status: 500 })
  }

  return NextResponse.json({ unlimited: true })
}
