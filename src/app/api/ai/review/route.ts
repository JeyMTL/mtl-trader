import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { rateLimit } from '@/lib/rate-limit'
import type { SupabaseClient } from '@supabase/supabase-js'
import { hashPayload } from '@/lib/ai/cache'
import { createProvider, resolveProviderConfig } from '@/lib/ai/providers'
import { generateReview, prepareReview } from '@/lib/ai/review'
import { normalizeReview } from '@/lib/ai/schema'
import type { ReviewRequest, ReviewResult, EdgeStats, SimilarSetup } from '@/lib/ai/types'

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

const RATE_LIMIT = 5
const RATE_WINDOW_MS = 10 * 60 * 1000
const CACHE_TTL_MS = 24 * 60 * 60 * 1000

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

    if (error) return NextResponse.json({ error: error.message }, { status: 500 })
    return NextResponse.json({ reviews: data || [] })
  } catch (error: unknown) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Unknown error' },
      { status: 500 }
    )
  }
}

export async function POST(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    // Each call can bill the provider, so cap it per user.
    const limit = rateLimit(`ai-review:${user.id}`, RATE_LIMIT, RATE_WINDOW_MS)
    if (!limit.ok) {
      return NextResponse.json(
        { error: 'Too many review requests. Please try again in a few minutes.' },
        { status: 429, headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) } }
      )
    }

    const config = resolveProviderConfig()
    if (!config) {
      return NextResponse.json(
        { error: 'AI reviews are not configured. Set OPENAI_API_KEY or ANTHROPIC_API_KEY.' },
        { status: 503 }
      )
    }

    const input = (await req.json()) as ReviewRequest
    const hasShape =
      input &&
      typeof input === 'object' &&
      (typeof input.totalTrades === 'number' || Array.isArray(input.trades))
    if (!hasShape) {
      return NextResponse.json({ error: 'Invalid journal input' }, { status: 400 })
    }

    const supabase = getAdminClient()
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
      return NextResponse.json({
        review: cached.review,
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

    const provider = createProvider(config)
    const streamRequested = new URL(req.url).searchParams.get('stream') === '1'
    const prepared = prepareReview(input)

    // Too little data: never call the model, just return the deterministic note.
    if (prepared.skipped) {
      const id = await persistReview(supabase, {
        userId: user.id,
        summaryHash,
        provider: provider.name,
        model: provider.model,
        review: prepared.earlyReview!,
        stats: prepared.stats,
        similar: [],
      })
      return NextResponse.json({
        review: prepared.earlyReview,
        id,
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
              id,
              meta: { provider: provider.name, model: provider.model, cached: false, skipped: false, generatedAt: new Date().toISOString() },
            })
          } catch (error: unknown) {
            send({ type: 'error', error: error instanceof Error ? error.message : 'AI request failed' })
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
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
