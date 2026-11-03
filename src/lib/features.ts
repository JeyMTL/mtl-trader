/**
 * Features that are built but not on sale yet.
 *
 * MT5 sync needs a hosted agent per customer — a running terminal and a machine
 * that costs money per account before it earns any. Until that is funded the
 * entry points disappear from the UI; the routes, the credentials store and the
 * supervisor stay exactly as they are, so flipping this back to `true` restores
 * the feature without a migration or a redeploy of anything else.
 *
 * Read by `src/app/dashboard/layout.tsx` (navigation) and
 * `src/app/dashboard/sync/page.tsx` (the page itself, so a bookmark or a typed
 * URL cannot land on a feature that is advertised nowhere).
 */
export const MT5_SYNC_ENABLED = false
