/**
 * A broker's visual identity, generated instead of downloaded.
 *
 * Shipping 79 brokers' real logos is not something this repo can do honestly:
 * the marks are third-party trademarks, the files would have to be fetched and
 * licensed, and a stale logo reads as a broken product. What every broker can
 * have for free is a stable monogram — the initials of its name on a colour
 * derived from the name — so the picker is scannable, the same broker always
 * looks the same, and no asset, network request or licence is involved.
 *
 * The hue is a hash, not a sequence: adding a broker must not recolour the
 * others, and a name is all the input there is.
 */

/** Ten brand-safe colours; white initials stay legible on every one. */
const PALETTE = [
  '#3B82F6',
  '#6366F1',
  '#0EA5E9',
  '#14B8A6',
  '#22C55E',
  '#D5A44E',
  '#F97316',
  '#EF4444',
  '#A855F7',
  '#64748B',
] as const

/**
 * One or two letters for the mark: initials of the first two words, or the
 * first two characters of a single-word name. Punctuation is removed rather
 * than replaced with a space, so "Gerchik & Co" is GC and "XS.com" is XS
 * instead of XC from a domain suffix that is not a word.
 */
export function brokerInitials(name: string): string {
  const words = name
    .replace(/[^\p{L}\p{N}\s]/gu, '')
    .split(/\s+/)
    .filter(Boolean)

  if (words.length === 0) return '?'
  if (words.length === 1) return words[0].slice(0, 2).toUpperCase()
  return `${words[0][0]}${words[1][0]}`.toUpperCase()
}

/** A colour from [PALETTE], stable for a given broker name. */
export function brokerMarkColor(name: string): string {
  let hash = 0
  for (let index = 0; index < name.length; index += 1) {
    hash = (hash * 31 + name.charCodeAt(index)) >>> 0
  }
  return PALETTE[hash % PALETTE.length]
}
