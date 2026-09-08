import { createClient, type SupabaseClient } from '@supabase/supabase-js'

let adminClient: SupabaseClient | null = null

export function getAdminClient(): SupabaseClient {
  if (adminClient) return adminClient
  adminClient = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!
  )
  return adminClient
}

export async function getAuthUser(req: Request) {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader || !authHeader.startsWith('Bearer ')) return null
  const token = authHeader.slice('Bearer '.length)
  const { data: { user }, error } = await getAdminClient().auth.getUser(token)
  if (error || !user) return null
  return user
}

export async function requireAdmin(req: Request) {
  const user = await getAuthUser(req)
  if (!user) return { user: null, error: 'Unauthorized' }
  const { data, error } = await getAdminClient()
    .from('users')
    .select('is_admin')
    .eq('id', user.id)
    .single()
  if (error || !data || data.is_admin !== true) {
    return { user: null, error: 'Forbidden' }
  }
  return { user, error: null }
}
