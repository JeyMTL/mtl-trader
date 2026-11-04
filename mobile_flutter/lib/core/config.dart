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

  /// True for the build uploaded to Google Play.
  ///
  /// ```
  /// flutter build appbundle --dart-define=PLAY_BUILD=true
  /// ```
  ///
  /// Google Play requires digital subscriptions sold for use inside the app to
  /// go through Play Billing, and an app that sends buyers to an external
  /// checkout for the same subscription is rejected under the Payments policy.
  /// This build therefore sells through Google Play: the plan buttons open the
  /// Play purchase sheet and the purchase is verified server-side against
  /// Google. There is no button that starts the card checkout and no link out
  /// to one. Direct-sold subscriptions (the website and any side-loaded build)
  /// are unaffected and keep the hosted card checkout.
  static const bool playBuild = bool.fromEnvironment('PLAY_BUILD');

  /// Whether this build may start a hosted card checkout. False in the Play
  /// build, where Play Billing is the only purchase path.
  static const bool cardCheckoutEnabled = !playBuild;
}
