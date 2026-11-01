# Android release: identity, signing, backups

Everything needed to build, sign, verify and ship the Flutter app in
`mobile_flutter/`. Written after the first real release build (1 Nov 2026).

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

1. Bump the build number in `mobile_flutter/pubspec.yaml` — `version: 1.0.1+2`.
   Only `+N` must change; Play rejects a duplicate version code.
2. `flutter build appbundle --release --dart-define-from-file=dart_defines.json`
3. Verify the signer fingerprint (above) — must be `395115FB…`
4. Install it (`flutter install` or `adb install -r`) and launch it once
5. Upload, or send the APK

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
