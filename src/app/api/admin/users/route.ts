import { NextResponse } from 'next/server'
import { getAdminClient, requireAdmin } from '@/lib/server-auth'

export async function GET(req: Request) {
  try {
    const { user, error } = await requireAdmin(req)
    if (!user) {
      return NextResponse.json({ error }, { status: error === 'Unauthorized' ? 401 : 403 })
    }

    const supabase = getAdminClient()
    const [{ data: authData, error: authError }, { data: profiles, error: profileError }] = await Promise.all([
      supabase.auth.admin.listUsers({ page: 1, perPage: 1000 }),
      supabase
        .from('users')
        .select('id, email, full_name, subscription_tier, subscription_status, trial_ends_at, created_at')
        .order('created_at', { ascending: false }),
    ])

    if (authError) {
      return NextResponse.json({ error: authError.message }, { status: 500 })
    }
    if (profileError) {
      return NextResponse.json({ error: profileError.message }, { status: 500 })
    }

    const profileMap = new Map((profiles || []).map((profile) => [profile.id, profile]))
    const users = (authData?.users || []).map((authUser) => {
      const profile = profileMap.get(authUser.id)
      return {
        id: authUser.id,
        email: authUser.email || profile?.email || '',
        full_name: profile?.full_name || authUser.user_metadata?.full_name || '',
        subscription_tier: profile?.subscription_tier || 'free',
        subscription_status: profile?.subscription_status || 'trial',
        trial_ends_at: profile?.trial_ends_at || null,
        created_at: profile?.created_at || authUser.created_at,
        last_sign_in_at: authUser.last_sign_in_at || null,
        email_confirmed_at: authUser.email_confirmed_at || null,
      }
    })

    return NextResponse.json({ users })
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
