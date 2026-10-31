import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AppColors.palette = AppPalette.dark;
  });

  test('the two palettes are distinct and readable', () {
    expect(AppPalette.dark.id, isNot(AppPalette.light.id));
    expect(AppPalette.dark.isLight, isFalse);
    expect(AppPalette.light.isLight, isTrue);

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
        (palette.primary.computeLuminance() - palette.surface.computeLuminance())
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

  test('a chosen mode survives a restart', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await ThemeController.instance.setMode(ThemeMode.light);
    expect(AppColors.palette.isLight, isTrue);

    // Simulate the next cold start: palette back to default, then restore.
    AppColors.palette = AppPalette.dark;
    await ThemeController.restore();

    expect(ThemeController.instance.mode, ThemeMode.light);
    expect(AppColors.palette.isLight, isTrue);
    expect(AppColors.background, AppPalette.light.background);
  });

  test('the built theme matches the palette brightness', () {
    expect(buildFlatTheme(AppPalette.dark).brightness, Brightness.dark);
    expect(buildFlatTheme(AppPalette.light).brightness, Brightness.light);
    expect(
      buildFlatTheme(AppPalette.light).scaffoldBackgroundColor,
      AppPalette.light.background,
    );
  });
}
