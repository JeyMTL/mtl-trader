import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const Color background = Color(0xFF080A0F);
  static const Color surface = Color(0xFF0F1218);
  static const Color surfaceAlt = Color(0xFF161A22);
  static const Color border = Color(0xFF242A36);
  static const Color borderStrong = Color(0xFF333B4B);

  static const Color primary = Color(0xFFD5A44E);
  static const Color primaryLight = Color(0xFFEBC57D);
  static const Color ink = Color(0xFF14100A);

  static const Color success = Color(0xFF45D29A);
  static const Color danger = Color(0xFFF26B78);
  static const Color text = Color(0xFFEDF0F5);
  static const Color muted = Color(0xFF98A1B0);
  static const Color faint = Color(0xFF6B7280);
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

ThemeData buildFlatTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.primary,
    onPrimary: AppColors.ink,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    surfaceContainerHighest: AppColors.surfaceAlt,
    outline: AppColors.border,
    error: AppColors.danger,
  );

  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.field),
    borderSide: const BorderSide(color: AppColors.border),
  );
  final fieldFocused = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.field),
    borderSide: const BorderSide(color: AppColors.primary, width: 1.3),
  );
  final fieldError = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.field),
    borderSide: const BorderSide(color: AppColors.danger),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    dividerColor: AppColors.border,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 58,
      titleTextStyle: TextStyle(
        color: AppColors.text,
        fontSize: 21,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      hintStyle: const TextStyle(color: AppColors.faint, fontSize: 13.5),
      labelStyle: const TextStyle(color: AppColors.muted, fontSize: 12.5),
      floatingLabelStyle: const TextStyle(
        color: AppColors.primaryLight,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldFocused,
      errorBorder: fieldError,
      focusedErrorBorder: fieldError,
      errorStyle: const TextStyle(color: AppColors.danger, fontSize: 11),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.ink,
        disabledBackgroundColor: AppColors.surfaceAlt,
        disabledForegroundColor: AppColors.faint,
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
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.borderStrong),
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
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primary.withAlpha(30),
      elevation: 0,
      height: 74,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      iconTheme: const WidgetStatePropertyAll(IconThemeData(size: 22)),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.ink,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceAlt,
      contentTextStyle: const TextStyle(color: AppColors.text, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
    ),
  );
}
