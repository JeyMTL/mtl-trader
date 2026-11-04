import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/config.dart';

/// Crash and funnel reporting, first-party.
///
/// Two rules shape everything here:
///
///   * It must never break the app. Every network failure is swallowed, the
///     client has a short timeout, and nothing awaits it on a user path.
///   * It must not identify anyone. There is no email, no device id, no journal
///     text in `properties` — only the event name and a handful of enums. The
///     session id is random per launch, so sessions cannot be stitched together
///     into a profile of a person.
///
/// Without this, the closed test produces no answer to "where did the twelve
/// testers stop?", which is the only question worth asking before launch.
class Telemetry {
  Telemetry._();

  static final Random _random = Random.secure();
  static HttpClient? _client;
  static String? _session;
  static String _platform = 'android';

  /// Which build this is, so a fix can be tied to a version. Keep it in step
  /// with the version in `pubspec.yaml`.
  static const String appVersion = '1.0.0';

  /// Starts a session. Called once from `main`, before the widget tree exists.
  static void start({String? platform}) {
    _session ??= _newSessionId();
    if (platform != null) {
      _platform = platform;
    } else if (Platform.isIOS) {
      _platform = 'ios';
    }

    event('app_open');
  }

  /// Records one event. Fire-and-forget: the future is deliberately not exposed,
  /// because no caller should be able to wait on telemetry.
  static void event(String name, [Map<String, Object?> properties = const {}]) {
    final session = _session ??= _newSessionId();
    _post({
      'event': name,
      'sessionId': session,
      'platform': _platform,
      'appVersion': appVersion,
      'properties': _clean(properties),
    });
  }

  /// A crash or handled error worth knowing about. The message is truncated and
  /// the stack reduced to its first frames: a full stack from an obfuscated
  /// release build is unreadable anyway, and stripping it keeps the payload
  /// under the server's 2 KB cap.
  static void crash(Object error, StackTrace? stack,
      {String source = 'unknown'}) {
    final message = error.toString();
    final frames = (stack?.toString() ?? '')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(6)
        .join('\n');

    event('app_error', {
      'source': source,
      'message':
          message.length > 300 ? '${message.substring(0, 300)}…' : message,
      'stack': frames.length > 900 ? frames.substring(0, 900) : frames,
    });
  }

  /// Drops anything that could carry user content or blow the payload cap.
  ///
  /// Only scalars survive, keys are snake_case and short, and there is a hard
  /// limit on how many pairs go out. A property that is not a scalar is
  /// replaced by its type name rather than serialised, so a nested map can never
  /// smuggle a note or an order into the event.
  static Map<String, Object?> _clean(Map<String, Object?> input) {
    final out = <String, Object?>{};
    for (final entry in input.entries) {
      if (out.length >= 8) break;
      final key =
          entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
      if (key.isEmpty || key.length > 32) continue;
      final value = entry.value;
      if (value == null) {
        out[key] = null;
      } else if (value is num || value is bool) {
        out[key] = value;
      } else if (value is String) {
        out[key] = value.length > 120 ? value.substring(0, 120) : value;
      } else {
        out[key] = value.runtimeType.toString();
      }
    }
    return out;
  }

  static String _newSessionId() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List<String>.generate(
      20,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
  }

  static void _post(Map<String, Object?> body) {
    if (!AppConfig.isConfigured) return;

    // One client for the process: creating an HttpClient per event leaks
    // connections, and telemetry must not be the reason the app runs hot.
    final client = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 4)
      ..idleTimeout = const Duration(seconds: 10);

    () async {
      try {
        final request = await client
            .postUrl(Uri.parse('${AppConfig.apiBaseUrl}/api/telemetry'))
            .timeout(const Duration(seconds: 4));
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
        final response =
            await request.close().timeout(const Duration(seconds: 4));
        // The body is never read: draining a response we do not want is the
        // difference between a clean socket and one held open until timeout.
        await response.drain<void>();
      } catch (_) {
        // Offline, DNS failure, a 500: none of it is worth surfacing, and a
        // telemetry failure during a crash must not become a second crash.
      }
    }();
  }
}
