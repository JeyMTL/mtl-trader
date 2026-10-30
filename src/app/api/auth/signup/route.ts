import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { trialFields } from '@/lib/subscription'
import { apiError, logEvent } from '@/lib/log'

export async function POST(req: Request) {
  try {
    const { userId, email, fullName } = await req.json()

    if (!userId || !email) {
      return NextResponse.json({ error: 'Missing userId or email' }, { status: 400 })
    }

    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
    const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY
    if (!supabaseUrl || !serviceRoleKey) {
      return NextResponse.json({
        error: 'Supabase is not configured on the server. Set NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.',
      }, { status: 500 })
    }

    const supabase = createClient(
      supabaseUrl,
      serviceRoleKey
    )

    const { data: authData, error: authError } = await supabase.auth.admin.getUserById(userId)
    if (authError || !authData.user) {
      return NextResponse.json({ error: 'Auth user not found' }, { status: 404 })
    }

    if ((authData.user.email || '').toLowerCase() !== String(email).trim().toLowerCase()) {
      return NextResponse.json({ error: 'Email does not match the authenticated user' }, { status: 403 })
    }

    const { error } = await supabase.from('users').upsert({
      id: userId,
      email: authData.user.email,
      full_name: fullName || '',
      ...trialFields(),
    }, { onConflict: 'id', ignoreDuplicates: true })

    if (error) {
      return apiError('auth.signup.profile', error, 500, 'Could not create your profile. Please try again.')
    }

    logEvent('info', 'auth.signup.profile', { userId })
    return NextResponse.json({ success: true })
  } catch (error: unknown) {
    return apiError('auth.signup', error, 500, 'Could not create your profile. Please try again.')
  }
}
