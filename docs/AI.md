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
| `providers.ts` | Gemini, Anthropic, OpenAI-compatible gateways; vision; streaming | 2 / 3 |
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
- Multi-provider support with an OpenAI-compatible gateway escape hatch

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
  "meta": { "provider": "gemini", "model": "gemini-3.6-flash", "cached": false, "skipped": false }
}
```

Add `?stream=1` to receive `text/event-stream`: `delta` events with text chunks,
then a final `final` event carrying the same `review`/`meta`.

### `GET /api/ai/review`

Returns the caller's 20 most recent saved reviews.

### `POST /api/ai/autotag`

Body `{ "note": "…" }` → `{ "tags": ["breakout", "patient"] }`. No model call.

### `POST /api/backtest/suggest`

Not a review: it converts one journal entry into runnable backtest parameters.
Body `{ "tradeId": "uuid" }` → the closest strategy id, clamped parameters, a
short reasoning and a confidence. `GET` on the same path lists the recent trades
it can read, with their note and screenshot counts.

- Notes are trimmed to 1,500 characters; at most two screenshots are attached.
- Images over 4 MB, or in a format the vision provider rejects (HEIC), are
  skipped and counted in `meta.skippedImages` — never sent as an unreadable part.
- The reply is normalized by `src/lib/backtest/suggest.ts`, which rejects an
  unknown strategy and clamps every parameter with the engine's own
  `normalizeParams`, so a hallucinated value cannot reach a run.
- Rate limit: 5 requests / 10 minutes per user. Provider unconfigured → 503.
- The note and the image are never logged; only the symbol, the chosen strategy
  and how many screenshots were sent.

## Configuration

See `.env.example`. Any one of these enables the review:

- `GEMINI_API_KEY` (+ optional `GEMINI_MODEL`) — the free tier, the default
- `ANTHROPIC_API_KEY` (+ optional `ANTHROPIC_MODEL`)
- `AI_PROVIDER=openai-compatible` with `AI_BASE_URL`, `AI_API_KEY` and `AI_MODEL`

There is no OpenAI account path. The `openai-compatible` provider exists for a
self-hosted gateway and is refused unless all three variables are set, so a
half-configured gateway cannot post a journal to a URL nobody chose.

Shared overrides: `AI_MODEL`, `AI_VISION_MODEL`. With none set, the review
returns 503 and the rest of the app is unaffected.

### Running it for free

The review is the only feature that costs money per use, and it does not have to
cost anything to start. Google's Gemini free tier needs no card, and its
OpenAI-compatible endpoint is already supported:

```
GEMINI_API_KEY=your-ai-studio-key
# AI_PROVIDER is inferred; set it explicitly to force the free path
AI_PROVIDER=gemini
# Optional: pin a model, otherwise gemini-3.6-flash is used
# GEMINI_MODEL=gemini-3.6-flash
```

That is the whole setup — one key from Google AI Studio. Vision works too, so an
attached chart screenshot is read on the free tier as well. Structured output is
supported on the compatibility layer, so the JSON contract in `schema.ts` holds.

One adapter detail exists because of that model family: Gemini 3.x spend tokens
thinking before they answer, out of the same budget as the reply. A 900-token
ceiling could therefore be eaten by reasoning and return an empty message, so the
adapter sends `reasoning_effort: "low"` and raises the ceiling to 2,000 tokens
for Gemini only. Other providers keep their exact request shape.

Two more behaviours come from the same incident (2026-11-02): the default model
is pinned to `gemini-3.6-flash` rather than a `latest` alias, because 3.8 Flash
returned 503 "experiencing high demand" while 3.6 answered in ~2s and 2.5 was
closed to new keys; and every request now has a 45s ceiling (`AI_TIMEOUT_MS`),
because a saturated model on the compatibility layer does not fail — it holds
the socket, which the customer experiences as a review that never finishes. The
ceiling sits just inside the routes' 60s `maxDuration`, so the failure is our
own error message rather than a killed function.

Check a key before deploying it:

```
node --env-file=.env.local scripts/check-ai.mjs           # what resolved, and why
node --env-file=.env.local scripts/check-ai.mjs --verify  # one real call
```

Precedence is deliberate: an explicit `AI_PROVIDER` wins, then an Anthropic key,
then Gemini. Adding `ANTHROPIC_API_KEY` later therefore upgrades the path without
touching any code, and removing it falls back to the free tier.

Two limits to know before you point real customers at it:

- Free-tier quotas are enforced by Google (requests per minute and per day, per
  key). Exceeding one returns 429 from the provider, which surfaces as a failed
  review. The per-user rate limit here (5 per 10 minutes) keeps this small for a
  handful of users, not for hundreds.
- A single shared key means one customer's burst can exhaust everyone's budget
  for that minute.

Move to a paid key when the review starts being used daily — at these token
counts that is cents per customer per month, see the cost note below.

## Privacy & cost

- Only aggregated stats, note excerpts, and (if attached) a chart image are sent
  to the provider. Trade symbols and P&L are included; account numbers are not.
- Results are cached, so an unchanged journal does not re-bill the model.
- Rate limiting caps cost, but it is per-instance in memory — back it with a
  shared store (e.g. Redis) before scaling.
- A review is roughly 2,000 input and 600 output tokens: free on the Gemini
  free tier, about 1.5 cents on Claude Sonnet. The monthly
  allowance (30 on Basic, 200 on Pro, `AI_REVIEW_QUOTA`) is what bounds the
  worst case per customer — check `provider` in the response `meta` to see which
  path actually served it.

## Extending

- **Embeddings:** swap `retrieval.ts` ranking for vector search (e.g. pgvector);
  the rest of the pipeline is unchanged.
- **Weekly AI digest:** reuse the notification cron and the latest saved review.
- **Outcome dashboard:** surface `compareOutcome()` per saved review.
