# Operations

What runs by itself, what wakes you up, and what to do when it does.

## Health

`GET /api/health` is the single source of truth for "is this deployment wired
up". It answers 200 only when the Supabase URL and anon key are present and the
database answers a query; otherwise 503. It reports whether each variable is
*present*, never any part of its value, so the endpoint is safe to leave public.

```bash
node scripts/check-deploy.mjs https://your-domain
```

That script is the same probe used by the deploy gate and the uptime monitor.

### Database functions

The endpoint also reports `migrations`: every RPC the app calls, probed once, with
`missing` naming both the function and the migration file that creates it.

```json
"migrations": {
  "status": "pending",
  "checked": 22,
  "missing": [{ "rpc": "session_stats", "migration": "20261105_session_stats.sql",
                "usedBy": "session strip, dashboard and analytics sessions" }]
}
```

A half-migrated database is the failure that looks like a code bug — the pages
render and one panel is silently empty — so this is what turns it into a
sentence. The probe sends the argument names the app actually uses, so a dropped
or renamed parameter reads as missing too, which is correct: the caller breaks
either way.

Every probe is sent as the anonymous role, which holds no `EXECUTE` on these
functions; "permission denied" is the *healthy* answer. The arguments are
harmless by design (a nil uuid, an unknown plan, a one-second window) so that if
a future migration grants one of them to `anon`, the probe still cannot change
anything.

`migrations.status` is reported but is **not** part of `status`, and it does not
fail the deploy gate. A pending migration is a known state with a named fix, and
an alert that fires every fifteen minutes until someone pastes SQL is an alert
people learn to ignore.

### Sync supervisor

`sync` reports the hosted MT5 connection set as aggregates, because the
supervisor runs on our own Windows host rather than in this deploy:

```json
"sync": { "verdict": "stalled", "connections": 12, "pending": 1,
          "connecting": 0, "connected": 11, "stalled": 1,
          "lastSyncAt": "2026-11-02T09:14:03.000Z", "oldestPendingMinutes": 47 }
```

`verdict: "stalled"` means a queued connection has gone unclaimed for more than
ten minutes — several missed cycles — which is what a supervisor that is not
running looks like from outside. Like `migrations`, it is reported but does not
change `status`: the app is fine and the missing piece is infrastructure.
Aggregates only, never a broker, server or account number, because the endpoint
is public.

## Uptime monitoring

`.github/workflows/uptime.yml` runs every 15 minutes:

1. probes `/api/health` up to three times, 30 seconds apart, so one cold start
   does not page anyone;
2. files **one** GitHub issue titled *Production health check is failing* on a
   real outage, and comments on it instead of opening duplicates;
3. closes that issue and notes the recovery when the probe goes green again.

**Setup:** none. The probe defaults to `https://mtl-trader.vercel.app`, the same
domain the app itself falls back to (`src/app/layout.tsx`,
`mobile_flutter/lib/core/config.dart`), so the monitor is green from the first
scheduled run. If the app moves to a custom domain, add a repository *variable*
named `PRODUCTION_URL` under Settings → Secrets and variables → Actions →
**Variables** (not Secrets — it is a public URL); it takes precedence over the
default.

There is no third-party monitor, deliberately: the extra account would watch the
same endpoint this workflow already polls, and the token is one you already
have.

### When the alert fires

1. Open the linked run; read which line failed (status, database, keys).
2. Run `node scripts/check-deploy.mjs <url>` locally to confirm.
3. `status: degraded` with `database: unreachable` → Supabase project paused,
   paused billing, or a bad URL. Check the Supabase dashboard first.
4. `config.*: false` → an environment variable is missing in Vercel. This has
   broken production before; the fix is redeploying with the variable set, not
   editing the app.
5. Wrong domain in `PRODUCTION_URL` → update the variable.

## Deploy gate

`.github/workflows/deploy-gate.yml` smokes the freshly deployed environment on
every successful Vercel deployment. A deployment that builds but cannot reach
its database therefore fails visibly instead of quietly serving errors.

## Crons

`vercel.json` schedules two jobs: billing reconciliation (03:00) and
notification delivery (07:00). A cron that stops running does **not** fail the
uptime probe — it only proves the app is reachable. The reconciliation cron is
idempotent, so the safe response to a suspected missed run is triggering it
manually from the Vercel dashboard and checking the logs for the period.

## Dependency security

* `.github/workflows/security.yml` runs on every push, every PR and weekly:
  secret scanning over the **full** git history, a check that no real `.env`
  file is tracked, the dependency gate below, and a Flutter outdated report.
* `scripts/audit-gate.mjs` (`npm run check:audit`) fails on any high or critical
  advisory in production dependencies **unless** the package is listed in
  `.github/audit-allowlist.json` with a reason and a review date.

The allowlist exists because one unfixable advisory would otherwise make the job
permanently red, and the usual response to that is to disable the check. Adding
an entry is a decision with a name and a date on it, reviewed by a person;
anything untriaged still fails the build.

Currently allowlisted: `xlsx` (see the file for why and what to migrate to).

* Dependabot (`.github/dependabot.yml`) opens grouped weekly PRs for npm and
  pub, and monthly for Actions. Patch/minor bumps arrive as one PR so review
  stays focused on majors.

## Accessibility rules

These are the invariants the UI is expected to keep:

* A label someone has to read is never smaller than `kMinLabelSize` (11 px,
  `lib/ui/theme.dart`). Chart axis ticks are the one exception.
* Profit and loss never rely on colour alone: every amount carries a sign, and
  the main screens add a ▲/▼ glyph (`PnlText` in `lib/ui/a11y.dart`) plus a
  spoken label such as "Profit of $1,204.10".
* Painted charts are wrapped in `ChartSemantics` so a screen reader gets one
  sentence instead of unlabelled pixels.
* Icon-only buttons have a tooltip, which doubles as the accessibility label.
* A repeated animation (the brand mark pulse) stops when the device asks for
  reduced motion.

These are enforced, not just written down. `mobile_flutter/test/a11y_test.dart`
renders the shared widgets and the login screen at a **2x text scale** and fails
on any overflow, walks every rendered `Text` to prove nothing is drawn below
`kMinLabelSize`, and checks that a loss is announced as "Loss of …" rather than
as a bare number. That suite is what caught the overflowing Sign in / Create
account row on login.

## Languages

English and French ship today. Adding a third:

1. copy `mobile_flutter/lib/l10n/app_en.arb` to `app_XX.arb` and translate the
   values (never the keys);
2. add `Locale('xx')` to `LocaleController.supported` in
   `mobile_flutter/lib/core/locale.dart`;
3. add its native name to `LocaleController.nativeNames`;
4. run `flutter gen-l10n` and `flutter test` — `test/l10n_test.dart` fails if a
   language resolves no strings.

Strings live in code as `AppLocalizations.of(context).key`. Translated today:
login, the five-tab shell, Desk, Journal, Analytics and the language picker
itself. Still English: Calendar, the Account page body, Plans and billing, the
trade form and the chart — they keep inline literals until they are migrated the
same way.

The picker lives under Account → Language, and
`mobile_flutter/test/language_picker_test.dart` covers listing the languages,
switching to French, and switching back to the device language.

## Hosted broker sync

Most customers only have a phone, and MT5 mobile cannot run an Expert Advisor,
so they connect with the account's **investor** (read-only) password instead. A
supervisor on our own Windows hosts logs in and streams closed trades to
`/api/sync`, exactly as a desktop agent would.

* **Table:** `broker_connections`
  (`supabase/migrations/20261102_broker_connections.sql`). The credential is
  sealed with AES-256-GCM in the application, and column grants keep
  `credential_cipher` out of every signed-in read, so the browser can see the
  connection but never the password.
* **`SYNC_CREDENTIAL_KEY`** (32 bytes, base64) seals credentials. Without it
  `POST /api/broker/connection` answers 503 rather than storing a password in
  the clear. Rotating the key makes existing connections undecryptable, so
  customers must reconnect — rotate deliberately.
* **Lifecycle:** `pending` → `connecting` → `connected`, or `failed` with
  `last_error`. `DELETE /api/broker/connection` wipes the credential and sets
  `disconnected`; the supervisor must tear that session down.
* **The supervisor is infrastructure, not part of the Next.js deploy.** It claims
  rows where `status = 'pending'` ordered by `created_at`, holds one MT5 terminal
  per connection, and posts to `/api/sync` with the customer's `agent_token`. A
  crashed session must be retried, and a session whose credential stops working
  must be marked `failed` with a message the customer can act on.
* **Never accept the master password.** The investor password cannot trade, which
  is what makes holding a credential defensible. The customer's revoke buttons
  are "Disconnect" in the app and changing the investor password in MT5.
* **Running it:** `supervisor/mt5_supervisor.py` on a Windows host with MT5
  installed. It needs `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
  `SYNC_CREDENTIAL_KEY` (the same value as the app) and `SYNC_SUPERVISOR_TOKEN`
  (which `/api/sync` accepts in place of a customer's agent token). It logs in
  sequentially — one terminal, one account at a time — so 40 connections cost a
  few seconds each per cycle rather than 40 terminals. `--once` runs a single
  pass, which is what a scheduled task should call.
* **Sync identity:** trades are keyed on MT5's `position_id`, not a deal ticket.
  Writes are idempotent upserts, and `sync_suppressions` (filled by a trigger on
  `trades` deletes) stops a deleted trade coming back on the next poll. Retiring
  any of those three brings back either doubled P&L or zombie trades.
* **Desktop traders** can still run `public/mt5_agent.py` (position-keyed,
  resumable, UTC timestamps) or the MQL5 expert advisor in `mt5/`, which pushes
  on `OnTradeTransaction` instead of polling.

## Vercel projects

Two projects were building this repo on every push, which doubled build minutes
and deploy-gate runs:

| Project | Role |
| --- | --- |
| `mtl-trader` | Owns `mtl-trader.vercel.app`, the production domain. Keep its GitHub integration connected. |
| `mtl-trader-bumx` | Older project (first deployment August 2026). Its deployments are only reachable at team-scoped URLs, so nothing user-facing points at it. Git was disconnected; the project is kept for its history. |

Exactly one project should have the GitHub integration enabled. After any project
change, prove it with a push rather than assuming:

```bash
git commit --allow-empty -m "check which project deploys"   # or any real change
git push
curl -s https://mtl-trader.vercel.app/api/health            # commit must advance
```

If `commit` stops advancing after a push, the Git integration is on a project
that does not own the domain. Reconnect it (Project → Settings → Git) instead of
debugging the app — and note that `Redeploy` in the dashboard is *not* a valid
test of this, because it rebuilds the same SHA without changing `commit`.

## Paddle go-live

Sandbox and live are separate Paddle accounts with separate catalogues, keys and
webhook destinations, so **nothing carries over**. The switch is six variables
and one redeploy; the danger is a half-swap, because it looks like success — the
button renders, the checkout opens, and the payment either 401s or lands with no
plan attached.

### 1. In Paddle, in **live** mode

1. **Paddle → Switch to Live**, complete the business details, and get the
   website approved for `mtl-trader.vercel.app`. This is the long pole; start it
   first.
2. Create **four** prices in the live catalogue, USD, quantity 1, no trial:
   `12.00` monthly, `120.00` yearly (Basic), `29.00` monthly, `290.00` yearly
   (Pro). Note each `pri_…` id.
3. **Developer tools → Authentication** → create a live **API key** (`pdl_live_…`).
4. **Events → Notifications** → **New destination**, pointing at
   `https://mtl-trader.vercel.app/api/webhooks/paddle`, subscribed to
   `transaction.completed`, `subscription.canceled` and `adjustment.created`,
   and copy its **secret key** (`pdl_ntfset_…`). It is unique per destination —
   the sandbox secret will not verify live events.

   The secret key has the shape `pdl_ntfset_<26 chars>_<32 chars>`. The
   destination's **ID** is `ntfset_<26 chars>` — the same ULID without the
   `pdl_` prefix and the trailing `_…` half. Copying the ID from the URL or the
   list row looks plausible (right prefix family, right length) and makes every
   delivery fail signature verification with a 401, so a customer pays and never
   gets the plan. If the value has no `pdl_` prefix or no `_` in it, it is the
   ID, not the secret.

   Set the destination's usage/`traffic_source` to include **simulations**
   (`all`, not `platform`) if you want to prove the secret without a sale —
   Developer tools → Simulations delivers a real, signed event to the URL, and
   because the signature is per destination rather than per event, any harmless
   event (`product.updated`) proves it. Expect **200**, not 401.
5. **Checkout settings** → set the default payment link to
   `https://mtl-trader.vercel.app/pay`. Live accounts require the approved domain
   here; sandbox does not, which is why this only bites on the switch.

### 2. In Vercel (Production and Preview)

| Variable | Value |
| --- | --- |
| `PADDLE_API_KEY` | live `pdl_live_…` |
| `PADDLE_WEBHOOK_SECRET` | live destination secret |
| `PADDLE_PRICE_BASIC` | live `pri_…` for 12.00/month |
| `PADDLE_PRICE_PRO` | live `pri_…` for 29.00/month |
| `PADDLE_PRICE_BASIC_ANNUAL` | live `pri_…` for 120.00/year |
| `PADDLE_PRICE_PRO_ANNUAL` | live `pri_…` for 290.00/year |
| `PADDLE_ENVIRONMENT` | `production` |

`PADDLE_ENVIRONMENT` is the one people forget: leave it unset and a live key is
sent to `sandbox-api.paddle.com`, which 401s every checkout. Delete any leftover
`NEXT_PUBLIC_PADDLE_CLIENT_TOKEN` once `PADDLE_CLIENT_TOKEN` is in place — it is
only a fallback now, and a stale test token there is a trap.

### 3. Verify before a real sale

```bash
node --env-file=.env.live scripts/check-paddle-live.mjs --live
```

It reads only: key prefix against `PADDLE_ENVIRONMENT`, the API base, the
webhook secret, and each of the four price ids resolved against the catalogue
with the right interval, amount, currency and `active` status. A monthly id
pasted into a yearly slot is the failure it exists for — that charges $12 and
then the webhook refuses the year as `amount_mismatch`.

Then confirm the deployment itself:

```bash
curl -s https://mtl-trader.vercel.app/api/health | node -e "
let s='';process.stdin.on('data',d=>s+=d).on('end',()=>console.log(JSON.stringify(JSON.parse(s).paddle,null,1)))"
```

Expected: `keyEnvironment: "live"`, `api: "production"`, all four `prices` true,
and `annualReusesMonthlyPrice: []`. Anything else is a half-swap: fix the
variable, redeploy, re-read.

### 4. One real sale, then one refund

Buy Basic yearly with a real card. Then check:

* `payment_events` shows `120.00 | applied` for provider `paddle`;
* `users.current_period_end` moved about 365 days;
* refund it in Paddle → `adjustment.created` arrives, `revoke_paid_order` runs,
  and the account drops to `free`.

A refund that does not downgrade is the more expensive bug: it means the
adjustment webhook or its secret is wrong, and every future refund will need a
manual fix.

### API key permissions and expiry

The app makes exactly three keyed calls, so the key needs three permissions and
nothing else:

| Permission | Why |
| --- | --- |
| Transactions — **write** | `POST /transactions`: the checkout itself |
| Subscriptions — **write** | `POST /subscriptions/{id}/cancel` when a customer stops renewing |
| Prices — **read** | `scripts/check-paddle-live.mjs` resolving the four price ids |

Do not grant *All*. A key that can pay out, refund or read customers is a much
worse leak than one that can only create checkouts, and the app never uses those
paths.

**Expiry is a launch risk.** The new-key dialog defaults to 90 days, which is a
hard stop nobody connects to a payment outage: on the day it lapses every
checkout returns 401, and nothing in the code changed. Either clear the expiry on
the production key, or record the date here and put a reminder a week before it:

| Key | Expires | Rotate before |
| --- | --- | --- |
| Paddle live (production) | _fill in_ | _fill in_ |

After rotating, re-run the pre-flight and take one real sale: a key that cannot
create transactions still renders a working-looking button.

### Rollback

Flip the six variables back to the sandbox values, set `PADDLE_ENVIRONMENT` back
to empty, and redeploy. That restores test payments; it does **not** touch money
already taken. Live subscriptions keep billing in Paddle and must be cancelled
there, and any customer who paid live needs their plan in this database, not a
flipped key.
