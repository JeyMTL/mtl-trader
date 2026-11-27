import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mtl_trader_mobile/core/instruments.dart';
import 'package:mtl_trader_mobile/l10n/gen/app_localizations.dart';
import 'package:mtl_trader_mobile/screens/chart_picker_screen.dart';
import 'package:mtl_trader_mobile/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('rotating to landscape gives the chart the screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // A 640x320 landscape phone with doubled text: the shortest screen the app
    // runs on, which is where a stacked header would eat the candles.
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: buildFlatTheme(AppPalette.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: const ChartPickerScreen(
          instrument: Instrument(
            'EURUSD',
            'Euro / US Dollar',
            'EURUSD=X',
            InstrumentKind.forex,
            5,
          ),
          direction: 'BUY',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // The app bar is gone: landscape is the analysis view, not a page.
    expect(find.byType(AppBar), findsNothing);
    // Every tool is still one tap away, in the rail.
    expect(find.byTooltip('Drawing tools'), findsOneWidget);
    expect(find.byTooltip('Time frame'), findsOneWidget);
    expect(find.byTooltip('Chart style'), findsOneWidget);
    expect(find.byTooltip('Market replay'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chart settings open, page in and come back at 2x text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: buildFlatTheme(AppPalette.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: const ChartPickerScreen(
          instrument: Instrument(
            'EURUSD',
            'Euro / US Dollar',
            'EURUSD=X',
            InstrumentKind.forex,
            5,
          ),
          direction: 'BUY',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Chart style'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Chart settings'), findsOneWidget);
    // The shell: ten tabs above the page, Cancel and Apply fixed below it.
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
    expect(find.text('Grid lines'), findsNothing);
    expect(tester.takeException(), isNull);

    // The strip scrolls sideways: at 2x text the third tab is already past the
    // right edge, so it has to be dragged into reach first.
    // Ten tabs are wider than a 320pt phone at 2x text: the strip is scrolled
    // in steps until the wanted tab can actually be tapped, which is the same
    // thing a thumb does.
    Future<void> openTab(String label) async {
      final strip = find
          .byWidgetPredicate(
            (widget) =>
                widget is ListView && widget.scrollDirection == Axis.horizontal,
          )
          .last;
      for (var step = 0; step < 12; step++) {
        if (find.text(label).hitTestable().evaluate().isNotEmpty) break;
        await tester.drag(strip, const Offset(-80, 0));
        await tester.pump();
      }
      await tester.tap(find.text(label).hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await openTab('Appearance');
    // 'Chart type' sits below the theme swatches and is not built yet on a
    // short page, so the page's first group is the proof the tab switched.
    expect(find.text('THEME'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await openTab('Grid');
    expect(find.text('Grid lines'), findsOneWidget);
    // No back chevron any more: Cancel is the way out and it discards.
    expect(find.byTooltip('Back'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
