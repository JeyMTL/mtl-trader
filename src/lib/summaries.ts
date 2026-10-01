/**
 * Pure helpers for the notification emails. Kept free of I/O so they can be
 * unit tested without a database or an email provider.
 */

export interface TradeLike {
  pnl: number | string
  close_time?: string | null
  open_time?: string | null
  created_at?: string | null
}

/** The timestamp a trade is attributed to, matching the quota trigger's ordering. */
export function tradeTime(trade: TradeLike): string | null {
  return trade.close_time || trade.open_time || trade.created_at || null
}

export interface Summary {
  trades: number
  wins: number
  losses: number
  pnl: number
  winRate: number
  best: number
  worst: number
}

export function summarizeTrades(trades: TradeLike[], since: Date, until: Date): Summary {
  const from = since.getTime()
  const to = until.getTime()

  let tradesCount = 0
  let wins = 0
  let losses = 0
  let pnl = 0
  let best = 0
  let worst = 0

  for (const trade of trades) {
    const time = tradeTime(trade)
    if (!time) continue
    const ms = new Date(time).getTime()
    if (!Number.isFinite(ms) || ms < from || ms >= to) continue

    const value = Number(trade.pnl) || 0
    tradesCount++
    pnl += value
    if (value > 0) wins++
    else if (value < 0) losses++
    best = Math.max(best, value)
    worst = Math.min(worst, value)
  }

  return {
    trades: tradesCount,
    wins,
    losses,
    pnl,
    winRate: tradesCount > 0 ? (wins / tradesCount) * 100 : 0,
    best,
    worst,
  }
}

export function formatMoney(value: number, currency = 'USD'): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency,
    minimumFractionDigits: 2,
  }).format(value)
}

function escapeHtml(value: string): string {
  const replacements: Record<string, string> = {
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  }
  return value.replace(/[&<>"']/g, (char) => replacements[char] || char)
}

export interface SummaryEmailOptions {
  name?: string | null
  title: string
  summary: Summary
  currency?: string
  appUrl?: string
}

export function renderSummaryEmail({
  name,
  title,
  summary,
  currency = 'USD',
  appUrl = 'https://mtl-trader.vercel.app',
}: SummaryEmailOptions): { subject: string; html: string } {
  const greeting = name ? `Hi ${escapeHtml(name)},` : 'Hi,'
  const sign = summary.pnl >= 0 ? '+' : ''
  const pnlColor = summary.pnl >= 0 ? '#1a7f37' : '#d1242f'
  const subject = `${title}: ${summary.trades} trade${summary.trades === 1 ? '' : 's'}, ${sign}${formatMoney(summary.pnl, currency)}`

  const row = (label: string, value: string, color = '#c9d1d9') =>
    `<tr><td style="padding:6px 0;color:#8b949e">${label}</td><td style="padding:6px 0;text-align:right;color:${color};font-weight:600">${value}</td></tr>`

  const html = `<!doctype html>
<html>
  <body style="margin:0;background:#0d1117;font-family:Arial,Helvetica,sans-serif;color:#c9d1d9">
    <div style="max-width:520px;margin:0 auto;padding:24px">
      <h1 style="font-size:18px;color:#f0f6fc;margin:0 0 4px">MTL Trader</h1>
      <p style="color:#8b949e;margin:0 0 20px">${escapeHtml(title)}</p>
      <div style="background:#161b22;border:1px solid #30363d;border-radius:12px;padding:20px">
        <p style="margin:0 0 12px">${greeting}</p>
        <table style="width:100%;border-collapse:collapse;font-size:14px">
          ${row('Trades', String(summary.trades))}
          ${row('Net P&L', `${sign}${formatMoney(summary.pnl, currency)}`, pnlColor)}
          ${row('Wins / Losses', `${summary.wins} / ${summary.losses}`)}
          ${row('Win rate', `${summary.winRate.toFixed(1)}%`)}
        </table>
      </div>
      <p style="margin:20px 0 0">
        <a href="${escapeHtml(appUrl)}/dashboard" style="color:#58a6ff">Open your journal</a>
      </p>
      <p style="color:#6e7681;font-size:12px;margin-top:24px">
        You are receiving this because email notifications are on in your MTL Trader settings.
      </p>
    </div>
  </body>
</html>`

  return { subject, html }
}

export interface JournalReminderOptions {
  name?: string | null
  appUrl?: string
}

/**
 * Working-day nudge to record trades. Sent when the user has opted in, it is a
 * weekday, and nothing has been journaled yet today.
 */
export function renderJournalReminderEmail({
  name,
  appUrl = 'https://mtl-trader.vercel.app',
}: JournalReminderOptions = {}): { subject: string; html: string } {
  const greeting = name ? `Hi ${escapeHtml(name)},` : 'Hi,'
  const subject = 'Reminder: journal today\u2019s trades'

  const html = `<!doctype html>
<html>
  <body style="margin:0;background:#0d1117;font-family:Arial,Helvetica,sans-serif;color:#c9d1d9">
    <div style="max-width:520px;margin:0 auto;padding:24px">
      <h1 style="font-size:18px;color:#f0f6fc;margin:0 0 4px">MTL Trader</h1>
      <p style="color:#8b949e;margin:0 0 20px">Keep today\u2019s journal current</p>
      <div style="background:#161b22;border:1px solid #30363d;border-radius:12px;padding:20px">
        <p style="margin:0 0 12px">${greeting}</p>
        <p style="margin:0 0 16px;color:#8b949e">You have not recorded a trade today. Add your notes while the session is still fresh so your journal stays accurate.</p>
        <a href="${escapeHtml(appUrl)}/dashboard/trades/new" style="display:inline-block;padding:10px 16px;background:#238636;color:#ffffff;border-radius:8px;text-decoration:none;font-weight:600">Journal a trade</a>
      </div>
      <p style="margin:20px 0 0">
        <a href="${escapeHtml(appUrl)}/dashboard" style="color:#58a6ff">Open your journal</a>
      </p>
      <p style="color:#6e7681;font-size:12px;margin-top:24px">
        You are receiving this because working-day journal reminders are on in your MTL Trader settings.
      </p>
    </div>
  </body>
</html>`

  return { subject, html }
}
