/// Features that are built but not on sale yet.
///
/// MT5 sync is on: the desktop EA runs in the trader's own terminal, and the
/// sync screen is where the EA token lives — the same token the hard lock uses.
/// The hosted supervisor is optional and still costs money per account, so that
/// part is only offered when it is funded. Setting this back to `false` hides the
/// entry points with no other change.
///
/// Mirrors `MT5_SYNC_ENABLED` in `src/lib/features.ts` so the app and the web
/// dashboard show the same thing on the same day.
const bool kMt5SyncEnabled = true;
