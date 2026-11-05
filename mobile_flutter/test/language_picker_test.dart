import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/language_packs.dart';
import 'package:mtl_trader_mobile/core/locale.dart';
import 'package:mtl_trader_mobile/ui/language_picker.dart';
import 'package:mtl_trader_mobile/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A published pack server: `/locales/manifest.json` plus one file per pack.
class _Server {
  final Map<String, String> bodies = <String, String>{};

  Future<String> get(Uri uri) async {
    final body = bodies[uri.path];
    if (body == null) throw StateError('not published: ${uri.path}');
    return body;
  }

  void manifest(List<Map<String, Object>> packs) {
    bodies['/locales/manifest.json'] = jsonEncode(<String, Object>{
      'packs': packs,
    });
  }

  void pack(String code, Map<String, String> messages, {int version = 1}) {
    bodies['/locales/$code.json'] = jsonEncode(<String, Object>{
      'code': code,
      'version': version,
      'messages': messages,
    });
  }
}

/// A miniature version of the root app: it listens to the controllers and
/// rebuilds, which is exactly what `MtlTraderApp` does.
Widget harness() => ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        LocaleController.instance,
        LanguagePacks.instance,
      ]),
      builder: (context, _) => MaterialApp(
        locale: LocaleController.instance.locale,
        supportedLocales: LocaleController.supported,
        localizationsDelegates: LanguagePacks.instance.delegates,
        theme: buildFlatTheme(AppPalette.dark),
        home: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: LanguagePicker(),
          ),
        ),
      ),
    );

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.expand_more));
  await tester.pumpAndSettle();
}

/// Opens the sheet and types a query, so a language far down the list is built
/// without depending on scroll position.
Future<void> search(WidgetTester tester, String query) async {
  await openSheet(tester);
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

void main() {
  late _Server server;

  setUp(() async {
    // Without a mock store the plugin channel never answers inside a widget
    // test, which makes `setLanguage` await forever.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    server = _Server();
    server.manifest(<Map<String, Object>>[
      <String, Object>{'code': 'fr', 'version': 2, 'bytes': 5120, 'keys': 3},
    ]);
    server.pack('fr', <String, String>{'language': 'Langue'});
    LanguagePacks.instance = LanguagePacks(fetch: server.get);
    await LocaleController.instance.setLanguage(null);
  });

  testWidgets('offers the device setting plus every shipped language', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('System'), findsOneWidget);

    await openSheet(tester);
    // English is compiled in, so its badge says so.
    expect(find.text('Built in'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'fran');
    await tester.pumpAndSettle();
    expect(find.text('Français'), findsOneWidget);
    // The badge states the size and the action in one place.
    expect(find.textContaining('Download · 5.0 KB'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'japan');
    await tester.pumpAndSettle();
    expect(find.text('日本語'), findsOneWidget);
    // No pack published: the row says so instead of pretending to download.
    expect(find.textContaining('English until translated'), findsOneWidget);
  });

  testWidgets('translated languages sort above the untranslated ones', (
    tester,
  ) async {
    // Tall enough that the first untranslated rows are built, so their
    // positions can be compared with the translated ones.
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Two translated languages, so the grouping is visible: German and French
    // have to beat Afrikaans even though the alphabet puts Afrikaans first.
    server.manifest(<Map<String, Object>>[
      <String, Object>{'code': 'fr', 'version': 2, 'bytes': 5120, 'keys': 3},
      <String, Object>{'code': 'de', 'version': 3, 'bytes': 7810, 'keys': 154},
    ]);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await openSheet(tester);

    // System row stays pinned first, then the translated languages, then the
    // untranslated list. 'System' is also on the card behind the sheet, so the
    // finders are scoped to the list. Rows whose native and English names match
    // (English, Afrikaans) carry that word twice, so titles are matched by their
    // heavier weight.
    final list = find.byType(ListView);
    Finder rowTitle(String label) => find.descendant(
      of: list,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == label &&
            widget.style?.fontWeight == FontWeight.w600,
      ),
    );
    double top(String label) => tester.getTopLeft(rowTitle(label)).dy;

    expect(top('System'), lessThan(top('Deutsch')));
    expect(top('Deutsch'), lessThan(top('Français')));
    expect(top('Français'), lessThan(top('Afrikaans')));
  });

  testWidgets('every catalogue language has a flag and no duplicates', (
    tester,
  ) async {
    final codes = LocaleController.languages.map((entry) => entry.code).toList();
    expect(codes.toSet().length, codes.length);
    expect(codes, containsAll(<String>['en', 'fr', 'es', 'ar', 'zh', 'hi']));
    for (final entry in LocaleController.languages) {
      expect(entry.flag.trim(), isNotEmpty, reason: entry.code);
      expect(entry.nativeName.trim(), isNotEmpty, reason: entry.code);
      expect(
        LocaleController.supported.any(
          (locale) => locale.languageCode == entry.code,
        ),
        isTrue,
        reason: '${entry.code} is not in supportedLocales',
      );
    }
  });

  testWidgets('downloading a language switches the interface to it', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);

    await search(tester, 'fran');
    await tester.tap(find.textContaining('Download · '));
    await tester.pumpAndSettle();

    expect(LanguagePacks.instance.isInstalled('fr'), isTrue);
    expect(LocaleController.instance.code, 'fr');
    // The card's own title changed, so this is the language switch, not just a
    // highlighted row.
    expect(find.text('Langue'), findsOneWidget);
    expect(find.text('Language'), findsNothing);
    expect(find.text('Français'), findsOneWidget);
    expect(find.text('🇫🇷'), findsOneWidget);
  });

  testWidgets('a language with no pack is still selectable in English', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await search(tester, 'deutsch');
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();

    expect(LocaleController.instance.code, 'de');
    expect(LanguagePacks.instance.isInstalled('de'), isFalse);
    // Dates and numbers follow German; the words stay English until translated.
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Deutsch'), findsOneWidget);
  });

  testWidgets('a failed download keeps the previous language', (tester) async {
    server.manifest(<Map<String, Object>>[
      <String, Object>{'code': 'fr', 'version': 2, 'bytes': 5120, 'keys': 3},
    ]);
    // Manifest promises French, but no pack body is published.
    server.bodies.remove('/locales/fr.json');

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await search(tester, 'fran');
    await tester.tap(find.textContaining('Download · '));
    await tester.pumpAndSettle();

    expect(LocaleController.instance.code, isNull);
    expect(LanguagePacks.instance.isInstalled('fr'), isFalse);
    expect(find.textContaining('Could not download this language'), findsOneWidget);
  });

  testWidgets('removing a downloaded pack falls back to the device', (
    tester,
  ) async {
    await LanguagePacks.instance.seed('fr', <String, String>{
      'language': 'Langue',
    });
    await LocaleController.instance.setLanguage('fr');

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('Langue'), findsOneWidget);

    // Search first: the list only builds visible rows, and Français sorts far
    // below the fold.
    await search(tester, 'fran');
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(LanguagePacks.instance.isInstalled('fr'), isFalse);
    expect(LocaleController.instance.code, isNull);
    expect(find.text('System'), findsWidgets);
  });
}
