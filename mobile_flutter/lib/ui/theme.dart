import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One concrete set of app colours.
///
/// Three palettes exist — [dark], [light] and [blue] — and [AppColors] reads
/// whichever one [ThemeController] has activated. The chart keeps a separate palette
/// (`ChartStyle`) on purpose: a light journal with a dark chart is a valid
/// preference, and the canvas needs candle colours the UI never uses.
@immutable
class AppPalette {
  const AppPalette({
    required this.id,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.borderStrong,
    required this.primary,
    required this.primaryLight,
    required this.ink,
    required this.success,
    required this.danger,
    required this.text,
    required this.muted,
    required this.faint,
  });

  final String id;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color borderStrong;

  /// Accent colour for buttons, pills and selection.
  final Color primary;

  /// Accent used for text on a dark background.
  final Color primaryLight;

  /// Text and icons drawn on top of [primary].
  final Color ink;

  final Color success;
  final Color danger;
  final Color text;
  final Color muted;
  final Color faint;

  bool get isLight => background.computeLuminance() > 0.5;

  static const AppPalette dark = AppPalette(
    id: 'dark',
    background: Color(0xFF080A0F),
    surface: Color(0xFF0F1218),
    surfaceAlt: Color(0xFF161A22),
    border: Color(0xFF242A36),
    borderStrong: Color(0xFF333B4B),
    primary: Color(0xFFD5A44E),
    primaryLight: Color(0xFFEBC57D),
    ink: Color(0xFF14100A),
    success: Color(0xFF45D29A),
    danger: Color(0xFFF26B78),
    text: Color(0xFFEDF0F5),
    muted: Color(0xFF98A1B0),
    faint: Color(0xFF6B7280),
  );

  /// Soft, low-contrast light theme: paper-grey background, white cards, and a
  /// deeper gold so the accent stays readable on white.
  static const AppPalette light = AppPalette(
    id: 'light',
    background: Color(0xFFF4F6F9),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEDF0F5),
    border: Color(0xFFDCE1E9),
    borderStrong: Color(0xFFC2C9D6),
    primary: Color(0xFF9A6E1F),
    primaryLight: Color(0xFF7C5814),
    ink: Color(0xFFFFFFFF),
    success: Color(0xFF0F7A57),
    danger: Color(0xFFB93441),
    text: Color(0xFF12161F),
    muted: Color(0xFF5A6372),
    faint: Color(0xFF8A94A3),
  );

  /// The mark's own palette: the icon's navy surfaces with its ice accent, so
  /// the journal can sit beside the logo instead of only in brass. Dark-based,
  /// so every light-mode assumption in the UI treats it as dark.
  static const AppPalette blue = AppPalette(
    id: 'blue',
    background: Color(0xFF071320),
    surface: Color(0xFF0C1C2B),
    surfaceAlt: Color(0xFF12293C),
    border: Color(0xFF1B3448),
    borderStrong: Color(0xFF2A4D67),
    primary: Color(0xFF57CCF7),
    primaryLight: Color(0xFF9BE4FF),
    ink: Color(0xFF04141F),
    success: Color(0xFF45D29A),
    danger: Color(0xFFF26B78),
    text: Color(0xFFE6F2FA),
    muted: Color(0xFF9AB1C4),
    faint: Color(0xFF6D879C),
  );

  static const List<AppPalette> all = <AppPalette>[dark, light, blue];
}

/// The app palette, resolved at runtime.
///
/// Everything in the UI reads `AppColors.x`, which forwards to the active
/// palette, so switching themes is a swap plus a rebuild — no call site needs a
/// `BuildContext`.
class AppColors {
  const AppColors._();

  /// Blue until the saved preference is read: it is the installed icon's
  /// palette, so a first launch already looks like the app.
  static AppPalette palette = AppPalette.blue;

  static Color get background => palette.background;
  static Color get surface => palette.surface;
  static Color get surfaceAlt => palette.surfaceAlt;
  static Color get border => palette.border;
  static Color get borderStrong => palette.borderStrong;
  static Color get primary => palette.primary;
  static Color get primaryLight => palette.primaryLight;
  static Color get ink => palette.ink;
  static Color get success => palette.success;
  static Color get danger => palette.danger;
  static Color get text => palette.text;
  static Color get muted => palette.muted;
  static Color get faint => palette.faint;
}

/// The appearance choices offered in Settings: the three palettes, plus
/// follow-the-device, which resolves to dark or light when it is chosen.
enum AppTheme { dark, light, blue, system }

/// The mark's blue / dark / light / follow-the-device, remembered across
/// launches.
///
/// Blue is the default because it is the app icon's own palette: a first launch
/// should look like the app that was installed.
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  static const String storageKey = 'app.theme.v1';

  /// Written the first time this build settles the default. It makes Blue the
  /// default for installs that picked Dark or Light before Blue was the
  /// default, without resetting the theme on every later launch.
  static const String defaultAppliedKey = 'app.theme.default.v2';

  AppTheme _theme = AppTheme.blue;

  AppTheme get theme => _theme;

  bool get isLight => AppColors.palette.isLight;

  /// Reads the saved preference. Called once from `main` before `runApp`.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // One-time switch: an install that stored Dark or Light before Blue
      // became the default would otherwise never see it. The marker means this
      // happens once, so the choice made after it still sticks.
      if (!(prefs.getBool(defaultAppliedKey) ?? false)) {
        await prefs.setBool(defaultAppliedKey, true);
        await prefs.setString(storageKey, AppTheme.blue.name);
        instance._apply(AppTheme.blue, notify: false);
        return;
      }

      instance._apply(_parse(prefs.getString(storageKey)), notify: false);
    } catch (_) {
      // A missing or unreadable preference keeps the blue default.
    }
  }

  /// Switches palette, notifies the root and stores the choice.
  Future<void> setTheme(AppTheme theme) async {
    if (theme == _theme) return;
    _apply(theme, notify: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, theme.name);
      // An explicit pick also settles the default, so a later restore can never
      // overwrite it with Blue.
      await prefs.setBool(defaultAppliedKey, true);
    } catch (_) {
      // The switch still applies for this session.
    }
  }

  void _apply(AppTheme theme, {required bool notify}) {
    _theme = theme;
    AppColors.palette = _paletteFor(theme);
    if (notify) notifyListeners();
  }

  /// [AppTheme.system] is resolved once, because the getters have no
  /// `BuildContext` to ask.
  static AppPalette _paletteFor(AppTheme theme) {
    switch (theme) {
      case AppTheme.dark:
        return AppPalette.dark;
      case AppTheme.light:
        return AppPalette.light;
      case AppTheme.blue:
        return AppPalette.blue;
      case AppTheme.system:
        break;
    }
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.light ? AppPalette.light : AppPalette.dark;
  }

  static AppTheme _parse(String? value) {
    switch (value) {
      case 'light':
        return AppTheme.light;
      case 'blue':
        return AppTheme.blue;
      case 'system':
        return AppTheme.system;
      default:
        return AppTheme.blue;
    }
  }
}

/// Shared corner radii, so cards, fields, chips and buttons stay in one
/// visual family instead of each screen inventing its own.
class AppRadius {
  const AppRadius._();

  static const double card = 14;
  static const double field = 12;
  static const double button = 12;
  static const double chip = 999;
  static const double sheet = 20;
}

/// Smallest font size used for a label a person has to read.
///
/// Anything below this was unreadable on a phone at arm's length and vanished
/// entirely under a system text-size bump. Chart axis ticks are allowed below
/// it: they are data, and the line's shape carries the meaning.
const double kMinLabelSize = 11;

enum Tone { positive, negative, neutral, muted }

Color toneColor(Tone tone) {
  switch (tone) {
    case Tone.positive:
      return AppColors.success;
    case Tone.negative:
      return AppColors.danger;
    case Tone.muted:
      return AppColors.faint;
    case Tone.neutral:
      return AppColors.text;
  }
}

ThemeData buildFlatTheme(AppPalette palette) {
  final scheme = ColorScheme.fromSeed(
    seedColor: palette.primary,
    brightness: palette.isLight ? Brightness.light : Brightness.dark,
  ).copyWith(
    primary: palette.primary,
    onPrimary: palette.ink,
    surface: palette.surface,
    onSurface: palette.text,
    surfaceContainerHighest: palette.surfaceAlt,
    outline: palette.border,
    error: palette.danger,
  );

  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.field),
    borderSide: BorderSide(color: palette.border),
  );
  final fieldFocused = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.field),
    borderSide: BorderSide(color: palette.primary, width: 1.3),
  );
  final fieldError = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.field),
    borderSide: BorderSide(color: palette.danger),
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Sora',
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: _FadeSlidePageTransitionsBuilder(),
        TargetPlatform.iOS: _FadeSlidePageTransitionsBuilder(),
        TargetPlatform.windows: _FadeSlidePageTransitionsBuilder(),
        TargetPlatform.macOS: _FadeSlidePageTransitionsBuilder(),
        TargetPlatform.linux: _FadeSlidePageTransitionsBuilder(),
        TargetPlatform.fuchsia: _FadeSlidePageTransitionsBuilder(),
      },
    ),
    brightness: palette.isLight ? Brightness.light : Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.background,
    dividerColor: palette.border,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background,
      foregroundColor: palette.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 58,
      titleTextStyle: TextStyle(
        color: palette.text,
        fontFamily: 'Sora',
        fontSize: 21,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      hintStyle: TextStyle(color: palette.faint, fontSize: 13.5),
      labelStyle: TextStyle(color: palette.muted, fontSize: 12.5),
      floatingLabelStyle: TextStyle(
        color: palette.primaryLight,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldFocused,
      errorBorder: fieldError,
      focusedErrorBorder: fieldError,
      errorStyle: TextStyle(color: palette.danger, fontSize: 11),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: palette.primary,
        foregroundColor: palette.ink,
        disabledBackgroundColor: palette.surfaceAlt,
        disabledForegroundColor: palette.faint,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        minimumSize: const Size.fromHeight(50),
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.text,
        side: BorderSide(color: palette.borderStrong),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        minimumSize: const Size.fromHeight(46),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.primary,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      // Translucent so the shell can frost whatever is scrolling behind it.
      backgroundColor: palette.surface.withAlpha(palette.isLight ? 226 : 208),
      indicatorColor: palette.primary.withAlpha(30),
      elevation: 0,
      height: 74,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: palette.muted,
        ),
      ),
      iconTheme: WidgetStatePropertyAll(
        IconThemeData(size: 22, color: palette.muted),
      ),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: palette.primary,
      foregroundColor: palette.ink,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.surfaceAlt,
      contentTextStyle: TextStyle(color: palette.text, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
    ),
  );
}

/// A short fade with a few pixels of upward travel, applied to every pushed
/// route. It reads as one continuous surface instead of a lateral slide, and
/// falls back to no motion when the device asks for reduced animation.
class _FadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
