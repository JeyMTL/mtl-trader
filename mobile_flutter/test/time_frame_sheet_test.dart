import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mtl_trader_mobile/core/instruments.dart';
import 'package:mtl_trader_mobile/screens/chart_picker_screen.dart';
import 'package:mtl_trader_mobile/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping the time frame card opens the picker', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // Pinned portrait on purpose: the default test surface is 800x600, which is
    // landscape, and landscape now opens the chart instead of this screen.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildFlatTheme(AppPalette.dark),
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

    await tester.tap(find.text('Live · newest candles'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // The sheet is titled "Time frame" with a LIVE badge beside it; the longer
    // "Chart time frame" header was dropped when the picker became one list.
    expect(find.text('Time frame'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
