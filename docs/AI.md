# AI Review — Architecture & Configuration

The AI journal review turns a trader's own journal into grounded, actionable
feedback. It is deliberately **hybrid**: deterministic analytics compute the
truth, and the LLM only narrates it. Nothing here places trades or gives
financial advice.

## Design principles

1. **Numbers are computed, never guessed.** `edge-stats.ts` derives every metric
   from the trades. The model is handed those numbers and told they are
   authoritative — it cannot invent statistics.
2. **Everything is pure and testable.** Stats, retrieval, prompting, validation,
   caching, outcomes and tagging are I/O-free. The model call is injected.
3. **Structured output, validated in code.** The model must return JSON; the
   response is parsed and normalized, so it can safely drive the UI.
4. **Fail soft.** Too little data short-circuits *before* any model call. Missing
   config returns 503. Provider errors are surfaced, not swallowed.

## Modules (`src/lib/ai/`)

| File | Responsibility | Tier |
|---|---|---|
| `types.ts` | Shared types | — |
| `edge-stats.ts` | Deterministic metrics: expectancy, streaks, groups by symbol/session/weekday/hold time | 2 |
| `retrieval.ts` | TF-IDF retrieval over the user's own notes (RAG, no embeddings) | 2 |
| `schema.ts` | JSON schema, tolerant extractor, strict normalizer, sample guard | 1 |
| `prompt.ts` | System/user prompt, compact stats, in-context examples | 1 / 3 |
| `providers.ts` | OpenAI, Anthropic, OpenAI-compatible; vision; streaming | 2 / 3 |
| `review.ts` | Orchestrator (`prepareReview`, `generateReview`) | — |
| `cache.ts` | Stable hashing so identical journals reuse a review | 1 |
| `outcomes.ts` | Before/after comparison to track whether advice helped | 3 |
| `autotag.ts` | Rule-based tag suggestions from notes | 2 |

## What each tier delivered

**Tier 1 — grounding & reliability**
- Structured JSON output (validated with `normalizeReview`)
- Richer context: full trades, notes, tags, session, hold time
- Persistence to `ai_reviews` (migration `20261004_add_ai_reviews.sql`)
- 24h cache keyed by a stable hash of the journal state
- Sample-size guard (`DEFAULT_MIN_SAMPLE = 10`) that never calls the model
- Token streaming (`?stream=1`, Server-Sent Events)

**Tier 2 — differentiation**
- Deterministic edge statistics that the model narrates
- Retrieval over the trader's own notes so reviews reference their history
- Rule-based auto-tagging (`POST /api/ai/autotag`) — free, instant
- Multi-provider support with an OpenAI-compatible escape hatch

**Tier 3 — advanced**
- Vision: attach a chart screenshot (`chartImage` data URL) for vision models
- In-context examples: strongest/weakest noted trades are fed as few-shot examples
- Outcome tracking: `compareOutcome()` compares pre/post-review performance

> **Not included:** model fine-tuning. It requires a labelled dataset this
> project does not have. Fine-tuning is discussed as a future option, not
> implemented — do not claim otherwise to buyers.

## API

### `POST /api/ai/review`

Auth: `Authorization: Bearer <supabase access token>` (email-verified).
Rate limit: 5 requests / 10 minutes per user.

Body (`ReviewRequest`): the analytics summary, plus optional `trades[]`,
`question`, and `chartImage` (data URL).

Response:

```json
{
  "review": {
    "headline": "…",
    "confidence": "medium",
    "sampleSize": 42,
    "strengths": [{ "title": "…", "detail": "…", "evidence": "London: +$120" }],
    "risks": [{ "title": "…", "detail": "…" }],
    "actions": [{ "title": "…", "detail": "…" }],
    "similarSetups": [{ "note": "…", "outcome": 50, "when": "2026-06-01", "score": 0.42 }],
    "disclaimer": "…"
  },
  "id": "uuid-or-null",
  "meta": { "provider": "openai", "model": "gpt-4o-mini", "cached": false, "skipped": false }
}
```

Add `?stream=1` to receive `text/event-stream`: `delta` events with text chunks,
then a final `final` event carrying the same `review`/`meta`.

### `GET /api/ai/review`

Returns the caller's 20 most recent saved reviews.

### `POST /api/ai/autotag`

Body `{ "note": "…" }` → `{ "tags": ["breakout", "patient"] }`. No model call.

## Configuration

See `.env.example`. Any one of these enables the review:

- `OPENAI_API_KEY` (+ optional `OPENAI_MODEL`)
- `ANTHROPIC_API_KEY` (+ optional `ANTHROPIC_MODEL`)
- `AI_PROVIDER=openai-compatible` with `AI_BASE_URL` and `AI_API_KEY`

Shared overrides: `AI_MODEL`, `AI_VISION_MODEL`. With none set, the review
returns 503 and the rest of the app is unaffected.

## Privacy & cost

- Only aggregated stats, note excerpts, and (if attached) a chart image are sent
  to the provider. Trade symbols and P&L are included; account numbers are not.
- Results are cached, so an unchanged journal does not re-bill the model.
- Rate limiting caps cost, but it is per-instance in memory — back it with a
  shared store (e.g. Redis) before scaling.

## Extending

- **Embeddings:** swap `retrieval.ts` ranking for vector search (e.g. pgvector);
  the rest of the pipeline is unchanged.
- **Weekly AI digest:** reuse the notification cron and the latest saved review.
- **Outcome dashboard:** surface `compareOutcome()` per saved review.
