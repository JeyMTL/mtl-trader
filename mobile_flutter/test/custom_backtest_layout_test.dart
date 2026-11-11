import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/screens/custom_backtest_screen.dart';
import 'package:mtl_trader_mobile/ui/theme.dart';

void main() {
  testWidgets('the custom workbench fits the narrowest phone at 2x text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1400);
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
        home: const CustomBacktestScreen(symbol: 'EURUSD', timeframe: 'M15'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('Add chart'), findsOneWidget);
    expect(find.text('Voice note'), findsOneWidget);
  });
}
