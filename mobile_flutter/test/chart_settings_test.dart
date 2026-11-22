import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mtl_trader_mobile/core/instruments.dart';
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
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Appearance'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Chart type'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Grid'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Grid lines'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
