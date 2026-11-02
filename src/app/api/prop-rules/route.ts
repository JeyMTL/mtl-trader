import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { parsePropRules } from '@/lib/prop-rules'
import { apiError } from '@/lib/log'

/**
 * Prop-firm evaluation rules.
 *
 *   GET -> the saved rules plus the standing against them
 *   PUT -> validate and save, then return the new standing
 *
 * The standing is computed in Postgres (`prop_status`) from the trades, so the
 * browser never decides whether a rule is breached. Only this route touches the
 * table: it has RLS enabled with no policies, which is what keeps one customer's
 * evaluation private from another.
 */

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

async function standingFor(userId: string) {
  const { data, error } = await getAdminClient().rpc('prop_status', { p_user_id: userId })
  if (error) throw new Error(error.message)
  return data
}

export async function GET(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const { data: rules, error } = await getAdminClient()
      .from('prop_rules')
      .select(
        'account_size, max_daily_loss_pct, max_drawdown_pct, trailing_drawdown, profit_target_pct, min_trading_days, started_on'
      )
      .eq('user_id', user.id)
      .maybeSingle()

    if (error) {
      // A database that predates the migration is not a failure: the card
      // explains which file to apply instead of showing an error every visit.
      if (/prop_rules|prop_status/.test(error.message)) {
        return NextResponse.json({ configured: false, missing: true })
      }
      return apiError('prop_rules.read', error, 500, 'Could not load your prop rules.')
    }

    if (!rules) {
      return NextResponse.json({ configured: false }, { headers: { 'Cache-Control': 'no-store' } })
    }

    const status = await standingFor(user.id)
    return NextResponse.json(
      { configured: true, rules, status },
      { headers: { 'Cache-Control': 'no-store' } }
    )
  } catch (error: unknown) {
    return apiError('prop_rules.read', error, 500, 'Could not load your prop rules.')
  }
}

export async function PUT(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const body = await req.json().catch(() => null)
    const parsed = parsePropRules(body)
    if (!parsed.ok) {
      return NextResponse.json({ error: parsed.error }, { status: 400 })
    }

    const { error } = await getAdminClient()
      .from('prop_rules')
      .upsert(
        { user_id: user.id, ...parsed.value, updated_at: new Date().toISOString() },
        { onConflict: 'user_id' }
      )

    if (error) {
      if (/prop_rules/.test(error.message)) {
        return NextResponse.json(
          { error: 'Prop rules are unavailable until the database migration is applied.' },
          { status: 503 }
        )
      }
      return apiError('prop_rules.save', error, 500, 'Could not save your prop rules.')
    }

    const status = await standingFor(user.id)
    return NextResponse.json({ configured: true, rules: parsed.value, status })
  } catch (error: unknown) {
    return apiError('prop_rules.save', error, 500, 'Could not save your prop rules.')
  }
}
