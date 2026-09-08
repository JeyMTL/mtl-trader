import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { randomBytes } from 'node:crypto'

export async function POST(req: Request) {
  try {
    const authUser = await getAuthUser(req)
    if (!authUser) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const token = randomBytes(32).toString('hex')
    const { error } = await getAdminClient()
      .from('users')
      .update({ agent_token: token })
      .eq('id', authUser.id)

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 })
    }

    return NextResponse.json({ token })
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}