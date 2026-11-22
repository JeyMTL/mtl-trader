/// The one place a thrown error becomes words a trader can read.
///
/// Package errors are written for developers: Supabase answers with
/// `PostgrestException(message: ..., code: ..., details: ..., hint: ...)`,
/// Google Play answers with `PlatformException(...)`, and the HTTP client
/// answers with socket vocabulary. Screens call this with the sentence they
/// would otherwise show; known problems are translated, anything technical is
/// replaced by that sentence.
library;

const String _fallback = 'Something went wrong. Please try again.';

final RegExp _connection = RegExp(
  r'failed to fetch|socketexception|connection (refused|closed|reset)|'
  r'network|timed? ?out|host lookup|handshake|xmlhttprequest|offline',
  caseSensitive: false,
);

final RegExp _vendor = RegExp(
  r'postgrest|supabase|postgres|pgrst|row[- ]level|\brls\b|duplicate key|'
  r'violates .*constraint|schema cache|vercel|jwt|service[_ ]role|'
  r'platformexception|missingpluginexception|in_app_purchase|oanda',
  caseSensitive: false,
);

/// [error] as a sentence, or [fallback] when it is technical or empty.
String friendlyError(
  Object? error, {
  String fallback = _fallback,
}) {
  if (error == null) return fallback;

  var text = error.toString().trim();
  // `Exception: ` and the `PostgrestException(message: ` wrapper are noise; the
  // content between the quotes is what the check below has to see.
  text = text.replaceFirst(
    RegExp(r'^(Exception|PlatformException|PostgrestException|FormatException):\s*'),
    '',
  );

  if (text.isEmpty || text == 'null' || text.startsWith('{')) return fallback;

  final lower = text.toLowerCase();
  if (_connection.hasMatch(lower)) {
    return 'Could not reach the server. Check your connection and try again.';
  }
  if (RegExp(r'rate limit|too many (requests|attempts)').hasMatch(lower)) {
    return 'Too many attempts. Please wait a moment and try again.';
  }
  if (_vendor.hasMatch(lower)) return fallback;

  return text;
}
