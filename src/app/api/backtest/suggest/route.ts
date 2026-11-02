import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { rateLimit } from '@/lib/rate-limit'
import { apiError, apiWarn, logEvent } from '@/lib/log'
import { createProvider, resolveProviderConfig } from '@/lib/ai/providers'
import { MAX_SUGGEST_IMAGES, buildSuggestionMessages, normalizeSuggestion } from '@/lib/backtest/suggest'
import type { SuggestionTrade } from '@/lib/backtest/suggest'

/**
 * Strategy suggestions from a journal entry.
 *
 *   GET  -> the recent trades a suggestion can be built from, with media counts
 *   POST -> read one trade's notes and screenshots and return runnable params
 *
 * Only one entry is sent to the model at a time, and the browser never uploads
 * the image: the route reads it from storage under the caller's user id and
 * passes the bytes straight to the provider. The reply is clamped by the shared
 * normaliser, so the numbers returned here are always legal for the engine.
 */

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
// Same reasoning as the AI review route: one vision round trip can legitimately
// outlast the platform default, and a killed function returns nothing at all.
export const maxDuration = 60

const BUCKET = 'journal-media'
/** Vision providers reject HEIC and most other camera formats outright. */
const VISION_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp'])
/** Per-image ceiling: a 12 MP JPEG is ~4 MB, and two of those is already a lot. */
const MAX_IMAGE_BYTES = 4 * 1024 * 1024
const CANDIDATE_LIMIT = 30

interface Candidate {
  id: string
  symbol: string
  timeframe: string | null
  strategy: string | null
  notes: string | null
  pnl: number | null
  closeTime: string | null
  images: number
  audio: number
}

interface AttachmentRow {
  trade_id: string
  kind: string
  storage_path: string
  mime_type: string | null
  size_bytes: number | null
}

export async function GET(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const admin = getAdminClient()
    const { data, error } = await admin
      .from('trades')
      .select('id, symbol, timeframe, strategy, notes, pnl, close_time, created_at')
      .eq('user_id', user.id)
      .order('created_at', { ascending: false })
      .limit(CANDIDATE_LIMIT)

    if (error) return apiError('backtest.suggest.list', error, 500, 'Could not load your journal trades.')

    const rows = (data ?? []) as Array<{
      id: string
      symbol: string
      timeframe: string | null
      strategy: string | null
      notes: string | null
      pnl: number | null
      close_time: string | null
    }>

    // One extra query for the counts, rather than a per-trade call.
    const counts = new Map<string, { images: number; audio: number }>()
    if (rows.length > 0) {
      const { data: attachments } = await admin
        .from('trade_attachments')
        .select('trade_id, kind')
        .in(
          'trade_id',
          rows.map((row) => row.id)
        )
      for (const row of (attachments ?? []) as Array<{ trade_id: string; kind: string }>) {
        const entry = counts.get(row.trade_id) ?? { images: 0, audio: 0 }
        if (row.kind === 'image') entry.images += 1
        if (row.kind === 'audio') entry.audio += 1
        counts.set(row.trade_id, entry)
      }
    }

    const trades: Candidate[] = rows.map((row) => ({
      id: row.id,
      symbol: row.symbol,
      timeframe: row.timeframe,
      strategy: row.strategy,
      notes: row.notes,
      pnl: row.pnl,
      closeTime: row.close_time,
      images: counts.get(row.id)?.images ?? 0,
      audio: counts.get(row.id)?.audio ?? 0,
    }))

    return NextResponse.json(
      { trades },
      { headers: { 'Cache-Control': 'no-store' } }
    )
  } catch (error: unknown) {
    return apiError('backtest.suggest.list', error, 500, 'Could not load your journal trades.')
  }
}

export async function POST(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    // Each call bills the vision model, so this shares the AI review's budget.
    const limit = await rateLimit(`backtest-suggest:${user.id}`, 5, 10 * 60 * 1000)
    if (!limit.ok) {
      return NextResponse.json(
        { error: 'Too many suggestions. Try again in a few minutes.' },
        { status: 429, headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) } }
      )
    }

    const body = (await req.json().catch(() => ({}))) as Record<string, unknown>
    const tradeId = typeof body.tradeId === 'string' ? body.tradeId : ''
    if (!tradeId) return apiWarn('backtest.suggest.invalid', 'Choose a journal trade first.', 400)

    const config = resolveProviderConfig()
    if (!config) {
      return NextResponse.json(
        { error: 'AI suggestions are not configured. Set OPENAI_API_KEY, ANTHROPIC_API_KEY or GEMINI_API_KEY.' },
        { status: 503 }
      )
    }

    const admin = getAdminClient()
    const { data: trade, error: tradeError } = await admin
      .from('trades')
      .select('id, symbol, type, timeframe, strategy, notes, tags, pnl, close_time')
      .eq('id', tradeId)
      .eq('user_id', user.id)
      .maybeSingle()

    if (tradeError) return apiError('backtest.suggest.trade', tradeError, 500, 'Could not load that trade.')
    if (!trade) return NextResponse.json({ error: 'Trade not found.' }, { status: 404 })

    const { images, skipped } = await readImages(String(trade.id))

    const provider = createProvider(config)
    let raw: string
    try {
      raw = await provider.complete(
        buildSuggestionMessages(trade as SuggestionTrade, images),
        { json: true, maxTokens: 700 }
      )
    } catch (error: unknown) {
      logEvent('warn', 'backtest.suggest.provider', { error, userId: user.id })
      return NextResponse.json(
        { error: 'The AI request failed. Try again in a moment.' },
        { status: 502 }
      )
    }

    let suggestion
    try {
      suggestion = normalizeSuggestion(raw, images.length)
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : 'The suggestion was unusable.'
      return apiWarn('backtest.suggest.unusable', message, 502)
    }

    // Never log the note or the image — only what was sent and what came back.
    logEvent('info', 'backtest.suggest', {
      userId: user.id,
      symbol: (trade as { symbol: string }).symbol,
      strategy: suggestion.strategyId,
      images: images.length,
      skippedImages: skipped,
      usedNotes: Boolean((trade as { notes: string | null }).notes?.trim()),
    })

    return NextResponse.json(
      {
        suggestion,
        meta: {
          provider: provider.name,
          model: provider.model,
          images: images.length,
          skippedImages: skipped,
          generatedAt: new Date().toISOString(),
        },
      },
      { headers: { 'Cache-Control': 'no-store' } }
    )
  } catch (error: unknown) {
    return apiError('backtest.suggest', error, 500, 'Could not suggest rules for that trade.')
  }
}

/**
 * Downloads the trade's screenshots into data URLs.
 *
 * Anything the vision model cannot read is counted and dropped rather than sent
 * as a broken part: a HEIC photo silently becoming "[unreadable image]" would
 * make the model describe a chart it never saw.
 */
async function readImages(tradeId: string): Promise<{ images: string[]; skipped: number }> {
  const admin = getAdminClient()
  const { data, error } = await admin
    .from('trade_attachments')
    .select('trade_id, kind, storage_path, mime_type, size_bytes')
    .eq('trade_id', tradeId)
    .eq('kind', 'image')
    .order('created_at', { ascending: true })
    .limit(MAX_SUGGEST_IMAGES + 4)

  if (error || !data) return { images: [], skipped: 0 }

  const images: string[] = []
  let skipped = 0

  for (const attachment of data as AttachmentRow[]) {
    if (images.length >= MAX_SUGGEST_IMAGES) break
    const mime = (attachment.mime_type || '').split(';')[0].trim().toLowerCase()
    if (!VISION_TYPES.has(mime) || !attachment.storage_path) {
      skipped += 1
      continue
    }
    if ((attachment.size_bytes ?? 0) > MAX_IMAGE_BYTES) {
      skipped += 1
      continue
    }

    const { data: file, error: downloadError } = await admin.storage
      .from(BUCKET)
      .download(attachment.storage_path)
    if (downloadError || !file) {
      skipped += 1
      continue
    }

    const bytes = Buffer.from(await file.arrayBuffer())
    if (bytes.byteLength > MAX_IMAGE_BYTES) {
      skipped += 1
      continue
    }
    images.push(`data:${mime};base64,${bytes.toString('base64')}`)
  }

  return { images, skipped }
}
