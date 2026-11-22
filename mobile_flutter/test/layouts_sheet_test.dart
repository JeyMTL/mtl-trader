import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mtl_trader_mobile/core/chart_layouts.dart';
import 'package:mtl_trader_mobile/core/chart_theme.dart';
import 'package:mtl_trader_mobile/ui/chart/layouts_sheet.dart';

ChartLayout entry(
  String id,
  String name, {
  String symbol = 'EURUSD',
  bool starred = false,
}) {
  return ChartLayout(
    id: id,
    name: name,
    symbol: symbol,
    intervalKey: '1m',
    style: ChartStyle.slate,
    savedAt: DateTime(2026, 11, 20, 14, 46),
    starred: starred,
  );
}

/// Holds the sheet's answer after it closes, so a test can tap a row and then
/// read what came back.
class Answer {
  LayoutsResult? result;
}

Future<Answer> open(
  WidgetTester tester, {
  required List<ChartLayout> layouts,
  String? activeId,
}) async {
  final answer = Answer();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                answer.result = await showLayoutsManager(
                  context,
                  layouts: layouts,
                  activeId: activeId,
                  currentSymbol: 'EURUSD',
                  currentIntervalKey: '1m',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return answer;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lists the layouts with their metadata', (tester) async {
    await open(
      tester,
      layouts: [entry('a', 'JeyMTL'), entry('b', 'dxy', symbol: 'DXY')],
    );

    expect(find.text('Layouts'), findsOneWidget);
    expect(find.text('LAYOUT NAME'), findsOneWidget);
    expect(find.text('JeyMTL'), findsOneWidget);
    expect(find.text('dxy'), findsOneWidget);
    // The subtitle is the spec's own format.
    expect(find.text('EURUSD, 1m (20 Nov 2026, 14:46)'), findsOneWidget);
    expect(find.text('DXY, 1m (20 Nov 2026, 14:46)'), findsOneWidget);
  });

  testWidgets('search filters the list as it is typed', (tester) async {
    await open(
      tester,
      layouts: [entry('a', 'JeyMTL'), entry('b', 'dxy', symbol: 'DXY')],
    );

    await tester.enterText(find.byType(TextField), 'dx');
    await tester.pumpAndSettle();

    expect(find.text('dxy'), findsOneWidget);
    expect(find.text('JeyMTL'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.textContaining('No layout matches'), findsOneWidget);
  });

  testWidgets('tapping a row opens that layout', (tester) async {
      final answer = await open(
      tester,
      layouts: [entry('a', 'JeyMTL'), entry('b', 'dxy')],
    );

    await tester.tap(find.text('JeyMTL'));
    await tester.pumpAndSettle();

    expect(answer.result, isNotNull);
    expect(answer.result!.layout?.id, 'a');
  });

  testWidgets('the star is a toggle, saved straight away', (tester) async {
    final answer = await open(tester, layouts: [entry('a', 'JeyMTL')]);
    expect(answer.result, isNull);

    await tester.tap(find.byTooltip('Star'));
    await tester.pumpAndSettle();

    final stored = await ChartLayoutStore.load();
    expect(stored, hasLength(1));
    expect(stored.first.starred, isTrue);
    expect(find.byTooltip('Unstar'), findsOneWidget);
  });

  testWidgets('deleting asks first, then hands the removal back', (tester) async {
    final answer = await open(tester, layouts: [entry('a', 'JeyMTL')]);

    await tester.tap(find.byTooltip('Delete JeyMTL'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this layout?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('JeyMTL'), findsNothing);
    expect(answer.result, isNull);
    expect(await ChartLayoutStore.load(), isEmpty);
  });

  testWidgets('an empty library explains how to fill it', (tester) async {
    await open(tester, layouts: const []);
    expect(find.textContaining('No saved layouts yet'), findsOneWidget);
    expect(find.text('Save this chart as a layout'), findsOneWidget);
  });
}
