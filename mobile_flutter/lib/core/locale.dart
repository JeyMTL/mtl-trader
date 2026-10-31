import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The UI language, remembered across launches.
///
/// Three states exist: follow the device, or an explicit English/French choice.
/// A null [code] means "follow the device", which is the default and the only
/// option that keeps working when a new language is added later.
class LocaleController extends ChangeNotifier {
  LocaleController._();

  static final LocaleController instance = LocaleController._();

  static const String storageKey = 'app.locale.v1';

  /// Languages the app ships translations for. The first one is the fallback.
  static const List<Locale> supported = <Locale>[Locale('en'), Locale('fr')];

  String? _code;

  /// Null means the device language decides.
  String? get code => _code;

  /// Passed to `MaterialApp.locale`; null lets Flutter resolve the device
  /// language against [supported].
  Locale? get locale => _code == null ? null : Locale(_code!);

  /// Native names, so the picker is readable whatever language is active.
  static const Map<String, String> nativeNames = <String, String>{
    'en': 'English',
    'fr': 'Français',
  };

  /// Reads the saved preference. Called once from `main` before `runApp`.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      instance._apply(prefs.getString(storageKey), notify: false);
    } catch (_) {
      // A missing or unreadable preference keeps following the device.
    }
  }

  /// Switches language, notifies the root and stores the choice.
  Future<void> setLanguage(String? code) async {
    if (code == _code) return;
    _apply(code, notify: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, code ?? '');
    } catch (_) {
      // The switch still applies for this session.
    }
  }

  void _apply(String? code, {required bool notify}) {
    _code =
        supported.any((locale) => locale.languageCode == code) ? code : null;
    _syncIntl();
    if (notify) notifyListeners();
  }

  /// `intl` formats dates and numbers with its own default locale, which is
  /// separate from Flutter's. Without this the app would be French but every
  /// month name would still be English.
  void _syncIntl() {
    Intl.defaultLocale = _code ?? _deviceLanguage();
  }

  static String _deviceLanguage() {
    final locales = WidgetsBinding.instance.platformDispatcher.locales;
    final first = locales.isEmpty ? null : locales.first.languageCode;
    if (first == null) return 'en';
    return supported.any((locale) => locale.languageCode == first)
        ? first
        : 'en';
  }
}
