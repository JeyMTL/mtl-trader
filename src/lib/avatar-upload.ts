import { supabase } from '@/lib/supabase'

/**
 * Profile picture uploads.
 *
 * The `avatars` bucket is public, so the stored value is a plain URL that an
 * <img> tag can load anywhere. Objects still live under `<user_id>/…`, which is
 * what the storage policies check, so a signed-in user can only write into
 * their own folder.
 */

export const AVATAR_BUCKET = 'avatars'
export const MAX_AVATAR_BYTES = 2 * 1024 * 1024

const AVATAR_TYPES = ['image/jpeg', 'image/png', 'image/webp']

/** Returns a human-readable reason the file cannot be used as an avatar, or null. */
export function validateAvatarFile(file: File): string | null {
  const type = file.type.split(';')[0].trim().toLowerCase()
  if (!AVATAR_TYPES.includes(type)) {
    return 'Use a JPEG, PNG or WebP image.'
  }
  if (file.size > MAX_AVATAR_BYTES) {
    return 'Profile pictures must be under 2 MB.'
  }
  return null
}

function extensionFor(file: File): string {
  const fromName = file.name.split('.').pop()?.toLowerCase()
  if (fromName && /^(jpe?g|png|webp)$/.test(fromName)) {
    return fromName === 'jpeg' ? 'jpg' : fromName
  }
  if (file.type.includes('png')) return 'png'
  if (file.type.includes('webp')) return 'webp'
  return 'jpg'
}

export async function uploadAvatar({
  file,
  userId,
}: {
  file: File
  userId: string
}): Promise<string> {
  const invalid = validateAvatarFile(file)
  if (invalid) throw new Error(invalid)

  const contentType = file.type.split(';')[0].trim().toLowerCase()
  const path = `${userId}/${crypto.randomUUID()}.${extensionFor(file)}`

  const { error } = await supabase.storage
    .from(AVATAR_BUCKET)
    .upload(path, file, { contentType, upsert: false })
  if (error) throw new Error(error.message)

  const { data } = supabase.storage.from(AVATAR_BUCKET).getPublicUrl(path)
  return data.publicUrl
}

/**
 * Best-effort cleanup of the picture being replaced, so switching avatars does
 * not leave every previous upload behind. Ignores anything outside this user's
 * folder, including links the user pasted from elsewhere.
 */
export async function deleteAvatarByUrl(
  url: string | null | undefined,
  userId: string
): Promise<void> {
  if (!url) return
  const marker = `/object/public/${AVATAR_BUCKET}/`
  const index = url.indexOf(marker)
  if (index < 0) return

  const path = decodeURIComponent(url.slice(index + marker.length))
  if (!path.startsWith(`${userId}/`)) return

  await supabase.storage.from(AVATAR_BUCKET).remove([path])
}
