import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/locale.dart';
import 'package:mtl_trader_mobile/l10n/gen/app_localizations.dart';
import 'package:mtl_trader_mobile/ui/language_picker.dart';
import 'package:mtl_trader_mobile/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A miniature version of the root app: it listens to the locale controller and
/// rebuilds, which is exactly what `MtlTraderApp` does.
Widget harness() => ListenableBuilder(
      listenable: LocaleController.instance,
      builder: (context, _) => MaterialApp(
        locale: LocaleController.instance.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: buildFlatTheme(AppPalette.dark),
        home: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: LanguagePicker(),
          ),
        ),
      ),
    );

void main() {
  setUp(() async {
    // Without a mock store the plugin channel never answers inside a widget
    // test, which makes `setLanguage` await forever.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocaleController.instance.setLanguage(null);
  });

  testWidgets('offers the device setting plus every shipped language', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('System'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Français'), findsOneWidget);
  });

  testWidgets('picking French repaints the whole surface in French', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);

    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();

    expect(LocaleController.instance.code, 'fr');
    // The card's own title changed, so this is the language switch, not just a
    // highlighted chip.
    expect(find.text('Langue'), findsOneWidget);
    expect(find.text('Language'), findsNothing);
  });

  testWidgets('choosing System returns to following the device',
      (tester) async {
    await LocaleController.instance.setLanguage('fr');
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('Langue'), findsOneWidget);

    await tester.tap(find.text('Système'));
    await tester.pumpAndSettle();

    expect(LocaleController.instance.code, isNull);
    expect(find.text('Language'), findsOneWidget);
  });
}
