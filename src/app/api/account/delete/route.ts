import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { apiError, logEvent } from '@/lib/log'
import { readJsonBody } from '@/lib/request'

/**
 * Deletes the caller's account.
 *
 * The data removal is one statement (`delete_account_data`), and every
 * user-owned table references `users(id)` with `ON DELETE CASCADE`, so a
 * half-deleted account is no longer possible. Deleting the auth identity is the
 * only step that cannot be inside that transaction; if it fails the user can
 * retry, because the data function is idempotent.
 *
 * Requires the caller to echo their own email, which stops a stray request (or an
 * XSS payload) from destroying the account on its own.
 */
export async function POST(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    if (!user.email) {
      return NextResponse.json({ error: 'Account has no email address to confirm' }, { status: 400 })
    }

    const parsed = await readJsonBody<{ userId?: unknown; confirmEmail?: unknown }>(req, {
      allowEmpty: true,
      maxBytes: 8 * 1024,
    })
    if (!parsed.ok) return parsed.response
    const body = parsed.value

    if (typeof body.userId === 'string' && body.userId && body.userId !== user.id) {
      return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    }

    const confirmEmail = typeof body.confirmEmail === 'string' ? body.confirmEmail.trim().toLowerCase() : ''
    if (!confirmEmail || confirmEmail !== user.email.toLowerCase()) {
      return NextResponse.json(
        { error: 'Type your account email to confirm deletion' },
        { status: 400 }
      )
    }

    const supabase = getAdminClient()

    // Storage objects do not cascade with the database rows. Remove the
    // journal's photos and voice notes while the attachment paths still exist.
    // A storage failure must never block the deletion itself, so this whole
    // block is best-effort and only logged.
    try {
      const { data: mediaRows } = await supabase
        .from('trade_attachments')
        .select('storage_path')
        .eq('user_id', user.id)
      const mediaPaths = (mediaRows ?? [])
        .map((row: { storage_path: string | null }) => row.storage_path)
        .filter((path): path is string => Boolean(path))
      for (let index = 0; index < mediaPaths.length; index += 500) {
        const { error: storageError } = await supabase.storage
          .from('journal-media')
          .remove(mediaPaths.slice(index, index + 500))
        if (storageError) {
          // The account is still deleted; this is logged so orphans can be swept.
          logEvent('error', 'account.delete.storage', { error: storageError, userId: user.id })
          break
        }
      }
    } catch (storageFailure) {
      logEvent('error', 'account.delete.storage', { error: storageFailure, userId: user.id })
    }

    const { data: result, error: deleteError } = await supabase.rpc('delete_account_data', {
      p_user_id: user.id,
    })

    if (deleteError) {
      return apiError('account.delete', deleteError, 500, 'Could not delete the account data.')
    }
    if (result !== 'deleted' && result !== 'not_found') {
      return apiError('account.delete', new Error(`Unexpected delete result: ${String(result)}`), 500, 'Could not delete the account data.')
    }

    const { error: authError } = await supabase.auth.admin.deleteUser(user.id)
    if (authError) {
      // Data is gone; only the identity remains. A retry finishes the job.
      logEvent('error', 'account.delete.identity', { error: authError, userId: user.id })
      return NextResponse.json(
        { error: 'Your data was deleted, but the sign-in record could not be removed. Please try again.' },
        { status: 500 }
      )
    }

    logEvent('info', 'account.delete', { userId: user.id })
    return NextResponse.json({ success: true })
  } catch (error: unknown) {
    return apiError('account.delete', error, 500, 'Could not delete the account.')
  }
}
