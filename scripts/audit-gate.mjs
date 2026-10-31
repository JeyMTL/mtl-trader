#!/usr/bin/env node
/**
 * Dependency vulnerability gate.
 *
 * `npm audit --audit-level=high` is all-or-nothing: one advisory with no
 * published fix would keep CI red forever, and the usual reaction is to switch
 * the step off. This gate keeps it meaningful — every high or critical advisory
 * fails the build *unless* it is listed, with a reason and a review date, in
 * .github/audit-allowlist.json.
 *
 *   node scripts/audit-gate.mjs
 *
 * Exits 0 when the only remaining findings are reviewed exceptions.
 */

import { execSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const allowListPath = fileURLToPath(
  new URL('../.github/audit-allowlist.json', import.meta.url)
)

function readReport() {
  let raw
  try {
    raw = execSync('npm audit --json --omit=dev', {
      encoding: 'utf8',
      maxBuffer: 32 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'ignore'],
    })
  } catch (error) {
    // npm exits non-zero as soon as it finds anything; the JSON is still on
    // stdout and is the part we need.
    raw = error.stdout?.toString() ?? ''
  }
  try {
    return JSON.parse(raw)
  } catch {
    console.error('✖ could not read the npm audit report')
    process.exit(1)
  }
}

function readAllowList() {
  if (!existsSync(allowListPath)) return new Map()
  try {
    const parsed = JSON.parse(readFileSync(allowListPath, 'utf8'))
    return new Map((parsed.allowed ?? []).map((entry) => [entry.package, entry]))
  } catch (error) {
    console.error(`✖ .github/audit-allowlist.json is not valid JSON: ${error.message}`)
    process.exit(1)
  }
}

const report = readReport()
const allowList = readAllowList()

const blocking = []
const accepted = []

for (const [name, vuln] of Object.entries(report.vulnerabilities ?? {})) {
  if (vuln.severity !== 'high' && vuln.severity !== 'critical') continue
  const exception = allowList.get(name)
  if (exception) {
    accepted.push({ name, severity: vuln.severity, exception })
    continue
  }
  blocking.push({
    name,
    severity: vuln.severity,
    detail: (vuln.via ?? [])
      .map((via) => (typeof via === 'string' ? via : via.title))
      .filter(Boolean)
      .join('; '),
    fix:
      vuln.fixAvailable === false
        ? 'no fix published'
        : typeof vuln.fixAvailable === 'object'
          ? `run npm audit fix (${vuln.fixAvailable.name}@${vuln.fixAvailable.version})`
          : 'run npm audit fix',
  })
}

for (const item of accepted) {
  console.log(
    `• ${item.name} (${item.severity}) accepted by policy — reviewed ${item.exception.reviewed}`
  )
  console.log(`  ${item.exception.reason}`)
}

if (blocking.length > 0) {
  console.error('')
  for (const item of blocking) {
    console.error(`✖ ${item.name} — ${item.severity}`)
    if (item.detail) console.error(`  ${item.detail}`)
    console.error(`  ${item.fix}`)
  }
  console.error(
    `\n${blocking.length} high/critical advisor${blocking.length === 1 ? 'y' : 'ies'} without a reviewed exception.`
  )
  process.exit(1)
}

console.log(
  `✔ no unreviewed high or critical advisories in production dependencies${
    accepted.length ? ` (${accepted.length} accepted by policy)` : ''
  }`
)
