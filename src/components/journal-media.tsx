'use client'

import { useEffect, useRef, useState, type Dispatch, type SetStateAction } from 'react'
import {
  Camera,
  Image as ImageIcon,
  Loader2,
  Mic,
  Square,
  Trash2,
  Upload,
  Volume2,
  X,
} from 'lucide-react'
import {
  deleteJournalMedia,
  formatBytes,
  formatClock,
  isAudioFile,
  isImageFile,
  listJournalMedia,
  persistJournalMedia,
  readAudioDuration,
  signedJournalMediaUrl,
  uploadJournalMedia,
  type JournalAttachment,
  type MediaKind,
  type PendingJournalAttachment,
} from '@/lib/journal-media'

const EMPTY_EXISTING: JournalAttachment[] = []

interface JournalMediaProps {
  userId: string
  tradeId?: string
  pending: PendingJournalAttachment[]
  onPendingChange: Dispatch<SetStateAction<PendingJournalAttachment[]>>
  existing?: JournalAttachment[]
  onExistingChange?: (next: JournalAttachment[]) => void
  disabled?: boolean
}

function supportedAudioMime(): string | null {
  if (typeof MediaRecorder === 'undefined') return null
  for (const type of ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg']) {
    if (MediaRecorder.isTypeSupported(type)) return type
  }
  return null
}

export function JournalMedia({
  userId,
  tradeId,
  pending,
  onPendingChange,
  existing = EMPTY_EXISTING,
  onExistingChange,
  disabled = false,
}: JournalMediaProps) {
  const imageInput = useRef<HTMLInputElement>(null)
  const audioInput = useRef<HTMLInputElement>(null)
  const recorder = useRef<MediaRecorder | null>(null)
  const stream = useRef<MediaStream | null>(null)
  const chunks = useRef<Blob[]>([])
  const timer = useRef<ReturnType<typeof setInterval> | null>(null)

  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [recording, setRecording] = useState(false)
  const [seconds, setSeconds] = useState(0)
  const [urls, setUrls] = useState<Record<string, string>>({})

  const canUse = Boolean(userId) && !disabled

  // Private bucket: each attachment is shown through a short-lived signed URL.
  useEffect(() => {
    let active = true
    const rows = existing ?? []
    if (rows.length === 0) return
    async function load() {
      const entries = await Promise.all(
        rows.map(async (row) => {
          const url = await signedJournalMediaUrl(row.storage_path)
          return [row.id, url] as const
        })
      )
      if (!active) return
      setUrls(Object.fromEntries(entries.filter((entry): entry is readonly [string, string] => Boolean(entry[1]))))
    }
    load()
    return () => {
      active = false
    }
  }, [existing])

  // Stopping the stream on unmount releases the microphone indicator.
  useEffect(() => {
    return () => {
      if (timer.current) clearInterval(timer.current)
      if (recorder.current?.state === 'recording') recorder.current.stop()
      stream.current?.getTracks().forEach((track) => track.stop())
    }
  }, [])

  const stopTracks = () => {
    stream.current?.getTracks().forEach((track) => track.stop())
    stream.current = null
  }

  const addPending = (item: PendingJournalAttachment) => {
    onPendingChange((previous) => [...previous, item])
  }

  const uploadFiles = async (files: FileList | File[] | null, kind: MediaKind) => {
    if (!files || !userId) return
    const list = Array.from(files)
    if (list.length === 0) return

    setBusy(true)
    setError('')
    const failures: string[] = []

    for (const file of list) {
      try {
        const duration = kind === 'audio' ? await readAudioDuration(file) : null
        const uploaded = await uploadJournalMedia({
          file,
          kind,
          userId,
          tradeId,
          durationSeconds: duration,
        })

        if (tradeId) {
          await persistJournalMedia({ userId, tradeId, pending: [uploaded] })
          if (uploaded.previewUrl) URL.revokeObjectURL(uploaded.previewUrl)
          const refreshed = await listJournalMedia(tradeId)
          onExistingChange?.(refreshed)
        } else {
          addPending(uploaded)
        }
      } catch (uploadError) {
        failures.push(`${file.name || 'File'}: ${uploadError instanceof Error ? uploadError.message : 'upload failed'}`)
      }
    }

    if (failures.length > 0) setError(failures.join(' '))
    setBusy(false)
  }

  const handleImagePick = (files: FileList | null) => {
    const images = files ? Array.from(files).filter((file) => isImageFile(file)) : []
    if (files && images.length !== files.length) setError('Only photo files can go in the photo slot.')
    if (images.length > 0) void uploadFiles(images, 'image')
    if (imageInput.current) imageInput.current.value = ''
  }

  const handleAudioPick = (files: FileList | null) => {
    const audio = files ? Array.from(files).filter((file) => isAudioFile(file)) : []
    if (files && audio.length !== files.length) setError('Only audio files can go in the recording slot.')
    if (audio.length > 0) void uploadFiles(audio, 'audio')
    if (audioInput.current) audioInput.current.value = ''
  }

  const startRecording = async () => {
    setError('')
    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === 'undefined') {
      setError('Recording is not supported in this browser. Upload an audio file instead.')
      return
    }
    const mimeType = supportedAudioMime()
    if (!mimeType) {
      setError('Recording is not supported in this browser. Upload an audio file instead.')
      return
    }

    try {
      const media = await navigator.mediaDevices.getUserMedia({ audio: true })
      const audioRecorder = new MediaRecorder(media, { mimeType })
      stream.current = media
      recorder.current = audioRecorder
      chunks.current = []
      setSeconds(0)

      audioRecorder.ondataavailable = (event) => {
        if (event.data.size > 0) chunks.current.push(event.data)
      }

      audioRecorder.onstop = () => {
        if (timer.current) clearInterval(timer.current)
        timer.current = null
        setRecording(false)
        stopTracks()

        // `audioRecorder.mimeType` can carry a codecs parameter; the storage
        // bucket only accepts the base MIME type.
        const mimeType = (audioRecorder.mimeType || 'audio/webm').split(';')[0].trim()
        const blob = new Blob(chunks.current, { type: mimeType })
        chunks.current = []
        if (blob.size === 0) {
          setError('Nothing was recorded. Check the microphone and try again.')
          return
        }
        const extension = mimeType.includes('mp4') ? 'm4a' : 'webm'
        const file = new File([blob], `voice-note-${new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-')}.${extension}`, {
          type: mimeType,
        })
        void uploadFiles([file], 'audio')
      }

      audioRecorder.start()
      setRecording(true)
      timer.current = setInterval(() => setSeconds((value) => value + 1), 1000)
    } catch (recordError) {
      stopTracks()
      const message = recordError instanceof Error ? recordError.message : ''
      setError(
        message.toLowerCase().includes('permission') || message.toLowerCase().includes('denied')
          ? 'Microphone access was blocked. Allow it in your browser settings, or upload an audio file.'
          : 'Could not start recording. Upload an audio file instead.'
      )
    }
  }

  const stopRecording = () => {
    if (recorder.current?.state === 'recording') recorder.current.stop()
  }

  const removePending = async (item: PendingJournalAttachment) => {
    if (item.previewUrl) URL.revokeObjectURL(item.previewUrl)
    onPendingChange((previous) => previous.filter((entry) => entry.id !== item.id))
    await deleteJournalMedia(item)
  }

  const removeExisting = async (item: JournalAttachment) => {
    if (!window.confirm('Remove this file from the journal entry?')) return
    setBusy(true)
    await deleteJournalMedia(item)
    const next = existing.filter((entry) => entry.id !== item.id)
    onExistingChange?.(next)
    setBusy(false)
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <button
          type="button"
          onClick={() => imageInput.current?.click()}
          disabled={!canUse || busy || recording}
          className="btn btn-secondary px-3 py-2 text-xs"
        >
          {busy ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Camera className="h-3.5 w-3.5" />}
          Add photos
        </button>

        {recording ? (
          <button
            type="button"
            onClick={stopRecording}
            className="btn border border-danger/50 bg-danger/10 px-3 py-2 text-xs text-danger"
          >
            <Square className="h-3.5 w-3.5 fill-current" />
            Stop · {formatClock(seconds)}
          </button>
        ) : (
          <button
            type="button"
            onClick={startRecording}
            disabled={!canUse || busy}
            className="btn btn-secondary px-3 py-2 text-xs"
          >
            <Mic className="h-3.5 w-3.5" />
            Record voice note
          </button>
        )}

        <button
          type="button"
          onClick={() => audioInput.current?.click()}
          disabled={!canUse || busy || recording}
          className="btn btn-secondary px-3 py-2 text-xs"
        >
          <Upload className="h-3.5 w-3.5" />
          Upload audio
        </button>

        <input
          ref={imageInput}
          type="file"
          accept="image/*"
          multiple
          className="hidden"
          onChange={(event) => handleImagePick(event.target.files)}
        />
        <input
          ref={audioInput}
          type="file"
          accept="audio/*"
          className="hidden"
          onChange={(event) => handleAudioPick(event.target.files)}
        />
      </div>

      {recording && (
        <div className="flex items-center gap-3 rounded-lg border border-danger/40 bg-danger/5 px-3 py-2 text-xs text-danger">
          <span className="relative flex h-2.5 w-2.5">
            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-danger opacity-60" />
            <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-danger" />
          </span>
          Recording… speak your setup while it is fresh. {formatClock(seconds)} · 25 MB limit
        </div>
      )}

      {error && (
        <div className="flex items-start gap-2 rounded-lg border border-danger/40 bg-danger/10 px-3 py-2 text-xs text-danger">
          <span className="flex-1">{error}</span>
          <button type="button" onClick={() => setError('')} aria-label="Dismiss media error">
            <X className="h-3.5 w-3.5" />
          </button>
        </div>
      )}

      {(pending.length > 0 || existing.length > 0) && (
        <div className="space-y-3">
          {pending.some((item) => item.kind === 'image') || existing.some((item) => item.kind === 'image') ? (
            <div>
              <p className="eyebrow mb-2">Charts & screenshots</p>
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                {pending.filter((item) => item.kind === 'image').map((item) => (
                  <figure key={item.id} className="group relative overflow-hidden rounded-lg border border-border bg-background-raised">
                    {/* Local object URL until the trade is saved. */}
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={item.previewUrl} alt={item.fileName} className="h-24 w-full object-cover" />
                    <figcaption className="truncate px-2 py-1.5 text-[10px] text-gray-500">{item.fileName}</figcaption>
                    <button
                      type="button"
                      onClick={() => void removePending(item)}
                      aria-label={`Remove ${item.fileName}`}
                      className="absolute right-1.5 top-1.5 flex h-6 w-6 items-center justify-center rounded-md bg-black/65 text-white backdrop-blur active:scale-95"
                    >
                      <Trash2 className="h-3 w-3" />
                    </button>
                  </figure>
                ))}

                {existing.filter((item) => item.kind === 'image').map((item) => (
                  <figure key={item.id} className="group relative overflow-hidden rounded-lg border border-border bg-background-raised">
                    {urls[item.id] ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={urls[item.id]} alt={item.file_name || 'Journal screenshot'} className="h-24 w-full object-cover" />
                    ) : (
                      <div className="flex h-24 items-center justify-center text-gray-600">
                        <ImageIcon className="h-5 w-5" />
                      </div>
                    )}
                    <figcaption className="truncate px-2 py-1.5 text-[10px] text-gray-500">
                      {item.file_name || 'Screenshot'}
                    </figcaption>
                    <button
                      type="button"
                      onClick={() => void removeExisting(item)}
                      aria-label={`Remove ${item.file_name || 'screenshot'}`}
                      className="absolute right-1.5 top-1.5 flex h-6 w-6 items-center justify-center rounded-md bg-black/65 text-white backdrop-blur active:scale-95"
                    >
                      <Trash2 className="h-3 w-3" />
                    </button>
                  </figure>
                ))}
              </div>
            </div>
          ) : null}

          {pending.some((item) => item.kind === 'audio') || existing.some((item) => item.kind === 'audio') ? (
            <div>
              <p className="eyebrow mb-2">Voice notes</p>
              <div className="space-y-2">
                {pending.filter((item) => item.kind === 'audio').map((item) => (
                  <div key={item.id} className="flex items-center gap-3 rounded-lg border border-border bg-surface-light px-3 py-2">
                    <Volume2 className="h-4 w-4 shrink-0 text-primary" />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-xs font-medium text-white">{item.fileName}</p>
                      <p className="num text-[10px] text-gray-500">
                        {item.durationSeconds ? formatClock(item.durationSeconds) : 'Audio'} · {formatBytes(item.sizeBytes)} · uploads when you save
                      </p>
                    </div>
                    <button
                      type="button"
                      onClick={() => void removePending(item)}
                      aria-label={`Remove ${item.fileName}`}
                      className="p-1 text-gray-500 hover:text-danger"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  </div>
                ))}

                {existing.filter((item) => item.kind === 'audio').map((item) => (
                  <div key={item.id} className="rounded-lg border border-border bg-surface-light px-3 py-2">
                    <div className="flex items-center gap-3">
                      <Volume2 className="h-4 w-4 shrink-0 text-primary" />
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-xs font-medium text-white">{item.file_name || 'Voice note'}</p>
                        <p className="num text-[10px] text-gray-500">
                          {item.duration_seconds ? formatClock(Number(item.duration_seconds)) : 'Audio'}
                          {item.size_bytes ? ` · ${formatBytes(Number(item.size_bytes))}` : ''}
                        </p>
                      </div>
                      <button
                        type="button"
                        onClick={() => void removeExisting(item)}
                        aria-label={`Remove ${item.file_name || 'voice note'}`}
                        className="p-1 text-gray-500 hover:text-danger"
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </button>
                    </div>
                    {urls[item.id] && (
                      <audio controls preload="none" src={urls[item.id]} className="mt-2 h-9 w-full" />
                    )}
                  </div>
                ))}
              </div>
            </div>
          ) : null}
        </div>
      )}

      {!canUse && !userId && (
        <p className="text-xs text-gray-500">Sign in again to attach photos and recordings.</p>
      )}

      <p className="text-[11px] leading-relaxed text-gray-500">
        Private to your account. Screenshots of the setup and a voice note about the decision are what the
        journal review reads back to you later.
      </p>
    </div>
  )
}
