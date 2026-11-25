#!/usr/bin/env node
// Fills public/locales/web/<code>.json from the English catalog with the
// project's Gemini provider. Writes after every batch, so a rate limit only
// pauses the run; re-running resumes the missing keys.
//
//   node --env-file=.env.local scripts/translate-web.mjs
//
// Restrict a run with WEB_LOCALES=fr,de and tune batching with WEB_BATCH.
import fs from 'node:fs'
import path from 'node:path'

const root = path.resolve(import.meta.dirname, '..')
const enFile = path.join(root, 'public', 'locales', 'web', 'en.json')
const languagesFile = path.join(root, 'src', 'lib', 'i18n', 'languages.json')
const outDir = path.join(root, 'public', 'locales', 'web')

const apiKey = process.env.GEMINI_API_KEY
if (!apiKey) throw new Error('GEMINI_API_KEY is not set')
const model = process.env.GEMINI_MODEL || 'gemini-3.6-flash'
const baseUrl =
  process.env.GEMINI_BASE_URL || 'https://generativelanguage.googleapis.com/v1beta/openai'

const english = JSON.parse(fs.readFileSync(enFile, 'utf8'))
const keys = Object.keys(english)

// The mobile packs already translate the core trading vocabulary. Reusing an
// exact English message from app_en.arb keeps "Win rate" or "Daily stop"
// consistent across the phone and the web instead of asking the model twice.
const mobileEn = JSON.parse(
  fs.readFileSync(path.join(root, 'mobile_flutter', 'lib', 'l10n', 'app_en.arb'), 'utf8')
)
const mobilePacksDir = path.join(root, 'mobile_flutter', 'lib', 'l10n', 'packs')

function mobileGlossary(code) {
  const file = path.join(mobilePacksDir, `app_${code}.arb`)
  if (!fs.existsSync(file)) return {}
  const pack = JSON.parse(fs.readFileSync(file, 'utf8'))
  const glossary = {}
  for (const [key, source] of Object.entries(mobileEn)) {
    if (typeof source !== 'string' || !source.trim()) continue
    const target = pack[key]
    if (typeof target !== 'string' || !target.trim() || target === source) continue
    const normalized = source.replace(/\s+/g, ' ').trim()
    if (!english[normalized]) continue
    if (placeholders(source) !== placeholders(target)) continue
    glossary[normalized] = target
  }
  return glossary
}
const languages = JSON.parse(fs.readFileSync(languagesFile, 'utf8')).filter(
  (language) => language.code !== 'en'
)

const requested = (process.env.WEB_LOCALES || '')
  .split(',')
  .map((code) => code.trim())
  .filter(Boolean)
const selected = requested.length
  ? languages.filter((language) => requested.includes(language.code))
  : languages

const MAX_CHARS = Number(process.env.WEB_BATCH || 12_000)
const CONCURRENCY = Number(process.env.WEB_CONCURRENCY || 3)

const placeholders = (text) =>
  [...new Set([...text.matchAll(/\{(\w+)\}/g)].map((match) => match[1]))].sort().join(',')

function batches() {
  const result = []
  let current = []
  let chars = 0
  for (const key of keys) {
    const size = key.length + english[key].length + 8
    if (current.length > 0 && chars + size > MAX_CHARS) {
      result.push(current)
      current = []
      chars = 0
    }
    current.push(key)
    chars += size
  }
  if (current.length) result.push(current)
  return result
}

async function request(language, pending) {
  const system = [
    `You are a professional software localiser for MTL Ledger, a trading journal, charting and backtesting web app for MetaTrader 5 traders.`,
    `Translate every value into ${language.englishName} (${language.nativeName}).`,
    'Rules:',
    '- Return ONLY a JSON object with exactly the same keys as the input.',
    '- Translate UI labels, headings, helper text, errors and legal copy into natural, concise language.',
    '- Keep placeholders such as {name} or {amount} exactly as written.',
    '- Never translate the brand "MTL Ledger", product names "MT5", "MT4", "TradingView", "Paddle", "PayPal", "Google Play", or ticker symbols such as EURUSD, XAUUSD, US30, NAS100.',
    '- Keep currency codes and symbols unchanged (USD, EUR, $, %, R).',
    '- Use established trading terminology for long, short, stop loss, take profit, drawdown, prop firm, backtest, replay, setup, journal, daily stop, soft lock and hard lock.',
    '- Preserve punctuation, capitalisation used for emphasis, and arrows.',
    '- Do not add explanations or extra keys.',
    '- These are ordinary UI terms and MUST be translated whenever the target language has a word for them: dashboard, settings, save, cancel, analytics, trades, win rate, profit factor, expectancy, drawdown, equity, daily stop, soft lock, hard lock, journal, setup, backtest, replay, session, instrument, direction, description, commission, swap, lots, stop loss, take profit, profit, performance, notifications, support, buy, sell, long, short.',
    '- Keep English only for MTL Ledger, MT5, MT4, TradingView, Paddle, PayPal, Google Play, VWAP, ticker symbols, email addresses, code identifiers, SQL names, file names, and values made only of symbols.',
    '- Do not leave a common noun or verb in English.',
  ].join('\n')

  const user = JSON.stringify(Object.fromEntries(pending.map((key) => [key, english[key]])))

  for (let attempt = 1; attempt <= 8; attempt++) {
    let response
    try {
      response = await fetch(`${baseUrl}/chat/completions`, {
        signal: AbortSignal.timeout(90_000),
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model,
          temperature: 0.15,
          response_format: { type: 'json_object' },
          messages: [
            { role: 'system', content: system },
            { role: 'user', content: user },
          ],
        }),
      })
    } catch (error) {
      if (attempt === 8) throw error
      await new Promise((resolve) => setTimeout(resolve, 2_000 * attempt))
      continue
    }

    if (response.status === 429 || response.status >= 500) {
      const wait = response.status === 429 ? 15_000 * attempt : 4_000 * attempt
      await new Promise((resolve) => setTimeout(resolve, wait))
      continue
    }
    if (!response.ok) {
      const body = await response.text()
      throw new Error(`${language.code}: HTTP ${response.status} ${body.slice(0, 300)}`)
    }

    const body = await response.json()
    let content = body.choices?.[0]?.message?.content ?? ''
    content = content.trim().replace(/^```(?:json)?\s*/i, '').replace(/```$/, '')
    try {
      return JSON.parse(content)
    } catch {
      // A truncated or malformed response is retried with the same batch.
    }
  }
  throw new Error(`${language.code}: no usable response after retries`)
}

async function fillLanguage(language) {
  const outFile = path.join(outDir, `${language.code}.json`)
  const existing = fs.existsSync(outFile)
    ? JSON.parse(fs.readFileSync(outFile, 'utf8'))
    : {}
  let missing = Object.fromEntries(
    keys.filter((key) => typeof existing[key] !== 'string' || !existing[key].trim()).map((key) => [key, key])
  )

  const glossary = mobileGlossary(language.code)
  let fromGlossary = 0
  for (const [key, value] of Object.entries(glossary)) {
    if (existing[key] !== value) {
      existing[key] = value
      fromGlossary++
    }
  }
  missing = Object.fromEntries(
    keys.filter((key) => typeof existing[key] !== 'string' || !existing[key].trim()).map((key) => [key, key])
  )

  if (Object.keys(missing).length === 0) {
    fs.writeFileSync(outFile, `${JSON.stringify(existing, null, 2)}\n`)
    return { code: language.code, added: 0, glossary: fromGlossary, skipped: true }
  }
  console.log(`${language.code}: starting (${Object.keys(missing).length} keys left)`)

  let added = 0
  for (const batch of batches()) {
    const pending = batch.filter((key) => key in missing)
    if (pending.length === 0) continue
    console.log(`${language.code}: translating ${pending.length} (${Object.keys(missing).length} left)`)

    let translated = {}
    let left = [...pending]
    for (let round = 0; round < 3 && left.length > 0; round++) {
      const result = await request(language, left)
      const still = []
      for (const key of left) {
        const value = result[key]
        if (
          typeof value !== 'string' ||
          !value.trim() ||
          placeholders(value) !== placeholders(english[key])
        ) {
          still.push(key)
          continue
        }
        translated[key] = value
      }
      left = still
    }
    if (left.length > 0) {
      throw new Error(`${language.code}: ${left.length} key(s) failed validation: ${left.slice(0, 5)}`)
    }

    for (const [key, value] of Object.entries(translated)) {
      existing[key] = value
      delete missing[key]
      added++
    }
    fs.writeFileSync(outFile, `${JSON.stringify(existing, null, 2)}\n`)
    const done = Object.keys(existing).length
    console.log(`${language.code}: ${done}/${keys.length} keys`)
  }

  const identical = keys.filter((key) => existing[key] === english[key]).length
  return { code: language.code, added, identical, glossary: fromGlossary, skipped: false }
}

let cursor = 0
const results = []
const failures = []

async function worker() {
  while (cursor < selected.length) {
    const language = selected[cursor++]
    try {
      const outcome = await fillLanguage(language)
      results.push(outcome)
      console.log(
        outcome.skipped
          ? `${outcome.code}: already complete (${outcome.glossary} glossary terms)`
          : `${outcome.code}: done (+${outcome.added}, ${outcome.identical} same as English, ${outcome.glossary} glossary terms)`
      )
    } catch (error) {
      failures.push(language.code)
      console.error(`${language.code}: FAILED — ${error.message}`)
    }
  }
}

await Promise.all(Array.from({ length: Math.max(1, CONCURRENCY) }, worker))
console.log(`done: ${results.length} locale(s), ${failures.length} failed`)
if (failures.length > 0) {
  console.error(`re-run to retry: ${failures.join(', ')}`)
  process.exitCode = 1
}
