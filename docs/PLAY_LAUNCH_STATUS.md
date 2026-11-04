# Play launch — where we stopped (4 Nov 2026)

Resume sheet. Everything below was verified in Play Console or on the build
machine on 4 Nov 2026. Pick this file up first; nothing else needs re-deriving.

## State: closed testing is LIVE

| Item | Value |
| --- | --- |
| App id | `com.mtltrader.app` |
| Live version | **1.0.3**, version code **4** |
| Track | Closed testing – Alpha (Active, 178 countries) |
| Published | 4 Nov 2026 (Console: "Last published on November 4, 2026") |
| Testers | Google Group `mtl-trader-testers@googlegroups.com` |
| Feedback email | `jfx064@gmail.com` |
| Production track | Inactive — awaiting the 14-day rule |

## Version codes already burned

`1` (old internal 1.0.0), `2` (1.0.1, had the photo permission), `3` (1.0.2,
discarded draft), `4` (1.0.3, live). **Next build must be `1.0.4+5`.**

Play never re-releases a version code, *including* codes from drafts that were
discarded before rollout. Do not upload the same AAB twice and do not discard a
draft after its bundle is accepted.

## What changed for this release

- `mobile_flutter/pubspec.yaml` — `version: 1.0.3+4`
- `mobile_flutter/android/app/src/main/AndroidManifest.xml` — removed
  `READ_MEDIA_IMAGES`. Remaining permissions: `INTERNET`, `RECORD_AUDIO`,
  `ACCESS_NETWORK_STATE`, `BIND_JOB_SERVICE`, `DUMP`.
- `mobile_flutter/README.md` — permission note updated.
- The Play **Photo and video permissions** declaration was submitted with a
  truthful statement (permission removed in 1.0.2/1.0.3; the app only uses the
  Android system photo picker). Without submitting it the release could not be
  saved at all — the error appears even when the uploaded bundle no longer
  requests the permission, because an older bundle in the app still does.

## Build command (unchanged)

```bash
cd mobile_flutter
flutter build appbundle --release \
  --dart-define-from-file=dart_defines.json \
  --dart-define=PLAY_BUILD=true
```

Flutter lives at `/c/Users/JeyMTLL/Desktop/ZANGA/flutter_sdk/bin/flutter`.
Output: `build/app/outputs/bundle/release/app-release.aab` (~61 MB).

Verify before uploading:

```bash
M=$(find build/app/intermediates -name AndroidManifest.xml -path "*merged*release*" | head -1)
grep -o 'versionCode="[0-9]*"' "$M"; grep -o 'versionName="[^"]*"' "$M"
unzip -p build/app/outputs/bundle/release/app-release.aab base/manifest/AndroidManifest.xml | grep -c READ_MEDIA
```

`grep -c` printing `0` exits 1 — that is a pass, not a failure.

## How a tester installs

Two links, group first:

1. `https://groups.google.com/g/mtl-trader-testers` — Join group (setting is
   *Anyone can join*; if it shows **Ask to join**, approve them under
   People → Pending members).
2. `https://play.google.com/apps/testing/com.mtltrader.app` — Become a tester →
   Download it on Google Play.

The testing link fails if opened before joining (or while Google has not yet
synced the membership, ~2–5 min), and it only works for the account that joined
the group and is signed into Play on the phone. The public store URL
(`play.google.com/store/apps/details?id=com.mtltrader.app`) is not the testing
link.

Testers must stay opted in and keep the app installed. Uninstalling or leaving
the program resets their contribution.

## The 14-day clock

Play requires **≥12 testers opted in continuously for 14 days** before production
access can be requested. Clock started 4 Nov 2026, so the earliest application is
**18 Nov 2026** — and only if 12 distinct accounts have been opted in the whole
time.

Check progress: Play Console → Dashboard → *Production access* card, or
Closed testing – Alpha → Testers tab (it shows how many are opted in).

Then: **Dashboard → Apply for production access** → answer the questionnaire
(how you recruited testers, what they tested, what you fixed) → submit →
Create production release with the same AAB approach (bump the version code
first) → roll out in stages.

## Still to do after production (Play Billing is not testable yet)

Billing cannot be exercised until the app is installed **from Play** with a
licence-tester account, and until the Console/API pieces exist:

1. Payments profile active on the developer account.
2. **Monetise with Play → Products → Subscriptions** — four subscriptions, ids
   exactly as in `docs/ANDROID_RELEASE.md`: `basic_month`/`basic-month`,
   `basic_year`/`basic-year`, `pro_month`/`pro-month`, `pro_year`/`pro-year`.
   Every base plan must be **Active**.
3. **Settings → API access** — service account with *View financial data* and
   *Manage orders and subscriptions*; JSON key.
4. Vercel env: `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`, `GOOGLE_PLAY_PACKAGE_NAME=com.mtltrader.app`; redeploy.
5. **Setup → License testing** — add the test phone's account.
6. Buy each plan once from the Play-installed build; confirm the row in
   `google_play_subscriptions` gets `acknowledged = true` and the plan unlocks.

## Console items still open

- **Data safety** form (App content) — not yet completed.
- Store listing: AI-generated asset label — choose *Label assets as created or
  edited using AI* and tick only the five phone screenshots, not the icon or
  feature graphic.
- Production release has never been created.

## Files worth knowing

| Path | Why |
| --- | --- |
| `docs/ANDROID_RELEASE.md` | keystore, signing, build, billing setup detail |
| `docs/PLAY_LISTING.md` | listing copy, screenshots, product ids |
| `mobile_flutter/lib/services/play_billing.dart` | purchase flow |
| `src/app/api/billing/google/verify/route.ts` | server-side verification + ack |
| `src/lib/google-play.ts`, `src/lib/google-billing.ts` | Google API client |
| `supabase/migrations/20261115_google_play_billing.sql` | `google_play_subscriptions` |
| `store/` | icon, feature graphic, mockups |

## Uncommitted work

Everything from this launch push — the manifest permission removal, the version
bump, the docs, `store/`, the billing and telemetry code — is **uncommitted** in
git on `main`. Nothing has been pushed.
