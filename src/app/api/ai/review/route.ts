import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { rateLimit } from '@/lib/rate-limit'
import { aiReviewsThisMonth, checkFeature } from '@/lib/plan-guard'
import type { SupabaseClient } from '@supabase/supabase-js'
import { hashPayload } from '@/lib/ai/cache'
import { createProvider, resolveProviderConfig } from '@/lib/ai/providers'
import { generateReview, prepareReview } from '@/lib/ai/review'
import { normalizeReview } from '@/lib/ai/schema'
import type { ReviewRequest, ReviewResult, EdgeStats, SimilarSetup, TradeRecord } from '@/lib/ai/types'
import { apiError, logEvent } from '@/lib/log'
import { readJsonBody } from '@/lib/request'

/**
 * POST /api/ai/review
 *   Generates a grounded, structured journal review. Persists the result and
 *   serves a cached copy when the journal state is unchanged (24h window).
 *   Add `?stream=1` for Server-Sent Events (`delta` chunks then a `final`).
 *
 * GET /api/ai/review
 *   Returns the caller's recent saved reviews.
 */

export const dynamic = 'force-dynamic'
// A review is one model round trip on a thinking model: seconds, not
// milliseconds, and longer than the platform default. The provider gives up at
// 45s (AI_TIMEOUT_MS), so this budget is what turns a hung model into our error
// message instead of a killed function.
export const maxDuration = 60

const RATE_LIMIT = 5
const RATE_WINDOW_MS = 10 * 60 * 1000
const CACHE_TTL_MS = 24 * 60 * 60 * 1000
// Upper bound on the trades read for one review. Recent history is what the
// model can actually use, and it keeps the request bounded for large journals.
const REVIEW_TRADE_LIMIT = 1000

function cacheKey(input: ReviewRequest) {
  return {
    trades: input.trades ?? null,
    question: input.question ?? '',
    hasImage: Boolean(input.chartImage),
    summary: {
      totalTrades: input.totalTrades ?? null,
      totalPnl: input.totalPnl ?? null,
      winRate: input.winRate ?? null,
    },
  }
}

interface PersistArgs {
  userId: string
  summaryHash: string
  provider: string
  model: string
  review: ReviewResult
  stats: EdgeStats
  similar: SimilarSetup[]
}

async function persistReview(supabase: SupabaseClient, args: PersistArgs): Promise<string | null> {
  const { data, error } = await supabase
    .from('ai_reviews')
    .insert({
      user_id: args.userId,
      summary_hash: args.summaryHash,
      provider: args.provider,
      model: args.model,
      review: args.review,
      stats: args.stats,
      similar: args.similar,
    })
    .select('id')
    .single()
  if (error) return null
  return (data as { id: string } | null)?.id ?? null
}

export async function GET(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const supabase = getAdminClient()
    const { data, error } = await supabase
      .from('ai_reviews')
      .select('id, review, provider, model, created_at')
      .eq('user_id', user.id)
      .order('created_at', { ascending: false })
      .limit(20)

    if (error) return apiError('ai.review.list', error, 500, 'Could not load saved reviews.')
    return NextResponse.json(
      { reviews: data || [] },
      { headers: { 'Cache-Control': 'no-store' } }
    )
  } catch (error: unknown) {
    return apiError('ai.review.list', error, 500, 'Could not load saved reviews.')
  }
}

export async function POST(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    // Each call can bill the provider, so cap it per user.
    const limit = await rateLimit(`ai-review:${user.id}`, RATE_LIMIT, RATE_WINDOW_MS)
    if (!limit.ok) {
      return NextResponse.json(
        { error: 'Too many review requests. Please try again in a few minutes.' },
        { status: 429, headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) } }
      )
    }

    // Entitlement: every paid plan includes the review (Basic has a monthly
    // taste, Pro the full allowance) and the trial gets the Pro allowance. This
    // runs before any provider work, so a refused caller costs nothing.
    const gate = await checkFeature(user.id, 'ai_review')
    if (!gate.allowed) {
      return NextResponse.json(
        { error: gate.message, code: 'upgrade_required' },
        { status: gate.status }
      )
    }

    const config = resolveProviderConfig()
    if (!config) {
      return NextResponse.json(
        { error: 'AI reviews are not configured. Set GEMINI_API_KEY (free tier) or ANTHROPIC_API_KEY.' },
        { status: 503 }
      )
    }

    const parsed = await readJsonBody<ReviewRequest>(req, { maxBytes: 2 * 1024 * 1024 })
    if (!parsed.ok) return parsed.response
    const input = parsed.value
    const hasShape =
      input &&
      typeof input === 'object' &&
      (typeof input.totalTrades === 'number' || Array.isArray(input.trades))
    if (!hasShape) {
      return NextResponse.json({ error: 'Invalid journal input' }, { status: 400 })
    }

    const supabase = getAdminClient()

    // The analytics page sends summary statistics only; the note-bearing trades
    // are loaded here, so the browser no longer uploads the whole journal.
    if (!Array.isArray(input.trades) || input.trades.length === 0) {
      const { data: tradesForReview, error: tradesError } = await supabase
        .from('trades')
        .select('symbol, type, pnl, lot_size, open_time, close_time, created_at, timeframe, strategy, notes, tags')
        .eq('user_id', user.id)
        .order('close_time', { ascending: false })
        .limit(REVIEW_TRADE_LIMIT)

      if (tradesError) {
        logEvent('warn', 'ai.review.trades', { error: tradesError, userId: user.id })
      } else if (tradesForReview?.length) {
        input.trades = tradesForReview as TradeRecord[]
      }
    }

    const summaryHash = hashPayload(cacheKey(input))

    // Serve a recent identical review instead of re-billing the model.
    const since = new Date(Date.now() - CACHE_TTL_MS).toISOString()
    const { data: cached } = await supabase
      .from('ai_reviews')
      .select('id, review, provider, model, created_at')
      .eq('user_id', user.id)
      .eq('summary_hash', summaryHash)
      .gte('created_at', since)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle()

    if (cached) {
      // The saved review does not store the pattern list, and the insights are
      // pure arithmetic over the trades already loaded — so recompute them here
      // rather than letting a cached response show fewer sections than a fresh
      // one for the same journal.
      const cachedInsights = prepareReview(input).insights
      return NextResponse.json({
        review: cached.review,
        insights: cachedInsights,
        id: cached.id,
        meta: {
          provider: cached.provider,
          model: cached.model,
          cached: true,
          skipped: false,
          generatedAt: cached.created_at,
        },
      })
    }

    // A cached review returned above without inserting a row, so this counts
    // real generations only: one insert per model call, no separate meter.
    const used = await aiReviewsThisMonth(user.id)
    if (gate.quota <= 0 || used >= gate.quota) {
      return NextResponse.json(
        {
          error: `You have used this month's ${gate.quota} AI review${gate.quota === 1 ? '' : 's'}. The allowance resets on the 1st.`,
          code: 'quota_exceeded',
        },
        { status: 402 }
      )
    }

    const provider = createProvider(config)
    const streamRequested = new URL(req.url).searchParams.get('stream') === '1'
    const prepared = prepareReview(input)

    // Too little data: never call the model, just return the deterministic note.
    if (prepared.skipped) {
      // Deliberately not persisted: this answer costs no model call, and the
      // monthly allowance is counted from `ai_reviews`. Writing it would spend a
      // customer's quota on a deterministic "not enough data yet" note.
      return NextResponse.json({
        review: prepared.earlyReview,
        insights: prepared.insights,
        id: null,
        meta: { provider: provider.name, model: provider.model, cached: false, skipped: true, generatedAt: new Date().toISOString() },
      })
    }

    if (streamRequested) {
      const encoder = new TextEncoder()
      const body = new ReadableStream<Uint8Array>({
        async start(controller) {
          const send = (event: unknown) =>
            controller.enqueue(encoder.encode(`data: ${JSON.stringify(event)}\n\n`))
          try {
            let text = ''
            for await (const delta of provider.stream(prepared.messages, { json: true })) {
              text += delta
              send({ type: 'delta', text: delta })
            }
            const review = normalizeReview(text, prepared.stats, prepared.similar)
            const id = await persistReview(supabase, {
              userId: user.id,
              summaryHash,
              provider: provider.name,
              model: provider.model,
              review,
              stats: prepared.stats,
              similar: prepared.similar,
            })
            send({
              type: 'final',
              review,
              insights: prepared.insights,
              id,
              meta: { provider: provider.name, model: provider.model, cached: false, skipped: false, generatedAt: new Date().toISOString() },
            })
          } catch (error: unknown) {
            logEvent('error', 'ai.review.stream', { error })
            send({ type: 'error', error: 'AI request failed. Please try again.' })
          } finally {
            controller.close()
          }
        },
      })
      return new Response(body, {
        headers: {
          'Content-Type': 'text/event-stream; charset=utf-8',
          'Cache-Control': 'no-cache, no-transform',
        },
      })
    }

    const generated = await generateReview(input, {
      complete: (messages, options) => provider.complete(messages, options),
      providerName: provider.name,
      model: provider.model,
    })

    const id = await persistReview(supabase, {
      userId: user.id,
      summaryHash,
      provider: provider.name,
      model: provider.model,
      review: generated.review,
      stats: generated.stats,
      similar: generated.similar,
    })

    return NextResponse.json({
      review: generated.review,
      insights: generated.insights,
      id,
      meta: {
        provider: provider.name,
        model: provider.model,
        cached: false,
        skipped: generated.skipped,
        generatedAt: new Date().toISOString(),
      },
    })
  } catch (error: unknown) {
    return apiError('ai.review', error, 500, 'Could not generate a review. Please try again.')
  }
}
