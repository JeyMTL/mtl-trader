import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('the gold action dips under the finger and comes back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(appHome(const LoginScreen()));
    await tester.pump(const Duration(milliseconds: 400));

    // The nearest AnimatedScale above the button is the press wrapper; the
    // card's own is further up and never moves here.
    final scale = find
        .ancestor(
          of: find.byType(ElevatedButton),
          matching: find.byType(AnimatedScale),
        )
        .first;

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ElevatedButton)),
    );
    await tester.pump(const Duration(milliseconds: 130));
    expect(tester.widget<AnimatedScale>(scale).scale, 0.98);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 130));
    expect(tester.widget<AnimatedScale>(scale).scale, 1);
  });

  testWidgets('submitting ticks the phone, refusals tick it differently', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final haptics = <Object?>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(appHome(const LoginScreen()));
    await tester.pump(const Duration(milliseconds: 400));

    // Empty form: the press lands, so it ticks — a selection click, not the
    // impact that would claim the request went out.
    await tester.tap(find.widgetWithText(ElevatedButton, fr['signIn']!).last);
    await tester.pump();
    expect(haptics, ['HapticFeedbackType.selectionClick']);

    // A filled form is a real submit: light impact, even though this harness has
    // no Supabase to send it to.
    haptics.clear();
    await tester.enterText(
      find.widgetWithText(TextFormField, fr['emailLabel']!).first,
      'trader@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, fr['passwordLabel']!).first,
      'correct horse',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, fr['signIn']!).last);
    await tester.pump();
    expect(haptics, ['HapticFeedbackType.lightImpact']);
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
