# MTL Ledger MT5 Expert Advisor

One EA does both jobs:

- **sync** — pushes every closed position to the journal;
- **hard lock** — while the daily stop is active in `hard` mode, deletes pending
  orders and closes positions opened after the stop.

The source is `MTLTraderSync.mq5`. `MTLTraderSync.ex5` is the compiled build from
MetaEditor (Windows, build 4755); recompile after any change.

## Install

1. In MT5, open **File → Open Data Folder → MQL5/Experts** and copy
   `MTLTraderSync.mq5` there.
2. Open it in MetaEditor and press **F7**. The Toolbox should say
   `0 errors, 0 warnings`.
3. In MT5, open **Tools → Options → Expert Advisors** and add your app URL to
   **Allow WebRequest for listed URL**. Without this every call fails with
   error 4014 and the EA prints the URL it needs.
4. Attach the EA to **one** chart (any symbol/timeframe is fine; it does not
   trade on ticks). Allow algo trading in the attach dialog.
5. On the app's **MT5 Sync** page, copy your **user id** and **sync token** into
   `InpUserId` and `InpSyncToken`.
6. Turn **AutoTrading** on. The EA needs it to close a fill while locked.

The same token authenticates the lock check. Rotating the token on the sync page
invalidates the old one immediately — update the EA inputs and reattach.

## Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `InpAppUrl` | `https://mtlledger.com` | Your deployment. Must match the WebRequest whitelist exactly. |
| `InpUserId` | — | From the MT5 Sync page. |
| `InpSyncToken` | — | From the MT5 Sync page; also used by the lock check. |
| `InpReconcileMinutes` | `30` | Full re-read of the lookback window. |
| `InpLookbackDays` | `30` | History re-read on start and on each reconcile. |
| `InpEnforceLock` | `true` | Turn the hard lock off without detaching the EA. |
| `InpDeletePending` | `true` | Delete resting orders while locked. |
| `InpCloseNewFills` | `true` | Close a position opened while locked. |
| `InpDeviationPoints` | `30` | Slippage allowed on that close. |
| `InpLockPollSeconds` | `30` | How often the EA asks the server (minimum 5). |
| `InpUnreachableGraceMinutes` | `5` | After this long offline, release the lock. |

## How sync behaves

- Trades are keyed by MT5 `position_id`, so a partial close cannot duplicate a
  row. The API upserts, so re-sending a window is harmless.
- Deal times are **broker-server time**; the EA converts them to UTC using the
  current server offset before sending. The journal's day boundary is then
  correct for the trader's timezone instead of being shifted by the broker's
  GMT+2/+3.
- The first run pushes the whole lookback window in batches of 200. Later runs
  push a close immediately from `OnTradeTransaction`, with a 30-second cursor
  sync as a safety net and a full reconcile every 30 minutes.
- A failed batch does not advance the cursor, so the next poll retries it.

## Hard lock limits (read this)

MQL5 cannot refuse a manual terminal click. The EA enforces what a client-side
program can:

- **pending orders** are deleted while locked, so a resting limit/stop cannot
  fill into a locked day;
- **a market order that fills** is closed immediately, which pays the spread and
  any slippage and is damage control, not prevention.

Only a broker-side block, or an execution EA that checks `MtlOrderAllowed()`
before sending, prevents the order outright. If the server cannot be reached the
EA keeps its last state for the grace period and then releases, so an outage
never traps the account. The journal refuses to override a hard lock; it clears
at the trader's local midnight.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `WebRequest failed (4014)` | URL not in the WebRequest whitelist. Add the exact `InpAppUrl`. |
| `Sync rejected (HTTP 401)` | Wrong or rotated token, or the user id does not match. |
| `Sync rejected (HTTP 403)` | Email unverified, or the plan has no sync feature. |
| `Sync rejected (HTTP 429)` | Rate limit (240 sync requests/hour/account). The cursor retries. |
| Nothing after attach | Check the Experts tab; the EA prints the first failure with its reason. |
| Lock never activates | A daily loss limit (or an entry cap) must be set and `lock_mode` must be `soft` or `hard` — both freeze the terminal, only `hard` also locks the journal. The EA must be attached with Algo Trading allowed, since MT5 refuses `order_send` without it. |

Run the EA on one chart only. Two instances push duplicates (the server absorbs
them) and both can close the same fill (harmless, but noisy).
