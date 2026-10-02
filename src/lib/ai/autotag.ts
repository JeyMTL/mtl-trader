/**
 * Rule-based auto-tagging from a trade note. Deterministic, free, and instant —
 * a strong default that an LLM pass can refine later.
 */

export interface TagRule {
  tag: string
  patterns: RegExp[]
}

export const AUTO_TAG_RULES: TagRule[] = [
  { tag: 'breakout', patterns: [/\bbreak ?out\b/i, /\bbreakout\b/i] },
  { tag: 'pullback', patterns: [/\bpull ?back\b/i, /\bretrace/i, /\brejection\b/i] },
  { tag: 'reversal', patterns: [/\breversal\b/i, /\breverse\b/i, /\bturn(ed)? around\b/i] },
  { tag: 'range', patterns: [/\brange\b/i, /\bconsolidat/i, /\bchop(ppy)?\b/i] },
  { tag: 'trend', patterns: [/\btrend\b/i, /\bmomentum\b/i, /\bcontinuation\b/i] },
  { tag: 'scalp', patterns: [/\bscalp/i, /\bquick\b/i, /\bminute chart\b/i] },
  { tag: 'news', patterns: [/\bnews\b/i, /\bnfp\b/i, /\bcpi\b/i, /\bfomc\b/i, /\bearning/i] },
  { tag: 'revenge-trade', patterns: [/\brevenge\b/i, /\btilt/i, /\bgot it back\b/i] },
  { tag: 'fomo', patterns: [/\bfomo\b/i, /\bchased?\b/i, /\blate entry\b/i, /\bmissed the move\b/i] },
  { tag: 'overtrading', patterns: [/\bovertrad/i, /\btoo many\b/i, /\bforced\b/i] },
  { tag: 'patient', patterns: [/\bpatient/i, /\bwaited\b/i, /\bno rush\b/i] },
  { tag: 'plan-followed', patterns: [/\bper plan\b/i, /\bfollowed the plan\b/i, /\baccording to plan\b/i] },
  { tag: 'plan-broken', patterns: [/\bbroke (my|the) rules?\b/i, /\bnot (my|the) plan\b/i, /\bignored\b/i] },
  { tag: 'early-exit', patterns: [/\bearly exit\b/i, /\bcut (it )?early\b/i, /\bexited too soon\b/i] },
  { tag: 'late-exit', patterns: [/\bheld too long\b/i, /\bheld too long\b/i, /\bgave it back\b/i, /\blate exit\b/i] },
  { tag: 'london-session', patterns: [/\blondon\b/i] },
  { tag: 'new-york-session', patterns: [/\bnew ?york\b/i, /\bny session\b/i] },
  { tag: 'asian-session', patterns: [/\basian\b/i, /\btokyo\b/i] },
  { tag: 'stop-hit', patterns: [/\bstop ?ped out\b/i, /\bhit (my )?stop\b/i, /\bsl hit\b/i] },
  { tag: 'target-hit', patterns: [/\bhit (my )?(target|tp)\b/i, /\btp hit\b/i, /\btook profit\b/i] },
  { tag: 'discipline', patterns: [/\bdisciplin/i, /\bstayed calm\b/i, /\bno emotion\b/i] },
]

/** Return the tags whose rules match the note, in rule order. */
export function suggestTags(note: string | null | undefined, maxTags = 5): string[] {
  if (!note || !note.trim()) return []
  const tags: string[] = []
  for (const rule of AUTO_TAG_RULES) {
    if (tags.length >= maxTags) break
    if (rule.patterns.some((pattern) => pattern.test(note))) tags.push(rule.tag)
  }
  return tags
}

/** Merge suggested tags with existing ones, de-duplicated and capped. */
export function mergeTags(existing: string[] | null | undefined, suggested: string[], max = 8): string[] {
  const out: string[] = []
  for (const tag of [...(existing || []), ...suggested]) {
    const clean = tag.trim().toLowerCase()
    if (clean && !out.includes(clean)) out.push(clean)
    if (out.length >= max) break
  }
  return out
}
