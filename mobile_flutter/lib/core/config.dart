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
    defaultValue: 'https://mtl-trader.vercel.app',
  );

  /// Deep link Supabase returns the Google sign-in to. It must match the scheme
  /// registered for the app (Android intent filter / iOS URL scheme) and be
  /// allow-listed under Authentication → URL Configuration in Supabase.
  static const String oauthRedirect = String.fromEnvironment(
    'OAUTH_REDIRECT',
    defaultValue: 'com.mtltrader.app://login-callback',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
