# MTL Trader — Flutter mobile app

A native, flat-design Flutter client for the same Supabase journal as the web app. It replaces the old Capacitor shell (`/mobile`) for the phone app.

## What is in it

- **Desk** — balance, net P&L, win rate, profit factor, max drawdown, equity curve, time edge and the latest journal entries.
- **Journal** — searchable, paged trade list with entry → exit time windows and photo/voice-note counts.
- **Chart pinning** — every instrument ships in the app (forex majors, crosses and exotics, metals, indices, crypto, energy); tap the candle chart to fill entry, stop, target and exit prices and the entry/exit times instead of typing them. Spot forex and crypto charts are live and refresh every minute; exchange-traded instruments are delayed.
- **New / edit entry** — instrument, direction, entry price, size, SL/TP, commission, swap, strategy, notes, tags, entry time, live P&L — the exit is found from the candles after entry (whichever of SL/TP the market hit first) instead of being typed — plus:
  - multiple chart screenshots (camera or gallery),
  - a voice note recorded in the app,
  - an existing audio file.
- **Edge** — best/worst entry hour, best/weakest session, 24-hour P&L chart and the session table.
- **Subscription** — plan cards, the current plan and paid-through date, sold through Google Play Billing (no external card checkout). Cancelling keeps the paid period; a lapsed plan reads as ended and offers Buy a subscription.
- **Account** — plan, status, trade limit, editable report timezone and sign out.

The design is deliberately quiet: dark surfaces, 14 px cards with hairline borders, a single gold accent, rounded chips and 12 px fields and buttons. Depth comes from surface steps and spacing rather than gradients, shadows or glows.

## Requirements

- Flutter **3.47+** and Dart 3.9+ (tested with Flutter 3.47.4 / Dart 3.13)
- Android Studio / Xcode for device builds
- The Supabase migration `supabase/migrations/20261028_journal_media_and_time_stats.sql` applied (it creates the `trade_attachments` table and the private `journal-media` storage bucket)

## First run

The `android/` and `ios/` platform folders are included in this checkout. From this directory:

```bash
flutter pub get
```

If the platform folders are ever missing, run `flutter create --platforms=android,ios --project-name mtl_trader_mobile .` in an empty temporary folder and copy only its `android/` and `ios/` folders here. Avoid running it in place: it can overwrite `lib/main.dart`, `pubspec.yaml` or the README, and it adds a `test/widget_test.dart` for Flutter's counter template.

Run against your Supabase project:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Or keep the two values in `dart_defines.json` (see below) and run `flutter run --dart-define-from-file=dart_defines.json`.

Build a release APK:

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

## Signing and release builds

The application id is **`com.mtltrader.app`**. It is permanent once the app is on Play, and the signing key is permanent too: an updated APK signed with a different key is rejected, so back the keystore up somewhere you will still have it in five years.

Create the upload key once (JDK `keytool` is the one bundled with Android Studio):

```bash
cd android
"/c/Program Files/Android/Android Studio/jbr/bin/keytool" -genkeypair -v \
  -keystore upload-keystore.jks -alias upload \
  -keyalg RSA -keysize 4096 -validity 10000
```

Record the passwords it asks for in `android/key.properties` (git-ignored, along with `*.jks` and `*.keystore`):

```properties
storePassword=…
keyPassword=…
keyAlias=upload
storeFile=../upload-keystore.jks
```

Then build the artifact Play accepts:

```bash
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
# android/app/build/outputs/bundle/release/app-release.aab
```

`android/app/build.gradle.kts` reads that file when it exists and signs with the debug key when it does not, printing a notice — so `flutter run --release` still works on a fresh clone, but a bundle built without `key.properties` must never be uploaded.

Verify what a build was signed with before uploading:

```bash
"/c/Program Files/Android/Android Studio/jbr/bin/keytool" -print-cert \
  -keystore android/app/build/outputs/apk/release/app-release.apk \
  | head -5
```

The URL and anon key are the same values as `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` in the web app's `.env.local`. No service-role key is used on the device.

The other API calls (backtest, prop rules, market candles) go through the web API, so pass `--dart-define=API_BASE_URL=https://your-domain` when the deployment is not the production URL. Purchases themselves run through Google Play; no payment credential ships in the app.

## Run from Android Studio or VS Code

Both IDEs launch the app with `flutter run`, so they need the same Supabase credentials. Keep them in `dart_defines.json` in this folder (gitignored) and let the run configurations pass it with `--dart-define-from-file`:

```bash
cp dart_defines.example.json dart_defines.json
```

```json
{
  "SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
  "SUPABASE_ANON_KEY": "eyJ..."
}
```

**Android Studio** — open this folder (`mobile_flutter`, the one that holds `pubspec.yaml`), not the repo root and not `mobile_flutter/android`. The run configuration **main.dart** is checked in at `.idea/runConfigurations/main_dart.xml`; select it in the configuration dropdown and press ▶. If the dropdown offers no Flutter configuration, the Flutter plugin is not active or its SDK path is empty: check **Settings → Plugins** (Flutter and Dart) and **Settings → Languages & Frameworks → Flutter → Flutter SDK path**.

**VS Code** — open the same folder and add `.vscode/launch.json`:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "mtl_trader_mobile",
      "request": "launch",
      "type": "dart",
      "program": "lib/main.dart",
      "args": ["--dart-define-from-file=dart_defines.json"]
    }
  ]
}
```

That file stays out of git too: it points at the key file. The first Android build downloads Gradle, the Android Gradle Plugin and the Flutter engine, so it can take several minutes; later builds are fast.

## Put the Flutter SDK on PATH

`flutter` and `dart` are not on this machine's PATH, so the IDEs cannot find the SDK on their own and have to be pointed at `C:\Users\JeyMTLL\Desktop\ZANGA\flutter_sdk` by hand.

Windows: **Settings → System → About → Advanced system settings → Environment Variables**, select `Path` under *User variables*, **Edit → New**, add

```
C:\Users\JeyMTLL\Desktop\ZANGA\flutter_sdk\bin
```

then confirm with OK and open a new terminal (already-open ones keep their old environment).

For a single session instead:

```bash
# Git Bash
export PATH="/c/Users/JeyMTLL/Desktop/ZANGA/flutter_sdk/bin:$PATH"
```

```powershell
# PowerShell
$env:Path = "C:\Users\JeyMTLL\Desktop\ZANGA\flutter_sdk\bin;$env:Path"
```

Check it with `flutter --version`; `flutter doctor -v` should also stop warning that the flutter and dart binaries are not on the path, and Android Studio / VS Code detect the SDK without a manual path.

## Android build settings

Two settings in the Android project exist to keep plugin builds working with this Flutter/AGP/Gradle combination; don't remove them.

- `android/gradle.properties` sets `kotlin.incremental=false`. Kotlin 2.4's incremental caches fail to close under Gradle 9.3 on this JDK, which aborts every `compileDebugKotlin` task.
- `android/build.gradle.kts` pins `compileSdk` 36 for every Android module. Plugins such as `file_picker` still hardcode 34, which fails the AAR metadata check against AndroidX libraries that require 36.

## Platform permissions

The checked-in Android manifest and iOS `Info.plist` already include the microphone and camera permissions. If you regenerate the platform folders, add these entries again.

**`android/app/src/main/AndroidManifest.xml`** (inside `<manifest>`):

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

There is deliberately no `READ_MEDIA_IMAGES`: photos are attached through the Android system picker, which needs no permission, and declaring broad photo access makes Play demand a justification for a permission the app never uses.

**`ios/Runner/Info.plist`**:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Record a voice note for a journal entry.</string>
<key>NSCameraUsageDescription</key>
<string>Photograph a chart for a journal entry.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Attach a chart screenshot to a journal entry.</string>
```

Photo picking uses the system picker (`image_picker`), which needs no media permission on either platform; audio recording uses `record` 7; playback uses `just_audio`.

## Chart data

The chart picker reads candles from a public, keyless chart feed and draws them with a custom painter, so there is no API key, no market-data bill and nothing extra to configure. The free feed is live for spot forex and crypto: those charts carry a `LIVE` badge, refresh every 60 seconds while open, and show the last update time.

Exchange-traded instruments need a paid licence for real time, so their free charts stay delayed: the 11 indices (NAS100, US30, SPX500, GER40, and the rest), the metals (which track gold/silver/platinum/palladium futures) and the energy futures. They carry a `DELAYED` badge, and index charts add the stronger warning that they exist only so a trader can pin levels quickly, never to time an entry or read live price.

A chart tap sets the selected level (entry → stop → target → exit, in that order) and stores prices with the instrument's own decimals and times in the device timezone; the form converts both times to UTC before saving, exactly like a hand-typed entry. The chart behaves like a trading chart: drag to scroll the candles, pinch to zoom around the focal point, and long-press a level line to drag it to a new price. A crosshair tracks the finger and reads out the candle's open/high/low/close on the price and time axes.

## Storage and security

- Files go to the private `journal-media` bucket at `<user_id>/<trade_id|draft>/<uuid>.<ext>`.
- The storage policy compares the first path segment with `auth.uid()`, so a user can only read or write their own files.
- The app never stores a public URL — images and audio are fetched through one-hour signed URLs.
- `trade_attachments` has row-level security and a foreign key cascade; deleting a trade removes its rows. The app also removes the storage objects before deleting the trade.

## Project layout

```
lib/
  main.dart                  # Supabase init, config guard, MaterialApp
  core/
    config.dart              # --dart-define credentials
    format.dart              # money/date/duration formatting
    pnl.dart                 # contract size + P&L maths (mirrors web)
    edge.dart                # best/worst hour and session helpers
  models/models.dart         # summary, equity, time stats, trades, media
  services/
    journal_api.dart         # every RPC/CRUD/storage call
    media_service.dart       # image picker, file picker, recorder
  screens/
    auth_gate.dart           # session + email confirmation gate
    login_screen.dart
    app_shell.dart           # four tabs + compose button
    dashboard_screen.dart
    journal_screen.dart
    trade_form_screen.dart
    edge_screen.dart
    account_screen.dart
    media_viewer_screen.dart
  ui/
    theme.dart               # flat dark theme
    widgets.dart             # cards, metrics, pills, empty states
test/
  edge_test.dart
  pnl_test.dart
```

## Tests

```bash
flutter test
```

The tests cover the P&L maths, the best/worst window rules and the duration formatters. They do not need a Supabase project.

## Notes

- The app reads the same rows and RPCs as the web dashboard, so a trade journaled on the phone appears on the web immediately.
- The hour report uses the timezone saved on your profile. Change it from **Account → Timezone**; the four market sessions are always labelled in UTC.
- The Flutter app is deliberately dark-only; the flat token set lives in `lib/ui/theme.dart`.
- If the app shows the "Supabase credentials are missing" screen, you built without `--dart-define` flags.
