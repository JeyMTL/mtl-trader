/**
 * Creates the Google Play review account and fills it with a plausible journal.
 *
 * Google's reviewer signs in with the credentials on the "Sign in details" page,
 * so that account has to exist, be email-confirmed, and not look empty. This
 * script does all three against the live Supabase project:
 *
 *   node scripts/seed-review-account.mjs
 *
 * It is safe to re-run: the auth user is reused when it already exists, and the
 * journal is replaced rather than duplicated. Nothing is printed except the
 * account id and row counts — no keys, no password.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const EMAIL = 'jfx064+demo@gmail.com'
// Supabase requires a symbol, so the password keeps one `!` and nothing else:
// the fewer punctuation characters, the less the Play Console form has to argue
// about when its sign-in details are saved.
const PASSWORD = 'MtlTraderReview2026!'
const FULL_NAME = 'Demo Trader'

/** Reads a dotenv file without pulling in a dependency. */
function loadEnv(path) {
  const values = {}
  let text
  try {
    text = readFileSync(path, 'utf8')
  } catch {
    return values
  }
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#')) continue
    const eq = trimmed.indexOf('=')
    if (eq === -1) continue
    const key = trimmed.slice(0, eq).trim()
    let value = trimmed.slice(eq + 1).trim()
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1)
    }
    values[key] = value
  }
  return values
}

const env = { ...loadEnv('.env.local'), ...process.env }
const url = env.NEXT_PUBLIC_SUPABASE_URL
const serviceKey = env.SUPABASE_SERVICE_ROLE_KEY

if (!url || !serviceKey) {
  console.error(
    'Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY. Put them in .env.local.'
  )
  process.exit(1)
}

const admin = createClient(url, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
})

const now = Date.now()
const DAY = 24 * 60 * 60 * 1000

/**
 * Eighteen trades across three symbols and two strategies, spread over the last
 * six weeks. Wins and losses are mixed on purpose: a journal where every trade
 * wins reads as fake, and the analytics screens have nothing to say about it.
 */
const TRADES = [
  { symbol: 'EURUSD', type: 'buy', entry: 1.0842, exit: 1.0897, lots: 0.5, pnl: 275, strategy: 'London breakout', daysAgo: 40, hour: 8, hours: 4, note: 'Broke the Asian range on the 15m and held. Trailed the stop under the last swing.', tags: ['london', 'breakout'] },
  { symbol: 'XAUUSD', type: 'sell', entry: 2418.5, exit: 2404.2, lots: 0.2, pnl: 286, strategy: 'Supply rejection', daysAgo: 39, hour: 14, hours: 3, note: 'Rejected the 4H supply zone with a bearish engulfing. Took most off at the round number.', tags: ['supply', 'reversal'] },
  { symbol: 'US30', type: 'buy', entry: 39120, exit: 39045, lots: 0.3, pnl: -225, strategy: 'New York open', daysAgo: 37, hour: 15, hours: 1, note: 'Bought the opening drive too early. No confirmation, stop was hit within the hour.', tags: ['newyork', 'mistake'] },
  { symbol: 'EURUSD', type: 'sell', entry: 1.0918, exit: 1.0871, lots: 0.4, pnl: 188, strategy: 'London breakout', daysAgo: 35, hour: 9, hours: 5, note: 'Failed retest of the previous day high. Entered on the 5m close below.', tags: ['london', 'retest'] },
  { symbol: 'XAUUSD', type: 'buy', entry: 2397.8, exit: 2391.4, lots: 0.2, pnl: -128, strategy: 'Trend pullback', daysAgo: 34, hour: 11, hours: 2, note: 'Pullback never held the 20 EMA. Should have waited for the hourly close.', tags: ['pullback'] },
  { symbol: 'US30', type: 'sell', entry: 39280, exit: 39110, lots: 0.3, pnl: 510, strategy: 'New York open', daysAgo: 32, hour: 16, hours: 2, note: 'Clean lower high after the 10am reversal. Best read of the week.', tags: ['newyork', 'reversal'] },
  { symbol: 'EURUSD', type: 'buy', entry: 1.0877, exit: 1.0864, lots: 0.5, pnl: -65, strategy: 'Range fade', daysAgo: 30, hour: 13, hours: 1, note: 'Faded the range high without a rejection candle. Small loss, correct exit.', tags: ['range'] },
  { symbol: 'XAUUSD', type: 'sell', entry: 2429.0, exit: 2408.6, lots: 0.3, pnl: 612, strategy: 'Supply rejection', daysAgo: 28, hour: 10, hours: 6, note: 'Same zone as the earlier short, this time with a daily bearish close behind it.', tags: ['supply', 'aplus'] },
  { symbol: 'US30', type: 'buy', entry: 38940, exit: 39005, lots: 0.2, pnl: 130, strategy: 'Opening range', daysAgo: 26, hour: 15, hours: 2, note: 'Waited for the first 30 minutes to print, then bought the break and held.', tags: ['openingrange'] },
  { symbol: 'EURUSD', type: 'sell', entry: 1.0934, exit: 1.0951, lots: 0.4, pnl: -68, strategy: 'London breakout', daysAgo: 24, hour: 8, hours: 2, note: 'False break, stopped out above the range. News at 9:00 was the culprit.', tags: ['london', 'news'] },
  { symbol: 'XAUUSD', type: 'buy', entry: 2402.4, exit: 2417.9, lots: 0.2, pnl: 310, strategy: 'Trend pullback', daysAgo: 22, hour: 12, hours: 4, note: 'Held the 20 EMA on the hourly and pushed into the prior high.', tags: ['pullback', 'trend'] },
  { symbol: 'US30', type: 'sell', entry: 39410, exit: 39386, lots: 0.2, pnl: 48, strategy: 'Range fade', daysAgo: 20, hour: 18, hours: 1, note: 'Scalp into the close. Small size, took what the range gave.', tags: ['range', 'scalp'] },
  { symbol: 'EURUSD', type: 'buy', entry: 1.0801, exit: 1.0846, lots: 0.5, pnl: 225, strategy: 'London breakout', daysAgo: 18, hour: 9, hours: 5, note: 'Textbook setup: Asian range, London sweep, entry on the reclaim.', tags: ['london', 'aplus'] },
  { symbol: 'XAUUSD', type: 'sell', entry: 2436.2, exit: 2445.8, lots: 0.2, pnl: -192, strategy: 'Supply rejection', daysAgo: 15, hour: 13, hours: 3, note: 'Shorted into a strong dollar session. Zone gave way and I held too long.', tags: ['supply', 'mistake'] },
  { symbol: 'US30', type: 'buy', entry: 39080, exit: 39240, lots: 0.3, pnl: 480, strategy: 'Opening range', daysAgo: 13, hour: 15, hours: 4, note: 'Opening range break with the trend from the prior day. Held to the measured move.', tags: ['openingrange', 'trend'] },
  { symbol: 'EURUSD', type: 'sell', entry: 1.0892, exit: 1.0858, lots: 0.3, pnl: 102, strategy: 'Retest', daysAgo: 9, hour: 10, hours: 3, note: 'Lower high on the 1H after the drop. Partial at the round number.', tags: ['retest'] },
  { symbol: 'XAUUSD', type: 'buy', entry: 2411.0, exit: 2404.6, lots: 0.2, pnl: -128, strategy: 'Trend pullback', daysAgo: 6, hour: 14, hours: 2, note: 'Bought a pullback in a downtrend. Direction was wrong before the entry was.', tags: ['pullback', 'mistake'] },
  { symbol: 'US30', type: 'buy', entry: 39320, exit: 39498, lots: 0.3, pnl: 534, strategy: 'New York open', daysAgo: 3, hour: 15, hours: 5, note: 'Opening drive held above the premarket high all session. Best trade of the month.', tags: ['newyork', 'aplus'] },
]

async function ensureUser() {
  const created = await admin.auth.admin.createUser({
    email: EMAIL,
    password: PASSWORD,
    email_confirm: true,
    user_metadata: { full_name: FULL_NAME },
  })
  if (!created.error && created.data.user) return created.data.user.id

  // Already registered: reuse it and make sure the password and confirmation
  // match what the Play Console says, so the reviewer's login cannot fail.
  const listed = await admin.auth.admin.listUsers({ page: 1, perPage: 200 })
  const found = (listed.data?.users ?? []).find(
    (user) => (user.email ?? '').toLowerCase() === EMAIL
  )
  if (!found) {
    console.error(`Could not create or find ${EMAIL}: ${created.error?.message}`)
    process.exit(1)
  }

  const updated = await admin.auth.admin.updateUserById(found.id, {
    password: PASSWORD,
    email_confirm: true,
  })
  if (updated.error) {
    console.error(`Could not reset the review password: ${updated.error.message}`)
    process.exit(1)
  }
  return found.id
}

async function main() {
  const userId = await ensureUser()

  // Trial instead of a paid tier: it unlocks everything (the trial is treated as
  // Pro) without inventing a payment record that would show up in revenue.
  const { error: profileError } = await admin.from('users').upsert(
    {
      id: userId,
      email: EMAIL,
      full_name: FULL_NAME,
      subscription_tier: 'free',
      subscription_status: 'trial',
      // A year, so the account cannot lapse mid-review.
      trial_ends_at: new Date(now + 365 * DAY).toISOString(),
      max_trades: -1,
      trades_remaining: -1,
      current_period_start: null,
      current_period_end: null,
      cancel_at_period_end: false,
      timezone: 'Africa/Nairobi',
      currency: 'USD',
    },
    { onConflict: 'id' }
  )
  if (profileError) {
    console.error(`Could not write the profile: ${profileError.message}`)
    process.exit(1)
  }

  const { error: clearError } = await admin.from('trades').delete().eq('user_id', userId)
  if (clearError) {
    console.error(`Could not clear the old journal: ${clearError.message}`)
    process.exit(1)
  }

  const rows = TRADES.map((trade, index) => {
    const open = new Date(now - trade.daysAgo * DAY)
    open.setUTCHours(trade.hour, 0, 0, 0)
    const close = new Date(open.getTime() + trade.hours * 60 * 60 * 1000)
    const dir = trade.type === 'buy' ? 1 : -1
    return {
      user_id: userId,
      ticket: 900000 + index,
      symbol: trade.symbol,
      type: trade.type,
      entry_price: trade.entry,
      exit_price: trade.exit,
      stop_loss: Number((trade.entry - dir * Math.abs(trade.exit - trade.entry) * 0.6).toFixed(4)),
      take_profit: Number((trade.entry + dir * Math.abs(trade.exit - trade.entry) * 1.8).toFixed(4)),
      lot_size: trade.lots,
      pnl: trade.pnl,
      commission: -Math.round(trade.lots * 7),
      swap: 0,
      open_time: open.toISOString(),
      close_time: close.toISOString(),
      timeframe: '15m',
      strategy: trade.strategy,
      notes: trade.note,
      tags: trade.tags,
    }
  })

  const { error: tradeError } = await admin.from('trades').insert(rows)
  if (tradeError) {
    console.error(`Could not seed the journal: ${tradeError.message}`)
    process.exit(1)
  }

  await admin.from('deposits').delete().eq('user_id', userId)
  const { error: depositError } = await admin.from('deposits').insert({
    user_id: userId,
    amount: 5000,
    type: 'deposit',
    description: 'Opening balance',
  })
  if (depositError) {
    console.error(`Could not seed the deposit: ${depositError.message}`)
    process.exit(1)
  }

  const pnl = rows.reduce((total, row) => total + row.pnl, 0)
  console.log('Review account ready')
  console.log(`  email    ${EMAIL}`)
  console.log(`  user id  ${userId}`)
  console.log(`  trades   ${rows.length} (net ${pnl >= 0 ? '+' : ''}${pnl})`)
  console.log(`  plan     trial until ${new Date(now + 365 * DAY).toISOString().slice(0, 10)}`)
}

main().catch((error) => {
  console.error('Seeding failed:', error?.message ?? error)
  process.exit(1)
})
