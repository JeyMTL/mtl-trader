/**
 * Features that are built but not on sale yet.
 *
 * MT5 sync is on: the desktop EA runs in the trader's own terminal, and the
 * sync page is where the EA token lives — the same token the hard lock uses.
 * The hosted supervisor is optional and still costs money per account, so that
 * part is only offered when it is funded. Flipping this to `false` hides the
 * entry points again without a migration or a redeploy of anything else.
 *
 * Read by `src/app/dashboard/layout.tsx` (navigation) and
 * `src/app/dashboard/sync/page.tsx` (the page itself, so a bookmark or a typed
 * URL cannot land on a feature that is advertised nowhere).
 */
export const MT5_SYNC_ENABLED = true

/**
 * Hosted sync needs a supervisor to claim the connection. Off until that
 * supervisor runs on a funded host: right now it only runs on one desktop, so a
 * connection made from a phone would queue as `pending` and never be claimed.
 * The desktop EA path is independent and stays on. See
 * `docs/PLAY_LAUNCH_STATUS.md`.
 */
export const MT5_HOSTED_SYNC_ENABLED = false

/**
 * Charting, off while there is no licensed feed behind it.
 *
 * Every candle this app serves comes from a personal OANDA token, and a
 * personal token licenses those prices to one person — putting them on other
 * people's screens is redistribution. Until a feed with redistribution in its
 * contract is paid for, the chart is closed rather than quietly in breach: the
 * nav entries go, `/dashboard/chart` redirects, the exit-capture card and the
 * trade form's level pinning go with it, and the two vendor routes answer 503
 * instead of spending the key.
 *
 * The code is all still here, deliberately. `MARKET_CHARTS_ENABLED = true` and a
 * licensed feed is the whole switch back.
 */
export const MARKET_CHARTS_ENABLED = false

/**
 * The free market view that holds the chart's place meanwhile.
 *
 * TradingView serves the prices inside its own iframe under its own terms, so
 * nothing here is redistribution and no vendor key is spent. No seconds, no
 * overlays we compute, no drawings: see `src/lib/market-widget.ts`. It does not
 * depend on `MARKET_CHARTS_ENABLED`; with a licensed feed back on, the desk
 * chart returns at the same URL and this is no longer rendered.
 */
export const MARKET_WIDGET_ENABLED = true
