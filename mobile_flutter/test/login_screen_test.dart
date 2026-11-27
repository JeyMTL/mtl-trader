import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mtl_trader_mobile/core/language_packs.dart';
import 'package:mtl_trader_mobile/core/locale.dart';
import 'package:mtl_trader_mobile/screens/login_screen.dart';
import 'package:mtl_trader_mobile/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The French strings exactly as published, read from the pack's ARB source.
Map<String, String> packMessages(String code) {
  final decoded = jsonDecode(
    File('lib/l10n/packs/app_$code.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
  return <String, String>{
    for (final entry in decoded.entries)
      if (!entry.key.startsWith('@') && entry.value is String)
        entry.key: entry.value as String,
  };
}

Widget appHome(Widget home, {double scale = 1}) {
  return MaterialApp(
    locale: const Locale('fr'),
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

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
    // French is a downloadable pack, so the harness installs it the way the app
    // does: the strings the published ARB carries, without a network.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LanguagePacks.instance = LanguagePacks(
      fetch: (uri) => Future<String>.error(StateError('offline')),
    );
    await LanguagePacks.instance.seed('fr', packMessages('fr'));
  });

  final fr = packMessages('fr');

  testWidgets('the intent switch comes before the Google route', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(appHome(const LoginScreen()));
    await tester.pump(const Duration(milliseconds: 400));

    // The card opens on Sign in / Create account; Google is offered after the
    // form, as an alternative to it rather than a step above it.
    // Both the tab and the CTA read "Se connecter"; the tab is the first in
    // the tree, the CTA is the ElevatedButton's label.
    final tabs = tester.getTopLeft(find.text(fr['signIn']!).first);
    final google = tester.getTopLeft(find.text(fr['continueWithGoogle']!));
    final primary = tester.getTopLeft(
      find.widgetWithText(ElevatedButton, fr['signIn']!).last,
    );

    expect(tabs.dy, lessThan(primary.dy));
    expect(primary.dy, lessThan(google.dy));
  });

  testWidgets('fits the narrowest phone at 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(appHome(const LoginScreen(), scale: 2));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    // The whole form stays reachable: the card scrolls, so the CTA only has to
    // exist, not be visible at rest.
    expect(find.text(fr['orSeparator']!), findsOneWidget);
    expect(find.text(fr['loginFooterEncrypted']!), findsOneWidget);
  });

  testWidgets('the password can be recovered from the screen itself', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(appHome(const LoginScreen()));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text(fr['forgotPassword']!));
    await tester.pumpAndSettle();

    expect(find.text(fr['resetTitle']!), findsOneWidget);
    expect(find.text(fr['resetSend']!), findsOneWidget);
  });

  testWidgets('creating an account swaps the footer for the confirmation note', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(appHome(const LoginScreen()));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(fr['loginFooterEncrypted']!), findsOneWidget);
    expect(find.text(fr['forgotPassword']!), findsOneWidget);

    await tester.tap(find.text(fr['createAccount']!));
    await tester.pumpAndSettle();

    expect(find.text(fr['loginFootnote']!), findsOneWidget);
    // Recovery belongs to sign-in; creating an account has no password yet.
    expect(find.text(fr['forgotPassword']!), findsNothing);
    expect(find.text(fr['loginFooterEncrypted']!), findsNothing);
  });
}
