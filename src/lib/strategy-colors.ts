/**
 * A stable colour per strategy label.
 *
 * Ten hues that stay distinguishable on the app's dark surface. The colour is a
 * hash of the label, so the same strategy keeps its dot across sessions, forms
 * and the analytics matrix without anything being stored. Collisions are fine —
 * the dot is a visual anchor, not an identifier.
 */

const PALETTE = [
  '#22d3ee', // cyan
  '#a78bfa', // violet
  '#f472b6', // pink
  '#fbbf24', // amber
  '#34d399', // emerald
  '#60a5fa', // blue
  '#fb923c', // orange
  '#e879f9', // fuchsia
  '#4ade80', // green
  '#f87171', // red
] as const

/**
 * Deterministic colour for a name. The prime modulus keeps the arithmetic
 * identical to the Dart implementation in `mobile_flutter/lib/core/strategy_colors.dart`,
 * so a strategy has the same dot on the web and on the phone.
 */
export function strategyColor(name: string): string {
  let hash = 0
  for (let index = 0; index < name.length; index += 1) {
    hash = (hash * 31 + name.charCodeAt(index)) % 1_000_003
  }
  return PALETTE[hash % PALETTE.length]
}
