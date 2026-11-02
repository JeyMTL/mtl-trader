#!/usr/bin/env node
/**
 * AI configuration check.
 *
 *   - default    reports which provider the environment resolves to, and which
 *                variable decided it
 *   - --verify   makes one real call with the exact request shape the review
 *                uses (JSON mode, vision model selection aside) and reports the
 *                latency. This is the check that proves a key works before a
 *                customer taps Review.
 *
 * Usage:
 *   node --env-file=.env.local scripts/check-ai.mjs
 *   node --env-file=.env.local scripts/check-ai.mjs --verify
 *
 * No secret is printed, only whether a variable is set and a masked prefix.
 *
 * The provider precedence is duplicated from `src/lib/ai/providers.ts` on
 * purpose: this script runs on plain Node with no build step, and the ordering
 * is three lines. If one changes, change both — `ai-support.test.ts` pins the
 * app side.
 */

const args = process.argv.slice(2)
const verify = args.includes('--verify')

const GEMINI_BASE_URL = 'https://generativelanguage.googleapis.com/v1beta/openai'
const GEMINI_DEFAULT_MODEL = 'gemini-3.6-flash'

const explicit = (process.env.AI_PROVIDER || '').toLowerCase()
const anthropicKey = process.env.ANTHROPIC_API_KEY
const geminiKey = process.env.GEMINI_API_KEY
const aiModel = process.env.AI_MODEL

function mask(value) {
  if (!value) return ''
  if (value.length <= 8) return '••••'
  return `${value.slice(0, 4)}…${value.slice(-4)}`
}

function line(label, ok, detail = '') {
  console.log(`${ok ? '✔' : '✖'} ${label}${detail ? ` — ${detail}` : ''}`)
}

/** Mirrors `resolveProviderConfig`, minus the parts this script does not need. */
function resolve() {
  let provider
  if (['anthropic', 'openai-compatible', 'gemini'].includes(explicit)) {
    provider = explicit
  } else if (anthropicKey) {
    provider = 'anthropic'
  } else if (geminiKey) {
    provider = 'gemini'
  } else {
    return null
  }

  if (provider === 'anthropic') {
    if (!anthropicKey) return null
    return {
      provider,
      apiKey: anthropicKey,
      baseUrl: process.env.ANTHROPIC_BASE_URL || 'https://api.anthropic.com/v1',
      model: aiModel || process.env.ANTHROPIC_MODEL || 'claude-3-5-sonnet-latest',
      keyVar: 'ANTHROPIC_API_KEY',
    }
  }

  if (provider === 'gemini') {
    if (!geminiKey) return null
    return {
      provider,
      apiKey: geminiKey,
      baseUrl: process.env.GEMINI_BASE_URL || GEMINI_BASE_URL,
      model: aiModel || process.env.GEMINI_MODEL || GEMINI_DEFAULT_MODEL,
      keyVar: 'GEMINI_API_KEY',
    }
  }

  const baseUrl = process.env.AI_BASE_URL
  const apiKey = process.env.AI_API_KEY
  const model = aiModel
  if (!baseUrl || !apiKey || !model) return null
  return { provider: 'openai-compatible', apiKey, baseUrl, model, keyVar: 'AI_API_KEY' }
}

console.log('MTL Trader — AI check\n')

if (explicit) {
  line('AI_PROVIDER', true, `${explicit} (explicit — wins over every key)`)
} else {
  line('AI_PROVIDER', true, 'not set — inferred from the keys, paid keys first')
}

for (const [name, value] of [
  ['ANTHROPIC_API_KEY', anthropicKey],
  ['GEMINI_API_KEY', geminiKey],
]) {
  if (value) line(name, true, `set (${mask(value)})`)
  else line(name, false, 'not set')
}

const config = resolve()
if (!config) {
  console.log('\n✖ No provider could be resolved — the review answers 503.')
  console.log('  Cheapest fix: paste a key from https://aistudio.google.com/apikey as GEMINI_API_KEY.')
  process.exitCode = 0
} else {
  console.log('')
  line('resolved provider', true, `${config.provider} via ${config.keyVar}`)
  line('model', true, config.model)
  line('base URL', true, config.baseUrl)
  if (config.provider === 'gemini') {
    console.log('  Free tier: no card needed, quota is per project and visible in AI Studio.')
    console.log('  This path is chosen because no Anthropic key is set.')
  }
  if (!verify) {
    console.log('\nConfig looks resolvable. Prove the key with:')
    console.log('  node --env-file=.env.local scripts/check-ai.mjs --verify')
    process.exitCode = 0
  }
}

/** The same structured-output request the review makes, cut down to one round trip. */
async function verifyProvider(current) {
  console.log(`\n→ Calling ${current.provider} (${current.model}) …`)

  const prompt = 'Reply with only a JSON object: {"ready":true}'
  const started = Date.now()
  let response

  try {
    if (current.provider === 'anthropic') {
      response = await fetch(`${current.baseUrl}/messages`, {
        method: 'POST',
        headers: {
          'x-api-key': current.apiKey,
          'anthropic-version': '2023-06-01',
          'Content-Type': 'application/json',
        },
        signal: AbortSignal.timeout(60000),
        body: JSON.stringify({
          model: current.model,
          max_tokens: 200,
          temperature: 0,
          messages: [{ role: 'user', content: prompt }],
        }),
      })
    } else {
      response = await fetch(`${current.baseUrl}/chat/completions`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${current.apiKey}`,
          'Content-Type': 'application/json',
        },
        signal: AbortSignal.timeout(60000),
        body: JSON.stringify({
          model: current.model,
          temperature: 0,
          // Same ceiling the adapter uses, so a thinking model cannot spend the
          // whole budget before it answers.
          max_tokens: current.provider === 'gemini' ? 2000 : 300,
          ...(current.provider === 'gemini' ? { reasoning_effort: 'low' } : {}),
          response_format: { type: 'json_object' },
          messages: [{ role: 'user', content: prompt }],
        }),
      })
    }
  } catch (error) {
    console.error(`✖ Could not reach ${current.baseUrl}`)
    console.error(`  ${error instanceof Error ? error.message : error}`)
    return 1
  }

  const elapsed = Date.now() - started
  const body = await response.json().catch(() => ({}))

  if (!response.ok) {
    const detail =
      body?.error?.message || body?.error || body?.message || `HTTP ${response.status}`
    console.error(`✖ ${current.provider} REJECTED the request (HTTP ${response.status})`)
    console.error(`  ${String(detail).slice(0, 300)}`)
    if (response.status === 401 || response.status === 403) {
      console.error(`  The key is wrong, revoked, or restricted. Re-copy it from AI Studio.`)
    }
    if (response.status === 404) {
      console.error(`  The model id "${current.model}" does not exist for this key. Set AI_MODEL.`)
    }
    if (response.status === 429) {
      console.error('  Rate limited — the key works, the project is out of quota right now.')
    }
    return 2
  }

  const text =
    current.provider === 'anthropic'
      ? (body.content || [])
          .filter((block) => block.type === 'text')
          .map((block) => block.text || '')
          .join('')
      : body?.choices?.[0]?.message?.content

  if (!text) {
    console.error('✖ The provider answered but returned no text.')
    console.error('  On a thinking model this usually means the token ceiling was too low.')
    return 2
  }

  console.log(`✔ ${current.provider} answered in ${elapsed}ms`)
  console.log(`  ${String(text).replace(/\s+/g, ' ').slice(0, 120)}`)
  console.log('\nThe AI review path is live. Nothing else to configure.')
  return 0
}

if (verify && config) {
  process.exitCode = await verifyProvider(config)
}
