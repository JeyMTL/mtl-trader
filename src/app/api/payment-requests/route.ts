import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { PLANS } from '@/lib/plans'
import { randomBytes } from 'node:crypto'

const PLAN_MAP = new Map(
  PLANS.filter((plan) => plan.price > 0).map((plan) => [plan.id, plan])
)

export async function POST(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const body = await req.json() as { planId?: unknown; reference?: unknown }
    const planId = typeof body.planId === 'string' ? body.planId : ''
    const requestedReference = typeof body.reference === 'string' ? body.reference.trim() : ''
    const plan = PLAN_MAP.get(planId)

    if (!plan) {
      return NextResponse.json({ error: 'Invalid plan' }, { status: 400 })
    }
    if (requestedReference.length > 200) {
      return NextResponse.json({ error: 'Payment reference cannot exceed 200 characters' }, { status: 400 })
    }

    const reference = requestedReference || `MTL-${user.id.slice(0, 8).toUpperCase()}-${randomBytes(4).toString('hex').toUpperCase()}`

    const { error } = await getAdminClient().from('payment_requests').insert({
      user_id: user.id,
      plan_id: plan.id,
      amount: plan.price,
      reference,
      status: 'pending',
    })

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 })
    }

    return NextResponse.json({ success: true, reference })
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
