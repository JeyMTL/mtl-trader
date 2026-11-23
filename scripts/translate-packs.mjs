#!/usr/bin/env node
// Fills every missing key in mobile_flutter/lib/l10n/packs/app_*.arb by
// translating app_en.arb with the project's Gemini provider. Writes each pack
// as it completes, so a rate limit or a failed batch can be resumed by re-running.
//
//   node --env-file=.env.local scripts/translate-packs.mjs
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const l10nDir = path.join(root, 'mobile_flutter', 'lib', 'l10n');
const packsDir = path.join(l10nDir, 'packs');

const apiKey = process.env.GEMINI_API_KEY;
if (!apiKey) throw new Error('GEMINI_API_KEY is not set');
const model = process.env.GEMINI_MODEL || 'gemini-3.6-flash';
const baseUrl =
  process.env.GEMINI_BASE_URL || 'https://generativelanguage.googleapis.com/v1beta/openai';

const template = JSON.parse(fs.readFileSync(path.join(l10nDir, 'app_en.arb'), 'utf8'));
const englishKeys = Object.keys(template).filter(
  (key) => !key.startsWith('@') && typeof template[key] === 'string',
);

const placeholders = (text) =>
  [...new Set([...text.matchAll(/\{(\w+)\}/g)].map((match) => match[1]))].sort().join(',');

// English names for the prompt, straight from the picker catalogue.
const localeSource = fs.readFileSync(
  path.join(root, 'mobile_flutter', 'lib', 'core', 'locale.dart'),
  'utf8',
);
const englishNames = {};
for (const match of localeSource.matchAll(
  /AppLanguage\(\s*code: '([^']+)'[\s\S]*?englishName: '([^']+)'/g,
)) {
  englishNames[match[1]] = match[2];
}

async function request(language, pending) {
  const system = [
    'You are a professional software localiser for a trading-journal mobile app.',
    `Translate every value into ${language}.`,
    'Rules:',
    '- Return ONLY a JSON object with exactly the same keys as the input.',
    '- Translate the meaning for a short mobile UI: concise, natural, no extra punctuation.',
    '- Keep placeholders such as {name} or {amount} exactly as written.',
    '- Do not translate the brand "MTL Ledger", or product names "MT5", "MT4", "TradingView", "Paddle", "Stripe".',
    '- Keep currency and ticker symbols unchanged (USD, EURUSD, GBPJPY, $, %).',
    '- Never leave a value in English unless it is a proper noun or an acronym.',
  ].join('\n');

  const user = JSON.stringify(
    Object.fromEntries(pending.map((key) => [key, template[key]])),
  );

  for (let attempt = 1; attempt <= 8; attempt++) {
    const response = await fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        temperature: 0.2,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: user },
        ],
      }),
    });

    if (response.status === 429 || response.status >= 500) {
      const wait = response.status === 429 ? 15_000 * attempt : 5_000 * attempt;
      await new Promise((resolve) => setTimeout(resolve, wait));
      continue;
    }
    if (!response.ok) {
      const body = await response.text();
      throw new Error(`${language}: HTTP ${response.status} ${body.slice(0, 300)}`);
    }

    const body = await response.json();
    let content = body.choices?.[0]?.message?.content ?? '';
    content = content.trim().replace(/^```(?:json)?\s*/i, '').replace(/```$/, '');
    let parsed;
    try {
      parsed = JSON.parse(content);
    } catch {
      continue;
    }
    return parsed;
  }
  throw new Error(`${language}: no usable response after retries`);
}

async function fillPack(file) {
  const filePath = path.join(packsDir, file);
  const pack = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const code = pack['@@locale'];
  const missing = englishKeys.filter((key) => typeof pack[key] !== 'string');
  if (missing.length === 0) return { code, added: 0, skipped: true };

  const language = englishNames[code] || code;
  let pending = [...missing];
  const translated = {};

  for (let round = 0; round < 3 && pending.length > 0; round++) {
    const result = await request(language, pending);
    const stillPending = [];
    for (const key of pending) {
      const value = result[key];
      if (
        typeof value !== 'string' ||
        value.trim() === '' ||
        placeholders(value) !== placeholders(template[key])
      ) {
        stillPending.push(key);
        continue;
      }
      translated[key] = value;
    }
    pending = stillPending;
  }

  if (pending.length > 0) {
    throw new Error(`${file}: ${pending.length} key(s) failed validation: ${pending.slice(0, 8)}`);
  }

  // Existing order first, then the new messages in app_en.arb order, so the
  // diff stays additive instead of rewriting the whole file.
  for (const key of englishKeys) {
    if (typeof pack[key] !== 'string') pack[key] = translated[key];
  }
  fs.writeFileSync(filePath, `${JSON.stringify(pack, null, 2)}\n`);

  const identical = missing.filter((key) => pack[key] === template[key]).length;
  return { code, added: missing.length, identical, skipped: false };
}

const limit = Number(process.env.PACK_LIMIT || 0);
const files = fs
  .readdirSync(packsDir)
  .filter((name) => name.endsWith('.arb'))
  .sort()
  .slice(0, limit > 0 ? limit : undefined);

const CONCURRENCY = 3;
const results = [];
let cursor = 0;

const failures = [];

async function worker() {
  while (cursor < files.length) {
    const file = files[cursor++];
    try {
      const outcome = await fillPack(file);
      results.push(outcome);
      console.log(
        outcome.skipped
          ? `${outcome.code}: already complete`
          : `${outcome.code}: +${outcome.added} (${outcome.identical} same as English)`,
      );
    } catch (error) {
      failures.push(file);
      console.error(`${file}: FAILED — ${error.message}`);
    }
  }
}

await Promise.all(Array.from({ length: CONCURRENCY }, worker));
console.log(`done: ${results.length} pack(s), ${failures.length} failed`);
if (failures.length > 0) {
  console.error(`re-run to retry: ${failures.join(', ')}`);
  process.exitCode = 1;
}
