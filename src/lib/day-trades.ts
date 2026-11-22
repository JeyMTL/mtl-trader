import { getAdminClient } from './server-auth'
import type { TradeForDay } from './daily-stop'

/**
 * The trades that belong to one trading day, whatever clock they carry.
 *
 * The daily stop measures a trade by its own instant — close time, else open
 * time, else when the row was written. The first version of both routes filtered
 * the query on `close_time` alone, so a trade logged with only an open time
 * never reached the stop at all: a loss could be taken after the lock and the
 * day would not notice. Three narrow reads cover the three cases exactly, and
 * the pure function then decides as it always did.
 */
export async function loadDayTrades(
  userId: string,
  bounds: { start: Date; end: Date },
  columns: string
): Promise<TradeForDay[]> {
  const admin = getAdminClient()
  const start = bounds.start.toISOString()
  const end = bounds.end.toISOString()
  const base = () => admin.from('trades').select(columns).eq('user_id', userId)

  const [closed, opened, created] = await Promise.all([
    base().gte('close_time', start).lt('close_time', end),
    base().is('close_time', null).gte('open_time', start).lt('open_time', end),
    base()
      .is('close_time', null)
      .is('open_time', null)
      .gte('created_at', start)
      .lt('created_at', end),
  ])

  const error = closed.error ?? opened.error ?? created.error
  if (error) throw new Error(`Could not read today's trades: ${error.message}`)

  // A trade can only appear in one of the three reads, but dedupe anyway: the
  // state counts trades, and a row counted twice would spend the budget twice.
  const byId = new Map<string, TradeForDay>()
  for (const row of [
    ...(closed.data ?? []),
    ...(opened.data ?? []),
    ...(created.data ?? []),
  ]) {
    const trade = row as unknown as TradeForDay
    byId.set(trade.id ?? JSON.stringify(trade), trade)
  }
  return [...byId.values()]
}
