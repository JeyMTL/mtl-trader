/// Features that are built but not on sale yet.
///
/// MT5 sync on the phone is the hosted path: the app hands over the investor
/// password and a supervisor connects from our host. That supervisor is not
/// running yet, so the screen is hidden until it is — a connection made today
/// would queue as `pending` forever. Desktop customers use the EA in their own
/// terminal instead, on the website.
///
/// Mirrors `MT5_HOSTED_SYNC_ENABLED` in `src/lib/features.ts` so the app and the
/// web dashboard show the same thing on the same day.
///
/// On since the supervisor was verified end to end (login, year of history,
/// ingest). No host runs it 24/7 yet, so a connection made today can still sit on
/// "Connecting…" — the screen says so itself after two minutes and tells the
/// trader to start the host or disconnect, rather than hanging silently.
const bool kMt5SyncEnabled = true;

/// The candle chart, off while there is no licensed feed behind it.
///
/// Mirrors `MARKET_CHARTS_ENABLED` in `src/lib/features.ts`. The candles this
/// app drew came from the web deployment's `/api/market/candles`, which is fed
/// by a personal OANDA token — a token that licenses those prices to one person.
/// Serving them to anybody else is redistribution, so the route now answers 503
/// and every screen that read from it has to stop asking: the chart picker, the
/// "find the exit from the candles" resolver, and the level pinning that went
/// with them.
///
/// Nothing is deleted. `kMarketChartsEnabled = true` plus a licensed feed is the
/// whole way back, and the chart picker is untouched behind this flag.
const bool kMarketChartsEnabled = false;

/// The free market view that holds the chart's place meanwhile.
///
/// Mirrors `MARKET_WIDGET_ENABLED` in `src/lib/features.ts`. TradingView serves
/// the prices inside its own WebView under its own terms, so no quote of ours is
/// shown and no vendor key is spent. No seconds, no drawings, no journal data.
const bool kMarketWidgetEnabled = true;
