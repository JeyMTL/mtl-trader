# Android release: identity, signing, backups

Everything needed to build, sign, verify and ship the Flutter app in
`mobile_flutter/`. Written after the first real release build (1 Nov 2026).

Current Play state, burned version codes and the resume checklist live in
`docs/PLAY_LAUNCH_STATUS.md`.

## What was wrong before

| Problem | Consequence |
|---|---|
| `buildTypes.release` signed with `signingConfigs.getByName("debug")` | Play rejects a debug-signed bundle; the debug key is per-machine, so an APK built on another machine cannot update one installed from this one |
| `applicationId = com.mtltrader.mtl_trader_mobile` (Flutter template, folder-derived) | The id is **permanent after the first Play upload**; it would have been locked in with a template name |
| `android:allowBackup` defaulted to true | The Supabase session in SharedPreferences could leave the phone via cloud backup or device transfer |
| No keystore, no `key.properties`, no git rules for them | One `git add .` would have published the app's signing identity |

## Identity — do not change any of this before the first upload

| Field | Value |
|---|---|
| Application id | `com.mtltrader.app` |
| Keystore | `mobile_flutter/android/upload-keystore.jks` (4,328 bytes) |
| Keystore SHA-256 (file) | `dea673231031f0aeff4ea1f82349f783cf4502f2969e16fea944e26ddaa75a14` |
| Key alias | `upload` |
| Certificate subject | `CN=MTL Trader, O=MTL Trader, L=Nairobi, C=KE` |
| Certificate SHA-256 | `395115FB64473543C022A125880B546482FD1536DA5F89A270B191DB29F44CF4` |
| Key | RSA 4096, PKCS12 store |
| Validity | 10,000 days (until ~2054) |

The certificate fingerprint is what Play uses to recognise updates. If a future
upload shows a different fingerprint, the wrong keystore was used — stop.

## Where the password lives

`mobile_flutter/android/key.properties` (4 lines: `storePassword`, `keyPassword`,
`keyAlias`, `storeFile`). It is git-ignored at two levels:

```
.gitignore:83                      *.jks / *.keystore / key.properties
mobile_flutter/android/.gitignore   key.properties, **/*.jks
```

The password is deliberately **not** in this document, in `mobile/App Details.txt`,
or anywhere in git history (verified with `git log --all -S<password>` → no
commits). A second copy belongs in a password manager on the phone, so that a
dead laptop does not take the signing identity with it.

## Backups — three identical copies

```
D:\MTL\mtl-trader\mobile_flutter\android\upload-keystore.jks   (working copy)
D:\Backups\MTL Trader\upload-keystore.jks                      (second disk)
C:\Users\<user>\OneDrive\upload-keystore.jks                   (off the machine)
```

Re-verify at any time — all three hashes must be `dea67323…`:

```bash
sha256sum \
  "/d/MTL/mtl-trader/mobile_flutter/android/upload-keystore.jks" \
  "/d/Backups/MTL Trader/upload-keystore.jks" \
  "$HOME/OneDrive/upload-keystore.jks"
```

A backup on the same physical disk is not a backup. The OneDrive copy is the one
that survives hardware failure.

## Building a release

Credentials come from `dart_defines.json` (git-ignored):

```bash
cd mobile_flutter

# APK — for handing to a tester or sideloading
flutter build apk --release --dart-define-from-file=dart_defines.json

# AAB — the one Play accepts
flutter build appbundle --release --dart-define-from-file=dart_defines.json
```

Outputs:

```
build/app/outputs/flutter-apk/app-release.apk           ~60 MB
build/app/outputs/bundle/release/app-release.aab
```

If Gradle prints `Release will be signed with the debug key: android/key.properties
is missing`, the build **must not be shipped** — that notice means the fallback
path was taken (kept so a fresh clone can still run `flutter run --release`).

## Verifying a build before it leaves the machine

```bash
JAVA_HOME="/c/Program Files/Android/Android Studio/jbr" \
"/c/Users/<user>/AppData/Local/Android/Sdk/build-tools/36.0.0/apksigner.bat" \
  verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

Expected:

```
Signer #1 certificate DN: CN=MTL Trader, O=MTL Trader, L=Nairobi, C=KE
Signer #1 certificate SHA-256 digest: 395115fb64473543c022a125880b546482fd1536da5f89a270b191db29f44cf4
```

`CN=Android Debug` means the build is unsafe to distribute. For the `.aab`
(a jar-signed format), use `keytool -printcert -jarfile app-release.aab`.
`keytool` needs its full path — it is not on PATH on this machine.

Check the keystore still opens with the recorded password:

```bash
cd mobile_flutter/android
keytool -list -keystore upload-keystore.jks \
  -storepass "$(grep '^storePassword=' key.properties | cut -d= -f2-)"
# must print: upload, PrivateKeyEntry
```

## Installing on a device (verified 1 Nov 2026)

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am start -n com.mtltrader.app/.MainActivity
adb shell pidof com.mtltrader.app     # non-empty pid = running
```

Result on the Pixel 7a (Android 17 / API 37): install `Success`, `versionName=1.0.0`,
`firstInstallTime 2026-11-01 06:02:36`, app running, no `FATAL` /
`AndroidRuntime` / `E/flutter` entries in logcat after launch.

The pre-rename build `com.mtltrader.mtl_trader_mobile` (installed 28 Oct) is a
separate package on that phone; remove it once the new one is trusted:

```bash
adb uninstall com.mtltrader.mtl_trader_mobile
```

## Release checklist (every build after this)

1. Bump both numbers in `mobile_flutter/pubspec.yaml` — `version: 1.0.4+5`. The number after `+` is the Android version code, and Play rejects one it has already accepted — including a code uploaded into a draft that was later discarded — so it must always increase.
2. `flutter build appbundle --release --dart-define-from-file=dart_defines.json`
3. Verify the signer fingerprint (above) — must be `395115FB…`
4. Install it (`flutter install` or `adb install -r`) and launch it once
5. Upload, or send the APK

## Google Play Billing

The Play build sells the subscription through Google Play. The card checkout
(Paddle) stays on the website and in side-loaded builds, because a
Play-distributed app may not send buyers to an external checkout for the same
digital subscription. Google keeps 15% of a subscription sold through Play
(10% service fee + 5% billing fee); Paddle keeps about 5% on the website.

| Piece | Where |
| --- | --- |
| Product ids and purchase flow | `mobile_flutter/lib/services/play_billing.dart` |
| Plan cards and purchase UI | `mobile_flutter/lib/screens/subscription_screen.dart` |
| Verification route | `src/app/api/billing/google/verify/route.ts` |
| Google API client | `src/lib/google-play.ts` |
| Stored purchase tokens | `google_play_subscriptions` (`20261115_google_play_billing.sql`) |

Build the Play bundle with the flag; without it the app keeps the card checkout
and the upload is the violation the flag exists to prevent:

```bash
cd mobile_flutter
flutter build appbundle --release \
  --dart-define-from-file=dart_defines.json \
  --dart-define=PLAY_BUILD=true
```

### Console setup, once

1. Play Console → **Monetise with Play** → **Products** → **Subscriptions**.
   Create four subscriptions, one per cadence, with exactly these ids:

   | Product id | Base plan id | Price |
   | --- | --- | --- |
   | `basic_month` | `basic-month` | $12.00 / month |
   | `basic_year` | `basic-year` | $120.00 / year |
   | `pro_month` | `pro-month` | $29.00 / month |
   | `pro_year` | `pro-year` | $290.00 / year |

   The app looks these ids up verbatim; a different id is a disabled button, not
   an error message. **Activate** every base plan — an inactive one is invisible
   to the store and never returned to the app. Google sets local prices and taxes
   from the USD amount, so the app shows Play's price, not `plans.dart`'s.
2. **Settings → API access**: link a Google Cloud project, then create a service
   account and grant it *View financial data* and *Manage orders and
   subscriptions* in Play Console. Create a JSON key for it.
3. Vercel → Settings → Environment Variables:
   `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` = the JSON key (raw, or base64 of it — the
   private key is a multi-line PEM), and `GOOGLE_PLAY_PACKAGE_NAME` =
   `com.mtltrader.app`. Redeploy.
4. **Setup → License testing**: add the Google account on your test phone. A
   licence tester is charged nothing and can buy the same product repeatedly.

### How a purchase reaches the database

1. The app opens Play's sheet and Play returns a purchase token.
2. The app posts the token to `/api/billing/google/verify`.
3. The server asks Google what the token is worth (`subscriptionsv2.get`) and
   ignores everything the app claimed.
4. The period is applied through `apply_paid_order` / `apply_annual_order` under
   the `google` provider, keyed on token + period end, so a replay grants nothing
   and a renewal grants once.
5. The server **acknowledges** the purchase. Skipping this makes Google refund
   it automatically after three days.

The daily `/api/admin/reconcile` run re-checks stored tokens, which is how a
renewal is noticed without real-time developer notifications (those need a
Pub/Sub topic and a billing-enabled Cloud project).

Known gaps, until real-time notifications are worth their cost: a refund or
chargeback is not detected automatically — revoke the plan by hand — and a
renewal is applied up to a day late, which costs the customer nothing because
access runs to the period end Google reported.

### Testing

Purchases can only be tested from a build **installed from Play** (internal
testing track) with a licence-tester account, and the version code must be
uploaded — a locally installed APK cannot buy anything. Before the first upload
the buttons will say the plan is not on sale; that is the expected state.

## If the keystore is lost

| When | Outcome |
|---|---|
| Before any upload | Regenerate — nothing has been published under the old key |
| After a Play upload, **without** Play App Signing | The app id is dead: no update can ever be signed again. A new app id is the only path |
| After a Play upload, **with** Play App Signing | Recoverable — Google holds the app signing key and the lost file is only the upload key, which support can reset |

Because of that third row, **enrol in Play App Signing** when creating the app in
the Play Console. It is free and it is the only safety net.

## Open items

- [ ] Store the keystore password in a password manager (on the phone, not only here)
- [ ] Build the `.aab` and run a Play internal-testing release ($25 one-time account)
- [ ] Upload the app icon/listing; `docs/LISTINGS.md` holds the copy
- [ ] iOS: bundle id, distribution certificate and a macOS runner — not possible on Windows
- [ ] Remove the old `com.mtltrader.mtl_trader_mobile` build from test devices

## Play listing assets

Everything the console asks for under **Store listing**, and where it comes
from. The store entry is rejected for a missing asset far more often than for a
bug, and the console will not tell you which one until you try to submit.

| Asset | Requirement | Source |
| --- | --- | --- |
| App icon | 512×512 PNG, no alpha, no rounded corners | `store/icon-512.png` (rendered from `assets/icon/`) |
| Feature graphic | 1024×500 PNG or JPEG | `store/feature-graphic.png` |
| Phone screenshots | 2–8 × PNG, 16:9 or 9:16, min 1080px on the long edge | capture, see below |
| Short description | ≤ 80 characters | `docs/PLAY_LISTING.md` |
| Full description | ≤ 4000 characters | same file |
| Privacy policy URL | public, no sign-in | `/privacy` |
| Account deletion URL | public, no sign-in | `/delete-account` |

Regenerate the feature graphic after editing `store/feature-graphic.html`:

```bash
node scripts/make-store-graphics.mjs
```

It screenshots the HTML with the installed Chrome at exactly 1024×500, so the
result is reproducible instead of a binary nobody can edit.

### Screenshots

Take these on a real phone, not a simulator: the simulator's status bar and font
rendering both differ from the store listing's own chrome, and Google's reviewer
sees the real device.

1. `flutter run --release` on the test device (a 1080×1920-class Android is
   enough; the app scales).
2. Populate a demo account with 15–20 trades across 3 symbols, one strategy per
   symbol, and at least one journal photo. An empty journal makes every screen
   look broken.
3. Capture with the volume-down + power chord, then crop the status bar out.

Capture in this order — the first two are what the listing shows without a tap:

1. **Dashboard** — equity curve and the month's P&L.
2. **Chart** — candles with an entry, stop and target pinned.
3. **Analytics** — time edge by hour and session.
4. **Trade form** — the strategy chips and colour dots.
5. **Backtest** — a saved run with its metrics.
6. **Journal** — a trade with a photo attached.

Screens keep the maximum system font size setting; if a screen overflows at 2×
text the listing will show it, and `test/screen_layout_test.dart` is the thing
that would have caught it first.
