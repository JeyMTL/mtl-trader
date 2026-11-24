/// Build-time configuration.
///
/// Credentials are passed with `--dart-define` so no key is ever committed:
///
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJ...
/// ```
class AppConfig {
  const AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Base URL of the web app, used for the hosted card checkout. Override it
  /// with `--dart-define=API_BASE_URL=https://your-domain` for a self-hosted
  /// deployment.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://mtlledger.com',
  );

  /// Deep link Supabase returns the Google sign-in to. It must match the scheme
  /// registered for the app (Android intent filter / iOS URL scheme) and be
  /// allow-listed under Authentication → URL Configuration in Supabase.
  static const String oauthRedirect = String.fromEnvironment(
    'OAUTH_REDIRECT',
    defaultValue: 'com.mtltrader.app://login-callback',
  );

  /// Web OAuth client ID, used as the `serverClientId` for native Google
  /// sign-in so the ID token's audience matches the client Supabase validates
  /// against. Public by design — the browser bundle ships the same value.
  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue:
        '896111658733-62il22avnott85bhj46dnlkpcnp0era7.apps.googleusercontent.com',
  );

  /// Firebase project values, passed at build time:
  ///
  /// ```
  /// flutter build apk --dart-define-from-file=dart_defines.json
  /// ```
  ///
  /// These are the *public* client values from Firebase → Project settings →
  /// Your apps, not a service account. They are safe in an APK, exactly like
  /// `SUPABASE_ANON_KEY`. With them absent, push stays off and the rest of the
  /// app is unaffected — no `google-services.json` is needed, because the app is
  /// initialised with these values directly.
  static const String firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
  );
  static const String firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String firebaseSenderId = String.fromEnvironment(
    'FIREBASE_SENDER_ID',
  );
  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const String firebaseStorageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Server-sent notifications are only possible when a Firebase project is
  /// wired into this build.
  static bool get pushConfigured =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;

  /// Purchases in this app always go through Google Play.
  ///
  /// Google Play requires digital subscriptions sold for use inside the app to
  /// go through Play Billing, and an app that sends buyers to an external
  /// checkout for the same subscription is rejected under the Payments policy.
  /// The plan buttons therefore open the Play purchase sheet and the purchase is
  /// verified server-side against Google; there is no card checkout and no link
  /// out to one. The website is a separate Next.js app and keeps its hosted card
  /// checkout (Paddle) for browser buyers.
  static const bool storeBillingOnly = true;
}
