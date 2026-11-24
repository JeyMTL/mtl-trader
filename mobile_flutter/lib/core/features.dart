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
