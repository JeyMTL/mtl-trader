import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/chart_drawings.dart';
import 'package:mtl_trader_mobile/ui/chart/object_settings.dart';

/// A rectangle with two anchors, which is the object the trader complained had
/// nothing to edit but its levels.
final ChartDrawing _rect = ChartDrawing.points(
  kind: DrawingKind.rectangle,
  points: const [
    ChartPoint(ms: 1762899000000, price: 1.25000),
    ChartPoint(ms: 1762900600000, price: 1.26000),
  ],
);

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showObjectSettings(
                context,
                drawing: _rect,
                title: 'Rectangle',
                decimals: 5,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a rectangle offers style and coordinates, not just levels',
      (tester) async {
    await _open(tester);

    expect(find.text('Style'), findsOneWidget);
    expect(find.text('Coordinates'), findsOneWidget);
    // A shape can carry a label, the way TradingView puts words on a zone.
    expect(find.text('Text'), findsOneWidget);

    // The controls that were missing entirely.
    expect(find.text('Width'), findsOneWidget);
    expect(find.text('Line style'), findsOneWidget);
    expect(find.text('Fill'), findsOneWidget);
    expect(find.text('Lock'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);

    // And the two anchors are editable by price, with their times on screen.
    await tester.tap(find.text('Coordinates'));
    await tester.pumpAndSettle();
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('1.25000'), findsOneWidget);
    expect(find.text('1.26000'), findsOneWidget);
  });

  testWidgets('Ok returns the restyled object', (tester) async {
    ObjectSettingsResult? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  answer = await showObjectSettings(
                    context,
                    drawing: _rect,
                    title: 'Rectangle',
                    decimals: 5,
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

    await tester.ensureVisible(find.text('3px'));
    await tester.tap(find.text('3px'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Dashed'));
    await tester.tap(find.text('Dashed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ok'));
    await tester.pumpAndSettle();

    expect(answer, isNotNull);
    expect(answer!.drawing!.look.weight, 3);
    expect(answer!.drawing!.look.dashed, isTrue);
    // Geometry is untouched by a restyle.
    expect(answer!.drawing!.points.first.price, closeTo(1.25, 1e-9));
  });

  testWidgets('Cancel changes nothing, even after edits', (tester) async {
    ObjectSettingsResult? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  answer = await showObjectSettings(
                    context,
                    drawing: _rect,
                    title: 'Rectangle',
                    decimals: 5,
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

    await tester.ensureVisible(find.text('2px'));
    await tester.tap(find.text('2px'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(answer, isNull);
  });

  testWidgets('a position offers its side and its levels', (tester) async {
    final position = ChartDrawing.position(
      side: PositionSide.long,
      startMs: 1762899000000,
      entry: 1.25,
      stop: 1.248,
      target: 1.256,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showObjectSettings(
                  context,
                  drawing: position,
                  title: 'Long position',
                  decimals: 5,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coordinates'));
    await tester.pumpAndSettle();

    expect(find.text('Long'), findsOneWidget);
    expect(find.text('Short'), findsOneWidget);
    expect(find.text('Entry'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Target'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);
  });

  testWidgets('the sheet fits a small phone at 2x text', (tester) async {
    tester.view.physicalSize = const Size(320 * 2, 568 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        // The real view, with only the text size scaled: a bare MediaQueryData
        // would report a zero-size window and the sheet would measure to nothing.
        data: MediaQueryData.fromView(tester.view)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showObjectSettings(
                    context,
                    drawing: _rect,
                    title: 'Rectangle',
                    decimals: 5,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Style is the first tab, and it is the one with the most controls on it.
    expect(tester.takeException(), isNull);
    expect(find.text('Width'), findsOneWidget);

    final coordinates = find.byKey(const ValueKey<String>('object-tab-1'));
    await tester.ensureVisible(coordinates);
    await tester.tap(coordinates);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('#2'), findsOneWidget);
  });

  testWidgets('a label typed on a rectangle comes back with it', (tester) async {
    ObjectSettingsResult? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  answer = await showObjectSettings(
                    context,
                    drawing: _rect,
                    title: 'Rectangle',
                    decimals: 5,
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

    await tester.tap(find.widgetWithText(InkWell, 'Text'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Supply, hold above');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ok'));
    await tester.pumpAndSettle();

    expect(answer!.drawing!.text, 'Supply, hold above');
    // The geometry is still the rectangle it was.
    expect(answer!.drawing!.points.length, 2);
  });

  testWidgets('a dotted line is one line style, not two', (tester) async {
    ObjectSettingsResult? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  answer = await showObjectSettings(
                    context,
                    drawing: _rect,
                    title: 'Rectangle',
                    decimals: 5,
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

    await tester.ensureVisible(find.text('Dashed'));
    await tester.tap(find.text('Dashed'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Dotted'));
    await tester.tap(find.text('Dotted'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ok'));
    await tester.pumpAndSettle();

    expect(answer!.drawing!.look.dotted, isTrue);
    expect(answer!.drawing!.look.dashed, isFalse);
  });

  testWidgets('a text object gets its words back', (tester) async {
    final label = ChartDrawing.points(
      kind: DrawingKind.text,
      text: 'Wait for the retest',
      points: const [ChartPoint(ms: 1762899000000, price: 1.25)],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showObjectSettings(
                  context,
                  drawing: label,
                  title: 'Text',
                  decimals: 5,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Text').last);
    await tester.pumpAndSettle();
    expect(find.text('Wait for the retest'), findsOneWidget);
  });
}
