import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mtl_trader_mobile/core/language_packs.dart';
import 'package:mtl_trader_mobile/core/locale.dart';
import 'package:mtl_trader_mobile/screens/login_screen.dart';
import 'package:mtl_trader_mobile/ui/a11y.dart';
import 'package:mtl_trader_mobile/ui/brand.dart';
import 'package:mtl_trader_mobile/ui/language_picker.dart';
import 'package:mtl_trader_mobile/ui/theme.dart';
import 'package:mtl_trader_mobile/ui/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The French strings exactly as published, read from the pack's ARB source.
Map<String, String> _packMessages(String code) {
  final decoded = jsonDecode(
    File('lib/l10n/packs/app_$code.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
  return <String, String>{
    for (final entry in decoded.entries)
      if (!entry.key.startsWith('@') && entry.value is String)
        entry.key: entry.value as String,
  };
}

/// Wraps a screen the way the real root does, with the system text size forced
/// to [scale].
Widget appHome(Widget home,
    {double scale = 1, Locale locale = const Locale('fr')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: LocaleController.supported,
    localizationsDelegates: LanguagePacks.instance.delegates,
    theme: buildFlatTheme(AppPalette.dark),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
      ),
      child: child!,
    ),
    home: home,
  );
}

/// The shared building blocks, filled with the longest strings the app
/// actually shows in French.
Widget gallery() => Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BrandMark(fontSize: 30, showDate: true),
            const SizedBox(height: 12),
            const SectionTitle(
              title: 'Résumé des performances',
              subtitle: 'Tous les trades clôturés du journal.',
            ),
            const SizedBox(height: 10),
            const Row(
              children: [
                Expanded(
                  child: MetricCard(
                    label: 'Facteur de profit',
                    value: '2.41',
                    foot: r'Brut $1,204.10 / $500.00',
                    semanticValue: r'Gain de $1,204.10',
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: MetricCard(
                    label: 'Taux de réussite',
                    value: '68.4%',
                    foot: '39 gagnants',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Pill(text: 'EN DRAWDOWN'),
                Pill(text: 'EURUSD', icon: Icons.euro),
              ],
            ),
            const SizedBox(height: 10),
            FlatCard(
              child: Column(
                children: [
                  const LabelValue(
                    label: 'Compte clôturé',
                    value: '31 octobre 2026',
                  ),
                  const ListDivider(),
                  LabelValue(
                    label: 'Net',
                    value: '',
                    trailing: const PnlText(value: -1234.5),
                  ),
                  const ListDivider(),
                  const LabelValue(
                    label: 'Notes jointes',
                    value: '3',
                    trailing: CountBadge(
                      icon: Icons.mic_none,
                      label: '3 notes vocales jointes',
                      count: 3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const EmptyState(
              title: 'Rien de consigné',
              body:
                  'Ouvrez un trade et ajoutez une capture ou une note vocale — '
                  "c'est la fiche que vous relirez.",
              icon: Icons.menu_book_outlined,
            ),
            const LanguagePicker(),
          ],
        ),
      ),
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
    // French is a downloadable pack now, so the harness installs it the way the
    // app does: the strings the published ARB carries, without a network.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LanguagePacks.instance = LanguagePacks(
      fetch: (uri) => Future<String>.error(StateError('offline')),
    );
    await LanguagePacks.instance.seed('fr', _packMessages('fr'));
  });

  testWidgets('shared widgets survive a 2x text scale without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(appHome(gallery(), scale: 2));
    // Not pumpAndSettle: the brand mark pulses forever, so the tree never
    // reaches a settled state. One laid-out frame is what an overflow needs.
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
  });

  testWidgets('the login screen survives a 2x text scale', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(appHome(const LoginScreen(), scale: 2));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    // The password reveal is icon-only, so its tooltip is the only label a
    // screen reader gets.
    expect(find.byTooltip('Afficher le mot de passe'), findsOneWidget);
  });

  testWidgets('nothing readable is drawn below the minimum label size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(appHome(gallery()));
    await tester.pump(const Duration(milliseconds: 400));

    final tooSmall = <String>[];
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final size = text.style?.fontSize;
      if (size == null) continue;
      if (size < kMinLabelSize) {
        tooSmall.add('"${text.data ?? ''}" at ${size}px');
      }
    }

    expect(
      tooSmall,
      isEmpty,
      reason:
          'Labels below kMinLabelSize (${kMinLabelSize}px): ${tooSmall.join(', ')}',
    );
  });

  testWidgets('a loss is announced as a loss, not just a red number', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      appHome(
        const Scaffold(
          body: Center(child: PnlText(value: -1234.5)),
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(r'Loss of $1,234.50'), findsOneWidget);
    // The sign and the arrow are both visible, so the meaning survives a
    // greyscale screenshot.
    expect(find.textContaining('▼'), findsOneWidget);
    expect(find.textContaining(r'-$1,234.50'), findsOneWidget);
    handle.dispose();
  });
}
