import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { trialFields } from '@/lib/subscription'
import { apiError, logEvent } from '@/lib/log'
import { rateLimit, clientKey } from '@/lib/rate-limit'
import { readJsonBody } from '@/lib/request'


export async function POST(req: Request) {
  try {
    // Unauthenticated by necessity (email confirmation can complete before a
    // session exists), so the per-IP budget is the only thing limiting a script
    // that probes UUID/email pairs.
    const limit = await rateLimit(clientKey(req, 'signup'), 10, 60 * 60 * 1000)
    if (!limit.ok) {
      return NextResponse.json(
        { error: 'Too many signup attempts. Please try again later.' },
        {
          status: 429,
          headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) },
        }
      )
    }

    const parsed = await readJsonBody<{
      userId?: unknown
      email?: unknown
      fullName?: unknown
    }>(req, { maxBytes: 8 * 1024 })
    if (!parsed.ok) return parsed.response

    const { userId, email, fullName } = parsed.value
    if (
      typeof userId !== 'string' ||
      userId.length < 1 ||
      userId.length > 64 ||
      typeof email !== 'string' ||
      !email.trim() ||
      email.length > 320
    ) {
      return NextResponse.json({ error: 'Missing or invalid signup details' }, { status: 400 })
    }
    const safeFullName = typeof fullName === 'string' ? fullName.trim().slice(0, 100) : ''

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
    // One response for both failures: distinguishing "no such user" from
    // "wrong email" turns this route into an account-existence oracle.
    if (
      authError ||
      !authData.user ||
      (authData.user.email || '').toLowerCase() !== email.trim().toLowerCase()
    ) {
      return NextResponse.json({ error: 'Could not verify this account' }, { status: 403 })
    }

    const { error } = await supabase.from('users').upsert({
      id: userId,
      email: authData.user.email,
      full_name: safeFullName,
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
