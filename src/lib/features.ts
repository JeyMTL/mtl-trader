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
