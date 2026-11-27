import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mtl_trader_mobile/core/chart_magnet.dart';
import 'package:mtl_trader_mobile/core/chart_tools.dart';
import 'package:mtl_trader_mobile/ui/chart/drawings_sheet.dart';
import 'package:mtl_trader_mobile/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ToolFavourites', () {
    test('the strip starts with the four tools a trader reaches for first', () {
      expect(ToolFavourites.defaults, ['trend', 'ray', 'fib', 'long']);
      expect(ToolFavourites.defaults.length, ToolFavourites.max);
    });

    test('pinning adds, pinning again removes, and order is kept', () {
      var pinned = ToolFavourites.toggle(ToolFavourites.defaults, 'measure');
      expect(pinned.last, 'measure');
      // A fifth pin drops the oldest rather than refusing the tap.
      expect(pinned.length, ToolFavourites.max);
      expect(pinned, isNot(contains('trend')));

      pinned = ToolFavourites.toggle(pinned, 'measure');
      expect(pinned, isNot(contains('measure')));
      expect(pinned.length, ToolFavourites.max - 1);
    });

    test('a stored list loses ids this build does not have', () async {
      await ToolFavourites.save(['trend', 'gone', 'fib']);
      final loaded = await ToolFavourites.load({'trend', 'fib', 'measure'});
      expect(loaded, ['trend', 'fib']);
    });

    test('nothing usable in storage falls back to the defaults', () async {
      await ToolFavourites.save(['gone']);
      final loaded = await ToolFavourites.load({'trend', 'fib'});
      expect(loaded, ToolFavourites.defaults);
    });
  });

  group('DrawingsPanel', () {
    late List<String> picked;
    late List<bool> continuous;
    late List<MagnetMode> magnets;

    Future<void> pumpPanel(WidgetTester tester, {bool keep = false}) async {
      picked = [];
      continuous = [];
      magnets = [];
      // The whole sheet on one screen: the mode bar sits under five rows of
      // tools, which is past the default 800x600 test surface.
      tester.view.physicalSize = const Size(420, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildFlatTheme(AppPalette.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: DrawingsPanel(
                onPick: picked.add,
                keepDrawing: keep,
                onKeepDrawingChanged: continuous.add,
                magnet: MagnetMode.weak,
                onMagnetChanged: magnets.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('shows the pinned strip, the grid and both mode toggles',
        (tester) async {
      await pumpPanel(tester);

      expect(find.text('PINNED'), findsOneWidget);
      // A pinned tool appears twice: once in the strip, once in the grid.
      expect(find.text('Trend line'), findsNWidgets(2));
      expect(find.text('Magnet'), findsOneWidget);
      expect(find.text('Weak'), findsOneWidget);
      expect(find.text('Continuous'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('choosing a tool reports it and leaves the sheet to the chart',
        (tester) async {
      await pumpPanel(tester);

      // By icon, not by label: "Measure" is also a category pill, and tapping
      // that only filters the grid.
      await tester.tap(find.byIcon(Icons.straighten));
      await tester.pump();

      expect(picked, ['measure']);
      // Picking is not a mode change.
      expect(continuous, isEmpty);
      expect(magnets, isEmpty);

      await tester.tap(find.text('Rectangle'));
      await tester.pump();
      expect(picked, ['measure', 'rectangle']);
    });

    testWidgets('the Continuous toggle reflects a mode already set on the screen',
        (tester) async {
      await pumpPanel(tester, keep: true);

      expect(find.text('Continuous'), findsOneWidget);
      expect(find.text('On'), findsOneWidget);
      expect(find.text('Off'), findsNothing);
    });

    testWidgets('a panel with nobody listening shows no mode bar at all',
        (tester) async {
      tester.view.physicalSize = const Size(420, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildFlatTheme(AppPalette.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: DrawingsPanel(onPick: (_) {}),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Continuous'), findsNothing);
      expect(find.text('Magnet'), findsNothing);
    });

    testWidgets('the mode toggles report the next magnet and continuous state',
        (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('Magnet'));
      await tester.pump();
      expect(magnets, [MagnetMode.strong]);

      await tester.tap(find.text('Continuous'));
      await tester.pump();
      expect(continuous, [true]);
      expect(find.text('On'), findsOneWidget);
    });
  });
}
