import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One selectable language: its locale code, the name its own speakers use, the
/// English name for searching, and the flag shown beside it.
class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.nativeName,
    required this.englishName,
    required this.flag,
  });

  final String code;
  final String nativeName;
  final String englishName;

  /// Emoji flag. A language is not a country, so this is the flag most people
  /// associate with it, not a claim about where it is spoken.
  final String flag;
}

/// The UI language, remembered across launches.
///
/// Three states exist: follow the device, or an explicit choice from
/// [languages]. A null [code] means "follow the device", which is the default
/// and the only option that keeps working when a new language is added later.
class LocaleController extends ChangeNotifier {
  LocaleController._();

  static final LocaleController instance = LocaleController._();

  static const String storageKey = 'app.locale.v1';

  /// Every language the picker offers. English is compiled into the app;
  /// everything else is served from a downloaded pack when one is published.
  /// A language without a pack still resolves — dates, numbers and direction
  /// follow it, and untranslated strings fall back to English.
  ///
  /// Sorted by native name for the picker; English stays first as the fallback.
  static const List<AppLanguage> languages = <AppLanguage>[
    AppLanguage(code: 'en', nativeName: 'English', englishName: 'English', flag: '🇺🇸'),
    AppLanguage(code: 'fr', nativeName: 'Français', englishName: 'French', flag: '🇫🇷'),
    AppLanguage(code: 'af', nativeName: 'Afrikaans', englishName: 'Afrikaans', flag: '🇿🇦'),
    AppLanguage(code: 'sq', nativeName: 'Shqip', englishName: 'Albanian', flag: '🇦🇱'),
    AppLanguage(code: 'am', nativeName: 'አማርኛ', englishName: 'Amharic', flag: '🇪🇹'),
    AppLanguage(code: 'ar', nativeName: 'العربية', englishName: 'Arabic', flag: '🇸🇦'),
    AppLanguage(code: 'hy', nativeName: 'Հայերեն', englishName: 'Armenian', flag: '🇦🇲'),
    AppLanguage(code: 'az', nativeName: 'Azərbaycanca', englishName: 'Azerbaijani', flag: '🇦🇿'),
    AppLanguage(code: 'eu', nativeName: 'Euskara', englishName: 'Basque', flag: '🇪🇸'),
    AppLanguage(code: 'be', nativeName: 'Беларуская', englishName: 'Belarusian', flag: '🇧🇾'),
    AppLanguage(code: 'bn', nativeName: 'বাংলা', englishName: 'Bengali', flag: '🇧🇩'),
    AppLanguage(code: 'bs', nativeName: 'Bosanski', englishName: 'Bosnian', flag: '🇧🇦'),
    AppLanguage(code: 'bg', nativeName: 'Български', englishName: 'Bulgarian', flag: '🇧🇬'),
    AppLanguage(code: 'my', nativeName: 'မြန်မာ', englishName: 'Burmese', flag: '🇲🇲'),
    AppLanguage(code: 'ca', nativeName: 'Català', englishName: 'Catalan', flag: '🇦🇩'),
    AppLanguage(code: 'zh', nativeName: '中文', englishName: 'Chinese', flag: '🇨🇳'),
    AppLanguage(code: 'hr', nativeName: 'Hrvatski', englishName: 'Croatian', flag: '🇭🇷'),
    AppLanguage(code: 'cs', nativeName: 'Čeština', englishName: 'Czech', flag: '🇨🇿'),
    AppLanguage(code: 'da', nativeName: 'Dansk', englishName: 'Danish', flag: '🇩🇰'),
    AppLanguage(code: 'nl', nativeName: 'Nederlands', englishName: 'Dutch', flag: '🇳🇱'),
    AppLanguage(code: 'et', nativeName: 'Eesti', englishName: 'Estonian', flag: '🇪🇪'),
    AppLanguage(code: 'fil', nativeName: 'Filipino', englishName: 'Filipino', flag: '🇵🇭'),
    AppLanguage(code: 'fi', nativeName: 'Suomi', englishName: 'Finnish', flag: '🇫🇮'),
    AppLanguage(code: 'ka', nativeName: 'ქართული', englishName: 'Georgian', flag: '🇬🇪'),
    AppLanguage(code: 'de', nativeName: 'Deutsch', englishName: 'German', flag: '🇩🇪'),
    AppLanguage(code: 'el', nativeName: 'Ελληνικά', englishName: 'Greek', flag: '🇬🇷'),
    AppLanguage(code: 'gu', nativeName: 'ગુજરાતી', englishName: 'Gujarati', flag: '🇮🇳'),
    AppLanguage(code: 'ha', nativeName: 'Hausa', englishName: 'Hausa', flag: '🇳🇬'),
    AppLanguage(code: 'he', nativeName: 'עברית', englishName: 'Hebrew', flag: '🇮🇱'),
    AppLanguage(code: 'hi', nativeName: 'हिन्दी', englishName: 'Hindi', flag: '🇮🇳'),
    AppLanguage(code: 'hu', nativeName: 'Magyar', englishName: 'Hungarian', flag: '🇭🇺'),
    AppLanguage(code: 'is', nativeName: 'Íslenska', englishName: 'Icelandic', flag: '🇮🇸'),
    AppLanguage(code: 'ig', nativeName: 'Igbo', englishName: 'Igbo', flag: '🇳🇬'),
    AppLanguage(code: 'id', nativeName: 'Bahasa Indonesia', englishName: 'Indonesian', flag: '🇮🇩'),
    AppLanguage(code: 'ga', nativeName: 'Gaeilge', englishName: 'Irish', flag: '🇮🇪'),
    AppLanguage(code: 'it', nativeName: 'Italiano', englishName: 'Italian', flag: '🇮🇹'),
    AppLanguage(code: 'ja', nativeName: '日本語', englishName: 'Japanese', flag: '🇯🇵'),
    AppLanguage(code: 'kn', nativeName: 'ಕನ್ನಡ', englishName: 'Kannada', flag: '🇮🇳'),
    AppLanguage(code: 'kk', nativeName: 'Қазақша', englishName: 'Kazakh', flag: '🇰🇿'),
    AppLanguage(code: 'km', nativeName: 'ខ្មែរ', englishName: 'Khmer', flag: '🇰🇭'),
    AppLanguage(code: 'ko', nativeName: '한국어', englishName: 'Korean', flag: '🇰🇷'),
    AppLanguage(code: 'ku', nativeName: 'Kurdî', englishName: 'Kurdish', flag: '🇮🇶'),
    AppLanguage(code: 'lo', nativeName: 'ລາວ', englishName: 'Lao', flag: '🇱🇦'),
    AppLanguage(code: 'lv', nativeName: 'Latviešu', englishName: 'Latvian', flag: '🇱🇻'),
    AppLanguage(code: 'lt', nativeName: 'Lietuvių', englishName: 'Lithuanian', flag: '🇱🇹'),
    AppLanguage(code: 'mk', nativeName: 'Македонски', englishName: 'Macedonian', flag: '🇲🇰'),
    AppLanguage(code: 'ms', nativeName: 'Bahasa Melayu', englishName: 'Malay', flag: '🇲🇾'),
    AppLanguage(code: 'ml', nativeName: 'മലയാളം', englishName: 'Malayalam', flag: '🇮🇳'),
    AppLanguage(code: 'mt', nativeName: 'Malti', englishName: 'Maltese', flag: '🇲🇹'),
    AppLanguage(code: 'mr', nativeName: 'मराठी', englishName: 'Marathi', flag: '🇮🇳'),
    AppLanguage(code: 'mn', nativeName: 'Монгол', englishName: 'Mongolian', flag: '🇲🇳'),
    AppLanguage(code: 'ne', nativeName: 'नेपाली', englishName: 'Nepali', flag: '🇳🇵'),
    AppLanguage(code: 'nb', nativeName: 'Norsk bokmål', englishName: 'Norwegian', flag: '🇳🇴'),
    AppLanguage(code: 'fa', nativeName: 'فارسی', englishName: 'Persian', flag: '🇮🇷'),
    AppLanguage(code: 'pl', nativeName: 'Polski', englishName: 'Polish', flag: '🇵🇱'),
    AppLanguage(code: 'pt', nativeName: 'Português', englishName: 'Portuguese', flag: '🇵🇹'),
    AppLanguage(code: 'pa', nativeName: 'ਪੰਜਾਬੀ', englishName: 'Punjabi', flag: '🇮🇳'),
    AppLanguage(code: 'ro', nativeName: 'Română', englishName: 'Romanian', flag: '🇷🇴'),
    AppLanguage(code: 'ru', nativeName: 'Русский', englishName: 'Russian', flag: '🇷🇺'),
    AppLanguage(code: 'sr', nativeName: 'Српски', englishName: 'Serbian', flag: '🇷🇸'),
    AppLanguage(code: 'si', nativeName: 'සිංහල', englishName: 'Sinhala', flag: '🇱🇰'),
    AppLanguage(code: 'sk', nativeName: 'Slovenčina', englishName: 'Slovak', flag: '🇸🇰'),
    AppLanguage(code: 'sl', nativeName: 'Slovenščina', englishName: 'Slovenian', flag: '🇸🇮'),
    AppLanguage(code: 'so', nativeName: 'Soomaali', englishName: 'Somali', flag: '🇸🇴'),
    AppLanguage(code: 'es', nativeName: 'Español', englishName: 'Spanish', flag: '🇪🇸'),
    AppLanguage(code: 'sw', nativeName: 'Kiswahili', englishName: 'Swahili', flag: '🇰🇪'),
    AppLanguage(code: 'sv', nativeName: 'Svenska', englishName: 'Swedish', flag: '🇸🇪'),
    AppLanguage(code: 'ta', nativeName: 'தமிழ்', englishName: 'Tamil', flag: '🇮🇳'),
    AppLanguage(code: 'te', nativeName: 'తెలుగు', englishName: 'Telugu', flag: '🇮🇳'),
    AppLanguage(code: 'th', nativeName: 'ไทย', englishName: 'Thai', flag: '🇹🇭'),
    AppLanguage(code: 'tr', nativeName: 'Türkçe', englishName: 'Turkish', flag: '🇹🇷'),
    AppLanguage(code: 'uk', nativeName: 'Українська', englishName: 'Ukrainian', flag: '🇺🇦'),
    AppLanguage(code: 'ur', nativeName: 'اردو', englishName: 'Urdu', flag: '🇵🇰'),
    AppLanguage(code: 'uz', nativeName: 'Oʻzbekcha', englishName: 'Uzbek', flag: '🇺🇿'),
    AppLanguage(code: 'vi', nativeName: 'Tiếng Việt', englishName: 'Vietnamese', flag: '🇻🇳'),
    AppLanguage(code: 'yo', nativeName: 'Yorùbá', englishName: 'Yoruba', flag: '🇳🇬'),
    AppLanguage(code: 'zu', nativeName: 'isiZulu', englishName: 'Zulu', flag: '🇿🇦'),
  ];

  /// Flutter-resolvable locales, derived from the catalogue so the two can
  /// never disagree.
  static final List<Locale> supported =
      List<Locale>.unmodifiable(languages.map((entry) => Locale(entry.code)));

  /// The catalogue entry for a locale code, or null for "follow the device".
  static AppLanguage? languageFor(String? code) {
    if (code == null) return null;
    for (final entry in languages) {
      if (entry.code == code) return entry;
    }
    return null;
  }

  String? _code;

  /// Null means the device language decides.
  String? get code => _code;

  /// Passed to `MaterialApp.locale`; null lets Flutter resolve the device
  /// language against [supported].
  Locale? get locale => _code == null ? null : Locale(_code!);

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
