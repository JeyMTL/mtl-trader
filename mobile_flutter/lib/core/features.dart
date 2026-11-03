/// Features that are built but not on sale yet.
///
/// MT5 sync needs a hosted agent per customer — a terminal running on a machine
/// that costs money per account before it earns any. Until that is funded the
/// entry points disappear; the sync screen, the API client and the server routes
/// stay in place, so setting this back to `true` restores the feature with no
/// other change.
///
/// Mirrors `MT5_SYNC_ENABLED` in `src/lib/features.ts` so the app and the web
/// dashboard hide the same thing on the same day.
const bool kMt5SyncEnabled = false;
