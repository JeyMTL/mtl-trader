import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AppColors.palette = AppPalette.dark;
  });

  test('the three palettes are distinct and readable', () {
    expect(AppPalette.all, hasLength(3));
    expect(AppPalette.dark.id, isNot(AppPalette.light.id));
    expect(AppPalette.blue.id, isNot(AppPalette.light.id));
    expect(AppPalette.dark.isLight, isFalse);
    expect(AppPalette.light.isLight, isTrue);
    // The blue theme is dark-based, so it has to stay dark: every
    // light-mode rule in the UI keys off this.
    expect(AppPalette.blue.isLight, isFalse);

    for (final palette in AppPalette.all) {
      final background = palette.background.computeLuminance();
      expect(
        (palette.text.computeLuminance() - background).abs(),
        greaterThan(0.4),
        reason: '${palette.id} body text',
      );
      expect(
        (palette.muted.computeLuminance() - background).abs(),
        greaterThan(0.15),
        reason: '${palette.id} muted text',
      );
      expect(
        (palette.primary.computeLuminance() -
                palette.surface.computeLuminance())
            .abs(),
        greaterThan(0.08),
        reason: '${palette.id} accent',
      );
    }
  });

  test('AppColors follows the activated palette', () {
    AppColors.palette = AppPalette.light;
    expect(AppColors.background, AppPalette.light.background);
    expect(AppColors.text, AppPalette.light.text);

    AppColors.palette = AppPalette.dark;
    expect(AppColors.background, AppPalette.dark.background);
    expect(AppColors.text, AppPalette.dark.text);
  });

  test('a fresh install starts on dark', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await ThemeController.restore();

    expect(ThemeController.instance.theme, AppTheme.dark);
    expect(AppColors.palette, AppPalette.dark);
  });

  test('an older stored theme is switched to dark once', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ThemeController.storageKey: 'light',
    });

    // The first launch after Dark became the default moves the install over.
    await ThemeController.restore();
    expect(ThemeController.instance.theme, AppTheme.dark);

    // A choice made after that is respected on the next launch.
    await ThemeController.instance.setTheme(AppTheme.light);
    AppColors.palette = AppPalette.dark;
    await ThemeController.restore();
    expect(ThemeController.instance.theme, AppTheme.light);
    expect(AppColors.palette.isLight, isTrue);

    // Leave the controller on the default so later tests start from a known
    // mode instead of inheriting this one.
    await ThemeController.instance.setTheme(AppTheme.dark);
  });

  test('a chosen mode survives a restart', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ThemeController.defaultAppliedKey: true,
    });

    await ThemeController.instance.setTheme(AppTheme.light);
    expect(AppColors.palette.isLight, isTrue);

    // Simulate the next cold start: palette back to default, then restore.
    AppColors.palette = AppPalette.dark;
    await ThemeController.restore();

    expect(ThemeController.instance.theme, AppTheme.light);
    expect(AppColors.palette.isLight, isTrue);
    expect(AppColors.background, AppPalette.light.background);
  });

  test('a blue choice survives a restart', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ThemeController.defaultAppliedKey: true,
    });

    await ThemeController.instance.setTheme(AppTheme.blue);
    expect(AppColors.palette, AppPalette.blue);

    AppColors.palette = AppPalette.dark;
    await ThemeController.restore();

    expect(ThemeController.instance.theme, AppTheme.blue);
    expect(AppColors.background, AppPalette.blue.background);
  });

  test('the built theme matches the palette brightness', () {
    expect(buildFlatTheme(AppPalette.dark).brightness, Brightness.dark);
    expect(buildFlatTheme(AppPalette.light).brightness, Brightness.light);
    expect(buildFlatTheme(AppPalette.blue).brightness, Brightness.dark);
    expect(
      buildFlatTheme(AppPalette.light).scaffoldBackgroundColor,
      AppPalette.light.background,
    );
  });
}
