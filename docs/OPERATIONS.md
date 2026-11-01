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
