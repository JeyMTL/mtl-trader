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
const bool kMt5SyncEnabled = false;
