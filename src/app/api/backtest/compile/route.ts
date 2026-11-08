import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import { rateLimit } from '@/lib/rate-limit'
import { apiError, apiWarn, logEvent } from '@/lib/log'
import { readJsonBody } from '@/lib/request'
import { createProvider, resolveProviderConfig } from '@/lib/ai/providers'
import { checkFeature } from '@/lib/plan-guard'
import {
  MAX_COMPILE_ATTACHMENT_BYTES,
  MAX_COMPILE_CRITERIA,
  MAX_COMPILE_DESCRIPTION,
  MAX_COMPILE_IMAGES,
  RULE_SPEC_DISCLAIMER,
  buildCompileMessages,
  describeRuleSpec,
  higherTimeframeRatio,
  normalizeCriteria,
  normalizeRuleSpec,
  normalizeTimeframe,
} from '@/lib/backtest/rules'

/**
 * Custom backtest compiler.
 *
 * POST { description, timeframe, higherTimeframe?, stopLoss?, symbol?, criteria?, images? }
 *   -> the same description turned into a declarative rule spec, plus that spec
 *      in plain English for the trader to check before running anything.
 *
 * The images are sent from the browser as data URLs (they are not journal
 * attachments, so there is nothing in storage to read). Only the formats vision
 * models actually accept are forwarded; anything else is counted and dropped,
 * because a screenshot silently replaced by "[unreadable image]" would make the
 * model describe a chart it never saw.
 *
 * `criteria` is the trader's saved definition of an acceptable setup. It is sent
 * by the browser rather than read from the database here: it is their own prompt
 * input, the panel already shows it, and keeping the route free of a second
 * lookup means a playbook read failure cannot break a compile.
 *
 * This call is gated exactly like a backtest run: compiling is part of the Pro
 * workbench, and the model call costs money.
 */

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const maxDuration = 60

const VISION_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp'])
const MAX_IMAGE_BYTES = 4 * 1024 * 1024
/** Just above the attachment budget once base64 and the text are added. */
const MAX_BODY_BYTES = 4_400_000

interface UsableImage {
  dataUrl: string
  bytes: number
}

function usableImage(raw: unknown): UsableImage | null {
  if (typeof raw !== 'string') return null
  const match = /^data:(image\/[a-z0-9.+-]+);base64,([a-z0-9+/=\s]+)$/i.exec(raw.trim())
  if (!match) return null
  const mime = match[1].toLowerCase()
  if (!VISION_TYPES.has(mime)) return null
  const bytes = Math.floor((match[2].replace(/\s/g, '').length * 3) / 4)
  if (bytes > MAX_IMAGE_BYTES) return null
  return { dataUrl: raw.trim(), bytes }
}

export async function POST(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const limit = await rateLimit(`backtest-compile:${user.id}`, 5, 10 * 60 * 1000)
    if (!limit.ok) {
      return NextResponse.json(
        { error: 'Too many compiles. Try again in a few minutes.' },
        { status: 429, headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) } }
      )
    }

    const gate = await checkFeature(user.id, 'backtest')
    if (!gate.allowed) {
      return NextResponse.json(
        { error: gate.message, code: 'upgrade_required' },
        { status: gate.status }
      )
    }

    const parsed = await readJsonBody<Record<string, unknown>>(req, { maxBytes: MAX_BODY_BYTES })
    if (!parsed.ok) return parsed.response
    const body = parsed.value

    const description = typeof body.description === 'string' ? body.description.trim() : ''
    if (description.length < 20) {
      return apiWarn(
        'backtest.compile.invalid',
        'Describe the strategy in at least a sentence — what has to happen before you take the trade?',
        400
      )
    }

    const config = resolveProviderConfig()
    if (!config) {
      return NextResponse.json(
        {
          error:
            'AI compilation is not configured. Set GEMINI_API_KEY (free tier) or ANTHROPIC_API_KEY.',
        },
        { status: 503 }
      )
    }

    const rawImages = Array.isArray(body.images) ? body.images : []
    const images: string[] = []
    let attachmentBytes = 0
    let overBudget = false
    for (const candidate of rawImages) {
      if (images.length >= MAX_COMPILE_IMAGES) break
      const image = usableImage(candidate)
      if (!image) continue
      // Dropping a chart the trader attached would compile rules from less than
      // they sent, so a budget breach is refused rather than trimmed.
      if (attachmentBytes + image.bytes > MAX_COMPILE_ATTACHMENT_BYTES) {
        overBudget = true
        break
      }
      attachmentBytes += image.bytes
      images.push(image.dataUrl)
    }
    if (overBudget) {
      return apiWarn(
        'backtest.compile.attachments',
        'Those attachments are too large to send at once. Use fewer or smaller charts and try again.',
        400
      )
    }
    const skippedImages = rawImages.length - images.length

    const timeframe = normalizeTimeframe(
      typeof body.timeframe === 'string' && body.timeframe.trim() ? body.timeframe : 'M15'
    )
    const higherTimeframe =
      typeof body.higherTimeframe === 'string' && body.higherTimeframe.trim()
        ? normalizeTimeframe(body.higherTimeframe)
        : null

    // The engine builds confirmation bars by grouping an exact number of primary
    // bars. Refuse an unsupported pair here, where the reason can be shown,
    // instead of letting the normaliser silently drop it and returning rules the
    // trader did not ask for.
    if (higherTimeframe && higherTimeframeRatio(timeframe, higherTimeframe) === null) {
      return apiWarn(
        'backtest.compile.invalid_timeframes',
        `A ${higherTimeframe} confirmation cannot be built from ${timeframe} bars. Choose a higher timeframe that divides into whole ${timeframe} bars.`,
        400
      )
    }

    const criteria = normalizeCriteria(body.criteria)

    const provider = createProvider(config)
    let raw: string
    try {
      raw = await provider.complete(
        buildCompileMessages(
          {
            description: description.slice(0, MAX_COMPILE_DESCRIPTION),
            timeframe,
            higherTimeframe,
            stopLoss: typeof body.stopLoss === 'string' ? body.stopLoss : null,
            symbol: typeof body.symbol === 'string' ? body.symbol : null,
            criteria,
          },
          images
        ),
        { json: true, maxTokens: 1_600 }
      )
    } catch (error: unknown) {
      logEvent('warn', 'backtest.compile.provider', { error, userId: user.id })
      return NextResponse.json(
        { error: 'The AI request failed. Try again in a moment.' },
        { status: 502 }
      )
    }

    let spec
    try {
      spec = normalizeRuleSpec(raw)
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : 'The compiled rules were unusable.'
      return apiWarn('backtest.compile.unusable', message, 502)
    }

    // The trader's selections are the contract, not the model's recollection of
    // them. Pinning both fields keeps a run from being compiled for one chart
    // and replayed against another.
    spec.timeframe = timeframe
    spec.higherTimeframe = higherTimeframe

    // Never log the description, the criteria or the images — only the shape of
    // the result.
    logEvent('info', 'backtest.compile', {
      userId: user.id,
      conditions: spec.longEntry.length + spec.shortEntry.length + spec.exit.length,
      higherTimeframe: spec.higherTimeframe,
      images: images.length,
      skippedImages,
      criteriaChars: criteria.length,
    })

    return NextResponse.json(
      {
        spec,
        rules: describeRuleSpec(spec),
        disclaimer: RULE_SPEC_DISCLAIMER,
        meta: {
          provider: provider.name,
          model: provider.model,
          images: images.length,
          skippedImages,
          criteriaChars: criteria.length,
          criteriaLimit: MAX_COMPILE_CRITERIA,
          generatedAt: new Date().toISOString(),
        },
      },
      { headers: { 'Cache-Control': 'no-store' } }
    )
  } catch (error: unknown) {
    return apiError('backtest.compile', error, 500, 'Could not compile that strategy.')
  }
}
