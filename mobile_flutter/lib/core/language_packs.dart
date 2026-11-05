import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations_pack.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/gen/app_localizations_en.dart';
import 'config.dart';
import 'locale.dart';

/// One pack as advertised by `/locales/manifest.json`: enough to show a size
/// and a version without downloading the messages.
class LanguagePackInfo {
  const LanguagePackInfo({
    required this.code,
    required this.version,
    required this.bytes,
    required this.keys,
  });

  factory LanguagePackInfo.fromJson(String code, Map<String, dynamic> json) {
    final version = json['version'];
    final bytes = json['bytes'];
    final keys = json['keys'];
    return LanguagePackInfo(
      code: code,
      version: version is int ? version : 0,
      bytes: bytes is int ? bytes : 0,
      keys: keys is int ? keys : 0,
    );
  }

  final String code;
  final int version;
  final int bytes;
  final int keys;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'bytes': bytes,
        'keys': keys,
      };
}

/// A downloaded pack and the strings it carries.
class LanguagePack {
  const LanguagePack({
    required this.code,
    required this.version,
    required this.bytes,
    required this.messages,
  });

  final String code;
  final int version;
  final int bytes;
  final Map<String, String> messages;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'bytes': bytes,
        'keys': messages.length,
      };
}

/// The downloaded half of the interface language.
///
/// English is compiled into the app, so it always works, offline and on a fresh
/// install. Every other language is a pack: the picker downloads it, this class
/// stores it on the phone, and the localization delegate below serves it —
/// falling back to English for any message the pack has not translated.
///
/// Packs are plain JSON by design: publishing a translation is uploading a file,
/// not shipping a build.
class LanguagePacks extends ChangeNotifier {
  LanguagePacks({Future<String> Function(Uri uri)? fetch})
      : _fetch = fetch ?? _httpGet;

  /// Replaced by tests so they never touch the network.
  static LanguagePacks instance = LanguagePacks();

  static const String manifestPath = '/locales/manifest.json';

  static const String _indexKey = 'app.locale.packs.v1';
  static const String _availableKey = 'app.locale.packs.available.v1';

  static String _packKey(String code) => 'app.locale.pack.v1.$code';

  /// Languages compiled into the app rather than downloaded.
  static final Set<String> bundled = AppLocalizations.supportedLocales
      .map((locale) => locale.languageCode)
      .toSet();

  final Future<String> Function(Uri uri) _fetch;

  final Map<String, LanguagePack> _installed = <String, LanguagePack>{};
  final Map<String, LanguagePackInfo> _available = <String, LanguagePackInfo>{};
  final Set<String> _installing = <String>{};
  final Map<String, String> _errors = <String, String>{};

  int _generation = 0;

  /// Bumped whenever the installed set changes. The app puts it in a widget key
  /// so a download that lands repaints the surface in the new language.
  int get generation => _generation;

  /// Published packs, whether or not they are on this phone.
  Map<String, LanguagePackInfo> get available =>
      Map<String, LanguagePackInfo>.unmodifiable(_available);

  bool isBuiltIn(String code) => bundled.contains(code);

  bool isInstalled(String code) => _installed.containsKey(code);

  bool isInstalling(String code) => _installing.contains(code);

  LanguagePackInfo? infoFor(String code) => _available[code];

  String? errorFor(String code) => _errors[code];

  /// The strings of an installed pack, or null when it is not on the phone.
  Map<String, String>? messagesFor(String code) => _installed[code]?.messages;

  /// Reads the packs saved on this phone. Called from `main` before `runApp`,
  /// so a downloaded language is already active on the first frame.
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final index = prefs.getString(_indexKey);
      if (index is String) {
        final decoded = jsonDecode(index);
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            final row = entry.value;
            if (row is! Map<String, dynamic>) continue;
            final raw = prefs.getString(_packKey(entry.key));
            if (raw is! String) continue;
            final messages = _decodeMessages(raw);
            if (messages == null) continue;
            final info = LanguagePackInfo.fromJson(entry.key, row);
            _installed[entry.key] = LanguagePack(
              code: entry.key,
              version: info.version,
              bytes: info.bytes,
              messages: messages,
            );
          }
        }
      }

      final cached = prefs.getString(_availableKey);
      if (cached is String) {
        final decoded = jsonDecode(cached);
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            final row = entry.value;
            if (row is Map<String, dynamic>) {
              _available[entry.key] = LanguagePackInfo.fromJson(entry.key, row);
            }
          }
        }
      }
    } catch (_) {
      // An unreadable store just means nothing is downloaded yet.
    }
  }

  /// Fetches the list of published packs. Best effort: on failure the picker
  /// keeps the cached list (or shows no download offer at all).
  Future<void> refreshManifest() async {
    try {
      final body = await _fetch(Uri.parse('${AppConfig.apiBaseUrl}$manifestPath'));
      final decoded = jsonDecode(body);
      final rows = decoded is Map<String, dynamic> ? decoded['packs'] : null;
      if (rows is! List) return;

      final next = <String, LanguagePackInfo>{};
      for (final row in rows) {
        if (row is! Map<String, dynamic>) continue;
        final code = row['code'];
        if (code is! String) continue;
        // A pack for a language the catalogue dropped would be unreachable.
        if (!LocaleController.languages.any((entry) => entry.code == code)) {
          continue;
        }
        next[code] = LanguagePackInfo.fromJson(code, row);
      }

      _available
        ..clear()
        ..addAll(next);
      notifyListeners();
      await _saveManifest();
    } catch (_) {
      // Offline, or the manifest is not deployed yet.
    }
  }

  /// Downloads and stores one language. Returns false when it could not be
  /// fetched, leaving the phone exactly as it was.
  Future<bool> install(String code) async {
    if (isBuiltIn(code) || _installed.containsKey(code)) return true;
    if (!_installing.add(code)) return false;

    _errors.remove(code);
    notifyListeners();
    try {
      final body = await _fetch(Uri.parse('${AppConfig.apiBaseUrl}/locales/$code.json'));
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) throw const FormatException('pack');
      final messages = _decodeMessages(jsonEncode(decoded['messages']));
      if (messages == null || messages.isEmpty) {
        throw const FormatException('pack');
      }

      final version = decoded['version'];
      final pack = LanguagePack(
        code: code,
        version: version is int ? version : 0,
        bytes: utf8.encode(body).length,
        messages: messages,
      );
      _installed[code] = pack;
      _available.putIfAbsent(
        code,
        () => LanguagePackInfo(
          code: code,
          version: pack.version,
          bytes: pack.bytes,
          keys: messages.length,
        ),
      );
      _generation++;
      await _saveInstalled(code, pack);
      return true;
    } catch (_) {
      _errors[code] = 'download_failed';
      return false;
    } finally {
      _installing.remove(code);
      notifyListeners();
    }
  }

  /// Deletes a downloaded pack. The caller decides what happens to a language
  /// that was active.
  Future<void> remove(String code) async {
    if (_installed.remove(code) == null) return;
    _generation++;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_packKey(code));
      await prefs.setString(
        _indexKey,
        jsonEncode(<String, dynamic>{
          for (final entry in _installed.entries) entry.key: entry.value.toJson(),
        }),
      );
    } catch (_) {
      // The pack still disappears for this session.
    }
  }

  /// Downloads the saved language's pack if it is not on the phone yet, so a
  /// language chosen before packs existed comes back without a trip to settings.
  Future<void> ensureActivePack(String? code) async {
    if (code == null || isBuiltIn(code) || _installed.containsKey(code)) return;
    if (_available.isEmpty) await refreshManifest();
    if (!_available.containsKey(code)) return;
    await install(code);
  }

  /// The delegates the app hands to `MaterialApp`: packs first, then the
  /// standard Material/Cupertino strings.
  List<LocalizationsDelegate<dynamic>> get delegates =>
      <LocalizationsDelegate<dynamic>>[
        _PackDelegate(this, _generation),
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  LanguagePack? packFor(String code) => _installed[code];

  /// Used by tests and by the offline harnesses: installs messages without a
  /// server round trip.
  @visibleForTesting
  Future<void> seed(
    String code,
    Map<String, String> messages, {
    int version = 1,
  }) async {
    final pack = LanguagePack(
      code: code,
      version: version,
      bytes: 0,
      messages: messages,
    );
    _installed[code] = pack;
    _generation++;
    notifyListeners();
    try {
      await _saveInstalled(code, pack);
    } catch (_) {
      // Memory still has it.
    }
  }

  Future<void> _saveInstalled(String code, LanguagePack pack) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_packKey(code), jsonEncode(pack.messages));
    await prefs.setString(
      _indexKey,
      jsonEncode(<String, dynamic>{
        for (final entry in _installed.entries) entry.key: entry.value.toJson(),
      }),
    );
  }

  Future<void> _saveManifest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _availableKey,
      jsonEncode(<String, dynamic>{
        for (final entry in _available.entries) entry.key: entry.value.toJson(),
      }),
    );
  }

  static Map<String, String>? _decodeMessages(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final messages = <String, String>{};
      for (final entry in decoded.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! String) continue;
        if (key.startsWith('@')) continue;
        messages[key] = value;
      }
      return messages.isEmpty ? null : messages;
    } catch (_) {
      return null;
    }
  }

  static Future<String> _httpGet(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 400) {
        throw HttpException('pack not published', uri: uri);
      }
      return text;
    } finally {
      client.close(force: true);
    }
  }
}

/// Serves English, the bundled locales, and downloaded packs.
///
/// A language with no pack resolves to the English strings — the locale is
/// still active, so dates, numbers and text direction follow the choice.
class _PackDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _PackDelegate(this._packs, this.generation);

  final LanguagePacks _packs;
  final int generation;

  @override
  bool isSupported(Locale locale) => LocaleController.languages
      .any((entry) => entry.code == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) {
    final messages = _packs.messagesFor(locale.languageCode);
    if (messages != null) {
      return SynchronousFuture<AppLocalizations>(
        AppLocalizationsPack(locale, messages),
      );
    }
    if (LanguagePacks.bundled.contains(locale.languageCode)) {
      return SynchronousFuture<AppLocalizations>(
        lookupAppLocalizations(locale),
      );
    }
    return SynchronousFuture<AppLocalizations>(AppLocalizationsEn());
  }

  @override
  bool shouldReload(_PackDelegate old) => old.generation != generation;

  @override
  bool operator ==(Object other) =>
      other is _PackDelegate && other.generation == generation;

  @override
  int get hashCode => generation.hashCode;
}
