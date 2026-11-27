/**
 * Solo mode: this deployment serves market data to one account only.
 *
 * The candle feed is licensed to a person, not to a platform. Serving those
 * prices to anyone but that person is redistribution, whatever the interface
 * looks like, so a deployment that is "the app, but only for me" has to be able
 * to say so in one place rather than trusting every caller to remember.
 *
 * `SOLO_USER_ID` is that statement. When it is set, the two routes that touch a
 * market feed — `/api/market/candles` and `/api/analytics/excursion` — answer
 * only that user id and refuse everyone else with 403. Everything the journal
 * computes from the trader's own records (P&L, exit capture summaries already
 * stored, the calendar) is untouched, because that is their data, not a vendor's.
 *
 * Unset is the normal case: no gate, exactly the behaviour before this file
 * existed. That keeps the public deployment and every test unchanged.
 */

/** The one account this deployment may serve market data to, or null. */
export function soloUserId(): string | null {
  const raw = process.env.SOLO_USER_ID?.trim()
  return raw ? raw.toLowerCase() : null
}

export function isSoloMode(): boolean {
  return soloUserId() !== null
}

/** Whether this user is the account a solo deployment serves. */
export function isSoloOwner(userId: string | null | undefined): boolean {
  const solo = soloUserId()
  if (!solo || !userId) return false
  return userId.trim().toLowerCase() === solo
}

/**
 * Whether this user may read vendor market data here.
 *
 * Deliberately fails closed in solo mode: a missing or malformed id is a
 * refusal, not a pass. Getting this wrong in the other direction is the one
 * mistake that costs a licence.
 */
export function mayReadMarketData(userId: string | null | undefined): boolean {
  const solo = soloUserId()
  if (!solo) return true
  return isSoloOwner(userId)
}
