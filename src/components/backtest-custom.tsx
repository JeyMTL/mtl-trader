'use client'

import { useEffect, useRef, useState, type ChangeEvent } from 'react'
import {
  BookOpenCheck,
  ImagePlus,
  Loader2,
  Mic,
  Save,
  Sparkles,
  Square,
  Trash2,
  Wand2,
  AlertTriangle,
  ClipboardCheck,
} from 'lucide-react'
import { authedFetch } from '@/lib/api'
import { useToast } from '@/components/toast'
import { supabase } from '@/lib/supabase'
import { MAX_VOICE_SECONDS, startVoiceNote, voiceNoteSupported, type VoiceRecorder } from '@/lib/voice-note'
import type { RuleSpec } from '@/lib/backtest/rules'

/**
 * "Describe it, then backtest it."
 *
 * The trader writes the strategy in their own words, names the timeframes and
 * the stop placement, and may attach a chart that shows exactly what they mean.
 * The model turns that into the closed rule spec the engine runs; the reply is
 * shown back as plain-English rules so the trader can see what was understood
 * before a single bar is simulated.
 *
 * The screenshots are only evidence for the compile step. They are sent with the
 * description, never stored, and never reach the simulation.
 */

export interface CompiledBacktest {
  spec: RuleSpec
  rules: string[]
  disclaimer: string
}

/**
 * These mirror MAX_COMPILE_IMAGES, MAX_COMPILE_CRITERIA and
 * MAX_COMPILE_ATTACHMENT_BYTES on the server. They are duplicated rather than
 * imported because the rule module drags the whole engine into this bundle.
 */
const MAX_IMAGES = 4
const MAX_IMAGE_BYTES = 4 * 1024 * 1024
const MAX_CRITERIA = 2_000
const ATTACHMENT_BUDGET = 3_000_000
const IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp']
const TIMEFRAMES = ['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1', 'W1']

/** Rough byte size of a base64 data URL, for the shared attachment budget. */
function dataUrlBytes(dataUrl: string): number {
  const comma = dataUrl.indexOf(',')
  if (comma === -1) return 0
  return Math.floor(((dataUrl.length - comma - 1) * 3) / 4)
}

function minutesFor(timeframe: string): number | null {
  const match = /^(M|H|D|W)(\d+)$/.exec(timeframe)
  if (!match) return null
  const width = Number(match[2])
  const unit = match[1]
  return unit === 'M' ? width : unit === 'H' ? width * 60 : unit === 'D' ? width * 1440 : width * 10_080
}

/** Mirrors the server rule: a confirmation must group whole primary bars. */
function higherTimeframes(primary: string): string[] {
  const fast = minutesFor(primary)
  if (!fast) return []
  return TIMEFRAMES.filter((candidate) => {
    const slow = minutesFor(candidate)
    if (!slow || slow <= fast) return false
    const ratio = slow / fast
    return Number.isInteger(ratio) && ratio >= 2 && ratio <= 2_000
  })
}

interface ImageAttachment {
  name: string
  dataUrl: string
}

function readAsDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(String(reader.result))
    reader.onerror = () => reject(new Error('Could not read that image.'))
    reader.readAsDataURL(file)
  })
}

export default function BacktestCustom({
  initialSymbol = '',
  onUse,
}: {
  initialSymbol?: string
  onUse: (compiled: CompiledBacktest) => void
}) {
  const { toast } = useToast()
  const [description, setDescription] = useState('')
  const [symbol, setSymbol] = useState(initialSymbol)
  const [timeframe, setTimeframe] = useState('M15')
  const [higherTimeframe, setHigherTimeframe] = useState('')
  const confirmationTimeframes = higherTimeframes(timeframe)
  const [stopLoss, setStopLoss] = useState('')
  const [images, setImages] = useState<ImageAttachment[]>([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [result, setResult] = useState<CompiledBacktest | null>(null)
  const [meta, setMeta] = useState<{ images: number; skipped: number; model: string } | null>(null)
  const [criteria, setCriteria] = useState('')
  const [criteriaState, setCriteriaState] = useState<'loading' | 'saving' | ''>('loading')
  const [recording, setRecording] = useState(false)
  const [recordSeconds, setRecordSeconds] = useState(0)
  const [transcribing, setTranscribing] = useState(false)
  const recorderRef = useRef<VoiceRecorder | null>(null)
  const tickRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const cutoffRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const pickImages = async (event: ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(event.target.files ?? [])
    event.target.value = ''
    if (files.length === 0) return

    const next = [...images]
    let total = next.reduce((sum, image) => sum + dataUrlBytes(image.dataUrl), 0)
    for (const file of files) {
      if (next.length >= MAX_IMAGES) {
        toast(`Up to ${MAX_IMAGES} charts.`, { tone: 'error' })
        break
      }
      if (!IMAGE_TYPES.includes(file.type)) {
        toast(`${file.name}: use a PNG, JPEG or WebP screenshot.`, { tone: 'error' })
        continue
      }
      if (file.size > MAX_IMAGE_BYTES) {
        toast(`${file.name} is over 4 MB. Crop it to the setup.`, { tone: 'error' })
        continue
      }
      // Charts and a recording travel in one request, so the ceiling is on the
      // sum: base64 is a third larger again than the file on disk.
      if (total + file.size > ATTACHMENT_BUDGET) {
        toast('Those charts are too large to send together. Remove one, or crop it.', {
          tone: 'error',
        })
        break
      }
      try {
        next.push({ name: file.name, dataUrl: await readAsDataUrl(file) })
        total += file.size
      } catch {
        toast('Could not read that image.', { tone: 'error' })
      }
    }
    setImages(next)
  }

  // The compiler is stateless, so the trader's own definition of an acceptable
  // setup is kept on the playbook row and sent with every description.
  useEffect(() => {
    let active = true
    async function load() {
      try {
        const {
          data: { user },
        } = await supabase.auth.getUser()
        if (!active) return
        if (!user) return
        const { data } = await supabase
          .from('playbooks')
          .select('backtest_brief')
          .eq('user_id', user.id)
          .maybeSingle()
        if (!active) return
        const stored = (data as { backtest_brief?: string | null } | null)?.backtest_brief
        if (typeof stored === 'string') setCriteria(stored)
      } catch {
        // An unreachable playbook is not an error: the field simply starts empty.
      } finally {
        if (active) setCriteriaState('')
      }
    }
    void load()
    return () => {
      active = false
    }
  }, [])

  // Releasing the microphone on unmount keeps the browser's recording indicator
  // from outliving the panel.
  useEffect(() => {
    return () => {
      if (tickRef.current) clearInterval(tickRef.current)
      if (cutoffRef.current) clearTimeout(cutoffRef.current)
      recorderRef.current?.cancel()
      recorderRef.current = null
    }
  }, [])

  const saveCriteria = async () => {
    setCriteriaState('saving')
    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) {
        toast('Sign in again to save that.', { tone: 'error' })
        return
      }
      const { error: saveError } = await supabase.from('playbooks').upsert(
        {
          user_id: user.id,
          backtest_brief: criteria.trim().slice(0, MAX_CRITERIA),
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'user_id' }
      )
      if (saveError) {
        toast('Could not save that: ' + saveError.message, { tone: 'error' })
        return
      }
      setCriteria(criteria.trim().slice(0, MAX_CRITERIA))
      toast('Acceptance criteria saved.', { tone: 'success' })
    } catch {
      toast('Could not reach the server.', { tone: 'error' })
    } finally {
      setCriteriaState('')
    }
  }

  const stopRecording = async () => {
    const handle = recorderRef.current
    recorderRef.current = null
    if (tickRef.current) clearInterval(tickRef.current)
    if (cutoffRef.current) clearTimeout(cutoffRef.current)
    tickRef.current = null
    cutoffRef.current = null
    setRecording(false)
    if (!handle) return

    setTranscribing(true)
    setError('')
    try {
      const clip = await handle.stop()
      const response = await authedFetch('/api/backtest/transcribe', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ audio: clip.dataUrl }),
      })
      const data = (await response.json()) as { transcript?: string; error?: string }
      if (!response.ok || !data.transcript) {
        setError(data.error || 'Could not use that recording.')
        return
      }
      // The transcript becomes text in the description rather than an opaque
      // attachment: a misheard trading term is fixable before anything compiles.
      const transcript = data.transcript
      setDescription((current) => {
        const existing = current.trim()
        return (existing ? `${existing}\n\n${transcript}` : transcript).slice(0, 4_000)
      })
      toast('Voice note added to the description.', { tone: 'success' })
    } catch {
      setError('Could not use that recording. Type the explanation instead.')
    } finally {
      setTranscribing(false)
    }
  }

  const beginRecording = async () => {
    setError('')
    if (!voiceNoteSupported()) {
      setError('This browser cannot record audio. Type the explanation instead.')
      return
    }
    try {
      const handle = await startVoiceNote()
      recorderRef.current = handle
      setRecording(true)
      setRecordSeconds(0)
      tickRef.current = setInterval(() => setRecordSeconds((value) => value + 1), 1_000)
      cutoffRef.current = setTimeout(() => void stopRecording(), MAX_VOICE_SECONDS * 1_000)
    } catch (recordError) {
      const message = recordError instanceof Error ? recordError.message : ''
      setError(
        message.toLowerCase().includes('permission') || message.toLowerCase().includes('denied')
          ? 'Microphone access was blocked. Allow it, or type the explanation instead.'
          : message || 'Could not start recording. Type the explanation instead.'
      )
    }
  }

  const compile = async () => {
    if (description.trim().length < 20) {
      setError('Describe the setup in at least a sentence — what has to happen before you enter?')
      return
    }
    setBusy(true)
    setError('')
    setResult(null)
    try {
      const response = await authedFetch('/api/backtest/compile', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          description,
          symbol,
          timeframe,
          higherTimeframe: higherTimeframe || null,
          stopLoss,
          criteria: criteria.trim() || null,
          images: images.map((image) => image.dataUrl),
        }),
      })
      const data = (await response.json()) as {
        spec?: RuleSpec
        rules?: string[]
        disclaimer?: string
        error?: string
        meta?: { images?: number; skippedImages?: number; model?: string }
      }
      if (!response.ok || !data.spec) {
        setError(data.error || 'Could not compile that strategy.')
        return
      }
      setResult({
        spec: data.spec,
        rules: data.rules ?? [],
        disclaimer: data.disclaimer ?? '',
      })
      setMeta({
        images: data.meta?.images ?? 0,
        skipped: data.meta?.skippedImages ?? 0,
        model: data.meta?.model ?? '',
      })
    } catch {
      setError('Could not reach the server. Try again.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="space-y-4">
      <div className="rounded-xl border border-border bg-surface p-5">
        <h2 className="flex items-center gap-2 text-sm font-semibold text-white">
          <Wand2 className="h-4 w-4 text-primary" />
          Write the strategy you want tested
        </h2>
        <p className="mt-1 text-xs leading-relaxed text-gray-500">
          Plain English is enough. Say what has to unfold before entry, on which timeframes,
          and where the stop goes. A chart helps more than another paragraph.
        </p>

        <label className="mt-4 mb-2 block text-sm font-medium text-gray-400" htmlFor="custom-description">
          What is the setup?
        </label>
        <textarea
          id="custom-description"
          value={description}
          onChange={(event) => setDescription(event.target.value)}
          rows={7}
          maxLength={4_000}
          placeholder="Example: on the 15 minute chart I wait for price to sweep the Asian session low during London. I only take it if the 1 hour trend is up (price above the 50 EMA). Entry when a bullish engulfing candle closes back above the swept low, stop below the low of that candle, target 2R."
          className="w-full resize-y rounded-lg border border-border bg-background px-4 py-3 text-sm leading-relaxed text-white placeholder-gray-600 focus:border-primary focus:outline-none"
        />
        <p className="mt-1 text-right text-[11px] text-gray-500">{description.length}/4000</p>

        <div className="mt-3 grid gap-3 sm:grid-cols-3">
          <div>
            <label className="mb-2 block text-sm font-medium text-gray-400" htmlFor="custom-symbol">
              Symbol
            </label>
            <input
              id="custom-symbol"
              value={symbol}
              onChange={(event) => setSymbol(event.target.value.toUpperCase())}
              placeholder="EURUSD"
              className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-white placeholder-gray-600 focus:border-primary focus:outline-none"
            />
          </div>
          <div>
            <label className="mb-2 block text-sm font-medium text-gray-400" htmlFor="custom-timeframe">
              You trade on
            </label>
            <select
              id="custom-timeframe"
              value={timeframe}
              onChange={(event) => {
                const next = event.target.value
                setTimeframe(next)
                if (higherTimeframe && !higherTimeframes(next).includes(higherTimeframe)) {
                  setHigherTimeframe('')
                }
              }}
              className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-white focus:border-primary focus:outline-none"
            >
              {TIMEFRAMES.map((value) => (
                <option key={value} value={value}>
                  {value}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="mb-2 block text-sm font-medium text-gray-400" htmlFor="custom-higher">
              Confirmation timeframe
            </label>
            <select
              id="custom-higher"
              value={higherTimeframe}
              onChange={(event) => setHigherTimeframe(event.target.value)}
              className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-white focus:border-primary focus:outline-none"
            >
              <option value="">None</option>
              {confirmationTimeframes.map((value) => (
                <option key={value} value={value}>
                  {value}
                </option>
              ))}
            </select>
          </div>
        </div>

        <label className="mt-4 mb-2 block text-sm font-medium text-gray-400" htmlFor="custom-stop">
          Stop loss placement
        </label>
        <input
          id="custom-stop"
          value={stopLoss}
          onChange={(event) => setStopLoss(event.target.value)}
          placeholder="e.g. below the swept low, or 2 × ATR(14)"
          className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-white placeholder-gray-600 focus:border-primary focus:outline-none"
        />

        <div className="mt-4">
          <div className="mb-2 flex items-center justify-between gap-2">
            <span className="text-sm font-medium text-gray-400">Chart screenshot</span>
            <span className="text-[11px] text-gray-500">{images.length}/{MAX_IMAGES}</span>
          </div>

          <div className="flex flex-wrap items-center gap-2">
            {images.map((image, index) => (
              <div
                key={`${image.name}-${index}`}
                className="group relative h-20 w-28 overflow-hidden rounded-lg border border-border bg-background"
              >
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={image.dataUrl} alt={image.name} className="h-full w-full object-cover" />
                <button
                  type="button"
                  onClick={() => setImages((current) => current.filter((_, position) => position !== index))}
                  aria-label={`Remove ${image.name}`}
                  className="absolute right-1 top-1 rounded-md bg-black/70 p-1 text-gray-300 transition-colors hover:text-danger"
                >
                  <Trash2 className="h-3 w-3" />
                </button>
              </div>
            ))}

            {images.length < MAX_IMAGES && (
              <label className="flex h-20 w-28 cursor-pointer flex-col items-center justify-center gap-1 rounded-lg border border-dashed border-border bg-background text-[11px] text-gray-500 transition-colors hover:border-primary/50 hover:text-white">
                <ImagePlus className="h-4 w-4" />
                Add chart
                <input
                  type="file"
                  accept="image/png,image/jpeg,image/webp"
                  multiple
                  className="hidden"
                  onChange={(event) => void pickImages(event)}
                />
              </label>
            )}
          </div>
          <p className="mt-2 text-[11px] leading-relaxed text-gray-500">
            Mark the entry, the stop and the trigger on the chart if you can. PNG, JPEG or
            WebP, 4 MB each. The picture is used only to understand the description.
          </p>
        </div>

        <div className="mt-4">
          <div className="mb-2 flex items-center justify-between gap-2">
            <span className="text-sm font-medium text-gray-400">Spoken explanation</span>
            <span className="text-[11px] text-gray-500">{MAX_VOICE_SECONDS}s max</span>
          </div>

          <div className="flex flex-wrap items-center gap-2">
            {recording ? (
              <button
                type="button"
                onClick={() => void stopRecording()}
                className="flex items-center gap-2 rounded-lg border border-danger/50 bg-danger/10 px-3 py-2 text-xs font-medium text-white transition-colors hover:bg-danger/20"
              >
                <Square className="h-3 w-3" /> Stop and transcribe · {recordSeconds}s
              </button>
            ) : (
              <button
                type="button"
                onClick={() => void beginRecording()}
                disabled={transcribing}
                className="flex items-center gap-2 rounded-lg border border-border px-3 py-2 text-xs font-medium text-gray-300 transition-colors hover:border-primary/50 hover:text-white disabled:opacity-50"
              >
                {transcribing ? (
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                ) : (
                  <Mic className="h-3.5 w-3.5" />
                )}
                {transcribing ? 'Transcribing…' : 'Record a voice note'}
              </button>
            )}
          </div>

          <p className="mt-2 text-[11px] leading-relaxed text-gray-500">
            Say the parts a paragraph loses — what you actually count as a valid gap or a
            sweep. It is transcribed into the description above as text you can correct, so
            the recording itself is never stored.
          </p>
        </div>

        <button
          type="button"
          onClick={() => void compile()}
          disabled={busy}
          className="mt-4 flex w-full items-center justify-center gap-2 rounded-lg bg-primary px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-primary-dark disabled:opacity-50"
        >
          {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Sparkles className="h-4 w-4" />}
          {busy ? 'Translating into rules…' : 'Compile rules with AI'}
        </button>

        {error && (
          <p className="mt-3 rounded-lg border border-warning/30 bg-warning/10 px-3 py-2 text-xs text-warning">
            {error}
          </p>
        )}
      </div>

      <div className="rounded-xl border border-border bg-surface p-5">
        <h2 className="flex items-center gap-2 text-sm font-semibold text-white">
          <BookOpenCheck className="h-4 w-4 text-primary" />
          What I count as acceptable
        </h2>
        <p className="mt-1 text-xs leading-relaxed text-gray-500">
          Your standing definition of a valid setup, saved once and sent with every compile
          so you are not retyping it. Anything in it that the engine cannot express comes
          back in the notes.
        </p>

        <textarea
          value={criteria}
          onChange={(event) => setCriteria(event.target.value)}
          rows={5}
          maxLength={MAX_CRITERIA}
          placeholder="e.g. A fair value gap only counts if the middle candle displaced through the prior swing high, the gap is wider than the last 20 bars' average range, and price has not traded back through it. Only in the first two hours of London."
          className="mt-3 w-full resize-y rounded-lg border border-border bg-background px-4 py-3 text-sm leading-relaxed text-white placeholder-gray-600 focus:border-primary focus:outline-none"
        />

        <div className="mt-2 flex flex-wrap items-center justify-between gap-2">
          <span className="text-[11px] text-gray-500">
            {criteria.length}/{MAX_CRITERIA}
          </span>
          <button
            type="button"
            onClick={() => void saveCriteria()}
            disabled={criteriaState !== ''}
            className="flex items-center gap-2 rounded-lg border border-border px-3 py-2 text-xs font-medium text-gray-300 transition-colors hover:border-primary/50 hover:text-white disabled:opacity-50"
          >
            {criteriaState === 'saving' ? (
              <Loader2 className="h-3.5 w-3.5 animate-spin" />
            ) : (
              <Save className="h-3.5 w-3.5" />
            )}
            {criteriaState === 'saving' ? 'Saving…' : 'Save criteria'}
          </button>
        </div>
      </div>

      {result && (
        <div className="rounded-xl border border-primary/30 bg-surface p-5">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div>
              <p className="text-sm font-semibold text-white">{result.spec.name}</p>
              <p className="text-xs text-gray-500">
                {result.spec.summary || 'No summary returned.'}
              </p>
            </div>
            <span className="rounded-full bg-primary/20 px-2.5 py-1 text-[11px] font-medium text-primary">
              compiled
            </span>
          </div>

          <h3 className="mt-4 flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-gray-400">
            <ClipboardCheck className="h-3.5 w-3.5" /> The rules that will run
          </h3>
          <ol className="mt-2 space-y-1.5">
            {result.rules.map((rule) => (
              <li
                key={rule}
                className="flex gap-2 rounded-lg border border-border bg-background px-3 py-2 text-xs leading-relaxed text-gray-300"
              >
                <span className="mt-0.5 text-primary">›</span>
                <span>{rule}</span>
              </li>
            ))}
          </ol>

          {result.spec.notes.length > 0 && (
            <div className="mt-3 space-y-1 rounded-lg border border-warning/20 bg-warning/5 px-3 py-2">
              {result.spec.notes.map((note) => (
                <p key={note} className="flex items-start gap-1.5 text-[11px] leading-relaxed text-yellow-200/90">
                  <AlertTriangle className="mt-0.5 h-3 w-3 shrink-0" />
                  {note}
                </p>
              ))}
            </div>
          )}

          {meta && (meta.images > 0 || meta.skipped > 0) && (
            <p className="mt-2 text-[11px] text-gray-500">
              Read {meta.images} screenshot{meta.images === 1 ? '' : 's'}
              {meta.skipped > 0 ? `, skipped ${meta.skipped} unreadable` : ''}
              {meta.model ? ` · ${meta.model}` : ''}.
            </p>
          )}

          <button
            type="button"
            onClick={() => onUse(result)}
            className="mt-4 flex w-full items-center justify-center gap-2 rounded-lg border border-primary/50 bg-primary/15 px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-primary/25"
          >
            <Wand2 className="h-4 w-4" /> Use these rules in the backtest
          </button>
          <p className="mt-2 text-[11px] leading-relaxed text-gray-500">{result.disclaimer}</p>
        </div>
      )}
    </div>
  )
}
