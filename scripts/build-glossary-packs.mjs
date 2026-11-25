#!/usr/bin/env node
// Produces a usable web pack for every locale from the reviewed mobile
// translations. This fills the core trading vocabulary immediately; the
// Gemini pass in translate-web.mjs adds the remaining web-specific copy.
//
//   node scripts/build-glossary-packs.mjs
import fs from 'node:fs'
import path from 'node:path'

const root = path.resolve(import.meta.dirname, '..')
const enFile = path.join(root, 'public', 'locales', 'web', 'en.json')
const languagesFile = path.join(root, 'src', 'lib', 'i18n', 'languages.json')
const mobileDir = path.join(root, 'mobile_flutter', 'lib', 'l10n')
const outDir = path.join(root, 'public', 'locales', 'web')

const english = JSON.parse(fs.readFileSync(enFile, 'utf8'))
const keys = Object.keys(english)
const mobileEn = JSON.parse(fs.readFileSync(path.join(mobileDir, 'app_en.arb'), 'utf8'))
const languages = JSON.parse(fs.readFileSync(languagesFile, 'utf8')).filter(
  (language) => language.code !== 'en'
)

const placeholders = (text) =>
  [...new Set([...text.matchAll(/\{(\w+)\}/g)].map((match) => match[1]))].sort().join(',')

const manifest = []

for (const language of languages) {
  const packFile = path.join(mobileDir, 'packs', `app_${language.code}.arb`)
  const outFile = path.join(outDir, `${language.code}.json`)
  const pack = fs.existsSync(packFile)
    ? JSON.parse(fs.readFileSync(packFile, 'utf8'))
    : {}
  const existing = fs.existsSync(outFile) ? JSON.parse(fs.readFileSync(outFile, 'utf8')) : {}

  let added = 0
  for (const [key, source] of Object.entries(mobileEn)) {
    if (typeof source !== 'string' || !source.trim()) continue
    const target = pack[key]
    if (typeof target !== 'string' || !target.trim() || target === source) continue
    const normalized = source.replace(/\s+/g, ' ').trim()
    if (!english[normalized]) continue
    if (placeholders(source) !== placeholders(target)) continue
    if (existing[normalized] !== target) {
      existing[normalized] = target
      added++
    }
  }

  fs.writeFileSync(outFile, `${JSON.stringify(existing, null, 2)}\n`)
  const translated = keys.filter((key) => typeof existing[key] === 'string' && existing[key].trim()).length
  manifest.push({
    code: language.code,
    translated,
    total: keys.length,
    percent: Math.round((translated / keys.length) * 100),
    complete: translated === keys.length,
  })
  console.log(`${language.code}: ${translated}/${keys.length} (${Math.round((translated / keys.length) * 100)}%) +${added}`)
}

fs.writeFileSync(
  path.join(outDir, 'manifest.json'),
  `${JSON.stringify({ total: keys.length, packs: manifest }, null, 2)}\n`
)
console.log(`wrote ${manifest.length} pack(s)`)
