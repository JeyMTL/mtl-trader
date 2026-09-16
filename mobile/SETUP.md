# MTL Trader Mobile Setup Guide

## Prerequisites
- Node.js 18+ installed
- Android Studio (for Android builds)
- Xcode (for iOS builds, macOS only)

## Quick Setup

### 1. Install Dependencies
```bash
cd mobile
npm install
```

### 2. Add Platform Support

#### For Android:
```bash
npm run add:android
```

#### For iOS (macOS only):
```bash
npm run add:ios
```

### 3. Sync the Project
```bash
# Android
npm run sync:android

# iOS
npm run sync:ios
```

### 4. Open in IDE
```bash
# Android Studio
npm run open:android

# Xcode
npm run open:ios
```

## Building the App

### Android APK (for testing):
1. Open Android Studio: `npm run open:android`
2. Go to Build → Build Bundle(s) / APK(s) → Build APK(s)
3. APK will be at: `android/app/build/outputs/apk/debug/app-debug.apk`

### Android Release (for Play Store):
1. Create a keystore file (see Android documentation)
2. Update `android/app/build.gradle` with your keystore config
3. Run: `cd android && ./gradlew assembleRelease`
4. APK will be at: `android/app/build/outputs/apk/release/app-release.apk`

### iOS (App Store):
1. Open Xcode: `npm run open:ios`
2. Set your Development Team in Signing & Capabilities
3. Select "Any iOS Device" as build target
4. Product → Archive
5. Follow App Store submission process

## Configuration

### App URL
The app loads from `https://mtl-trader.vercel.app` by default.
To change this, edit `capacitor.config.json`:
```json
{
  "server": {
    "url": "https://your-domain.com"
  }
}
```

### Splash Screen
Customize the splash screen in `capacitor.config.json`:
```json
{
  "plugins": {
    "SplashScreen": {
      "backgroundColor": "#0d1117",
      "showSpinner": true,
      "spinnerColor": "#3884ff"
    }
  }
}
```

### Status Bar
Configure the status bar in `capacitor.config.json`:
```json
{
  "plugins": {
    "StatusBar": {
      "style": "DARK",
      "backgroundColor": "#0d1117",
      "overlaysWebView": false
    }
  }
}
```

## Features

### Mobile Optimizations
- **Safe Area Support**: Proper handling for notched phones (iPhone X+, etc.)
- **Pull-to-Refresh Prevention**: Prevents accidental page refresh
- **Touch Feedback**: Haptic feedback on button presses
- **Keyboard Handling**: Proper keyboard avoidance for input fields
- **Back Button**: Smart back navigation (web history → minimize)
- **Splash Screen**: Branded loading screen with spinner
- **Status Bar**: Dark theme status bar matching the app
- **Orientation**: Portrait mode on phones, all orientations on tablets

### Plugins Included
- `@capacitor/splash-screen` - Branded splash screen
- `@capacitor/status-bar` - Status bar styling
- `@capacitor/keyboard` - Keyboard behavior
- `@capacitor/haptics` - Touch feedback
- `@capacitor/app` - App lifecycle events

## Troubleshooting

### App shows white screen
1. Check internet connection
2. Verify the URL in `capacitor.config.json` is correct
3. Check Android Studio/Xcode console for errors

### Splash screen doesn't hide
1. Ensure `launchAutoHide: false` is set in config
2. The web app should call `SplashScreen.hide()` when ready

### Status bar color wrong
1. Update `backgroundColor` in `capacitor.config.json`
2. Rebuild the app

### Build fails
1. Run `npm install` again
2. Delete `node_modules` and reinstall
3. Run `cap sync` again

## Development

### Adding New Capacitor Plugins
1. Install the plugin: `npm install @capacitor/plugin-name`
2. Add to `capacitor.config.json` plugins section
3. Run `cap sync`

### Testing on Device
1. Connect your device via USB
2. Enable USB debugging (Android) or trust computer (iOS)
3. Run `npm run open:android` or `npm run open:ios`
4. Click Run in the IDE

## Distribution

### Internal Testing (Android)
1. Build APK: `cd android && ./gradlew assembleDebug`
2. Share the APK file directly
3. Users need to enable "Install from unknown sources"

### Internal Testing (iOS)
1. Use TestFlight for beta testing
2. Upload build through Xcode or Application Loader

### Production
1. Follow Google Play Store guidelines for Android
2. Follow App Store guidelines for iOS
3. Ensure all required metadata is complete
