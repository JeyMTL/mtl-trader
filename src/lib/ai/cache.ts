/**
 * Stable hashing for review caching so an identical journal state does not
 * re-bill the model. Server-only (uses node:crypto).
 */

import { createHash } from 'node:crypto'

/** JSON stringify with recursively sorted object keys, so key order can't change the hash. */
export function stableStringify(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value) ?? 'null'
  if (Array.isArray(value)) return `[${value.map((item) => stableStringify(item)).join(',')}]`
  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([, item]) => item !== undefined)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([key, item]) => `${JSON.stringify(key)}:${stableStringify(item)}`)
  return `{${entries.join(',')}}`
}

export function hashPayload(value: unknown): string {
  return createHash('sha256').update(stableStringify(value)).digest('hex')
}
