import { supabase } from '@/lib/supabase'
import type { JournalAttachmentRow } from '@/types/journal'

/**
 * Journal media: photos and voice notes stored in the private `journal-media`
 * bucket, with one `trade_attachments` row per file.
 *
 * Paths start with the user id (`<user_id>/<trade_id|draft>/<uuid>.<ext>`), which
 * is exactly what the storage RLS policy checks, so one trader can never read
 * another trader's files.
 */

export const JOURNAL_MEDIA_BUCKET = 'journal-media'
export const MAX_IMAGE_BYTES = 8 * 1024 * 1024
export const MAX_AUDIO_BYTES = 25 * 1024 * 1024

export type MediaKind = 'image' | 'audio'

export interface PendingJournalAttachment {
  id: string
  kind: MediaKind
  storagePath: string
  fileName: string
  mimeType: string
  sizeBytes: number
  durationSeconds: number | null
  /** Object URL for an instant local preview; revoked by the component. */
  previewUrl?: string
}

export interface JournalAttachment extends JournalAttachmentRow {
  storage_path: string
  url?: string
}

const IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
const AUDIO_TYPES = [
  'audio/webm',
  'audio/ogg',
  'audio/mpeg',
  'audio/mp4',
  'audio/wav',
  'audio/x-wav',
  'audio/x-m4a',
  'audio/m4a',
  'audio/aac',
]

export function isImageFile(file: { type: string }): boolean {
  return file.type.startsWith('image/')
}

export function isAudioFile(file: { type: string }): boolean {
  return file.type.startsWith('audio/')
}

/** Returns a human-readable reason the file cannot be attached, or null. */
export function validateMediaFile(file: File, kind: MediaKind): string | null {
  const allowed = kind === 'image' ? IMAGE_TYPES : AUDIO_TYPES
  const limit = kind === 'image' ? MAX_IMAGE_BYTES : MAX_AUDIO_BYTES
  // MediaRecorder reports `audio/webm;codecs=opus`; the bucket policy matches
  // the base type, so normalise before validating and uploading.
  const type = file.type.split(';')[0].trim().toLowerCase()
  if (!allowed.includes(type)) {
    return kind === 'image'
      ? 'Use a JPEG, PNG, WebP or HEIC photo.'
      : 'Use an MP3, M4A, WAV, OGG or WebM recording.'
  }
  if (file.size > limit) {
    return kind === 'image'
      ? `Photos must be under ${formatBytes(MAX_IMAGE_BYTES)}.`
      : `Recordings must be under ${formatBytes(MAX_AUDIO_BYTES)}.`
  }
  return null
}

export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 B'
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

/** `83` → `1:23`, for the recorder timer and audio chips. */
export function formatClock(totalSeconds: number): string {
  const seconds = Math.max(0, Math.round(totalSeconds))
  const minutes = Math.floor(seconds / 60)
  return `${minutes}:${String(seconds % 60).padStart(2, '0')}`
}

function extensionFor(file: File, kind: MediaKind): string {
  const fromName = file.name.split('.').pop()?.toLowerCase()
  if (fromName && /^[a-z0-9]{2,5}$/.test(fromName)) return fromName
  if (file.type.includes('png')) return 'png'
  if (file.type.includes('webp')) return 'webp'
  if (file.type.includes('heic')) return 'heic'
  if (file.type.includes('mpeg')) return 'mp3'
  if (file.type.includes('wav')) return 'wav'
  if (file.type.includes('mp4') || file.type.includes('m4a')) return 'm4a'
  if (file.type.includes('ogg')) return 'ogg'
  return kind === 'image' ? 'jpg' : 'webm'
}

/** Reads the duration of a local audio file without uploading it first. */
export function readAudioDuration(blob: Blob): Promise<number | null> {
  if (typeof document === 'undefined' || typeof URL === 'undefined') return Promise.resolve(null)
  return new Promise((resolve) => {
    const url = URL.createObjectURL(blob)
    const audio = document.createElement('audio')
    const done = (value: number | null) => {
      URL.revokeObjectURL(url)
      resolve(value)
    }
    audio.preload = 'metadata'
    audio.onloadedmetadata = () => {
      done(Number.isFinite(audio.duration) ? Math.round(audio.duration) : null)
    }
    audio.onerror = () => done(null)
    audio.src = url
  })
}

export async function uploadJournalMedia({
  file,
  kind,
  userId,
  tradeId,
  durationSeconds = null,
}: {
  file: File
  kind: MediaKind
  userId: string
  tradeId?: string
  durationSeconds?: number | null
}): Promise<PendingJournalAttachment> {
  const invalid = validateMediaFile(file, kind)
  if (invalid) throw new Error(invalid)

  const contentType = file.type.split(';')[0].trim().toLowerCase()
  const path = `${userId}/${tradeId || 'draft'}/${crypto.randomUUID()}.${extensionFor(file, kind)}`
  const { error } = await supabase.storage
    .from(JOURNAL_MEDIA_BUCKET)
    .upload(path, file, { contentType, upsert: false })

  if (error) throw new Error(error.message)

  return {
    id: crypto.randomUUID(),
    kind,
    storagePath: path,
    fileName: file.name || (kind === 'image' ? 'Photo' : 'Voice note'),
    mimeType: contentType,
    sizeBytes: file.size,
    durationSeconds: kind === 'audio' ? durationSeconds : null,
    previewUrl: kind === 'image' ? URL.createObjectURL(file) : undefined,
  }
}

/** Writes the `trade_attachments` rows once the trade id exists. */
export async function persistJournalMedia({
  userId,
  tradeId,
  pending,
}: {
  userId: string
  tradeId: string
  pending: PendingJournalAttachment[]
}): Promise<void> {
  if (pending.length === 0) return
  const rows = pending.map((item) => ({
    user_id: userId,
    trade_id: tradeId,
    kind: item.kind,
    storage_path: item.storagePath,
    file_name: item.fileName,
    mime_type: item.mimeType,
    size_bytes: item.sizeBytes,
    duration_seconds: item.durationSeconds,
  }))
  const { error } = await supabase.from('trade_attachments').insert(rows)
  if (error) throw new Error(error.message)
}

export async function listJournalMedia(tradeId: string): Promise<JournalAttachment[]> {
  const { data, error } = await supabase
    .from('trade_attachments')
    .select('*')
    .eq('trade_id', tradeId)
    .order('created_at', { ascending: true })
  if (error) throw new Error(error.message)
  return ((data ?? []) as JournalAttachment[]).filter((row) => Boolean(row.storage_path))
}

export async function signedJournalMediaUrl(path: string, expiresIn = 3600): Promise<string | null> {
  const { data, error } = await supabase.storage
    .from(JOURNAL_MEDIA_BUCKET)
    .createSignedUrl(path, expiresIn)
  if (error) return null
  return data?.signedUrl ?? null
}

export async function deleteJournalMedia(attachment: JournalAttachment | PendingJournalAttachment): Promise<void> {
  const path = 'storagePath' in attachment ? attachment.storagePath : attachment.storage_path
  const id = 'storagePath' in attachment ? undefined : attachment.id

  if (path) {
    await supabase.storage.from(JOURNAL_MEDIA_BUCKET).remove([path])
  }
  if (id) {
    await supabase.from('trade_attachments').delete().eq('id', id)
  }
}

/**
 * Best-effort storage cleanup when a trade or the whole journal is deleted.
 * The database rows cascade, but storage objects do not.
 */
export async function deleteTradeMedia(tradeIds: string[]): Promise<void> {
  if (tradeIds.length === 0) return
  const { data } = await supabase
    .from('trade_attachments')
    .select('storage_path')
    .in('trade_id', tradeIds)
  const paths = ((data ?? []) as Array<{ storage_path: string }>)
    .map((row) => row.storage_path)
    .filter(Boolean)
  if (paths.length > 0) {
    await supabase.storage.from(JOURNAL_MEDIA_BUCKET).remove(paths)
  }
}
