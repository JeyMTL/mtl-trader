import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/ui/chart/drawings_sheet.dart';

import 'package:mtl_trader_mobile/ui/theme.dart';

Widget panel({
  bool keep = false,
  ValueChanged<bool>? onKeep,
  void Function(String id)? onPick,
}) {
  return MaterialApp(
    theme: buildFlatTheme(AppColors.palette),
    home: Scaffold(
      // The real sheet scrolls; the panel is taller than a phone.
      body: SingleChildScrollView(
        child: DrawingsPanel(
          onPick: onPick ?? (_) {},
          keepDrawing: keep,
          onKeepDrawingChanged: onKeep,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the keep-drawing switch starts off and reports a flip',
      (tester) async {
    final values = <bool>[];
    await tester.pumpWidget(panel(onKeep: values.add));

    expect(find.text('Keep drawing'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(values, [true]);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('the switch reflects a lock already set on the screen',
      (tester) async {
    await tester.pumpWidget(panel(keep: true, onKeep: (_) {}));
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.byTooltip('Close'), findsNothing);
  });

  testWidgets('a panel with nobody listening hides the switch', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildFlatTheme(AppColors.palette),
        home: Scaffold(
          body: SingleChildScrollView(
            child: DrawingsPanel(onPick: (_) {}),
          ),
        ),
      ),
    );
    expect(find.text('Keep drawing'), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('picking a tool still hands its id back', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(panel(onPick: picked.add));

    await tester.tap(find.text('Rectangle'));
    await tester.pumpAndSettle();

    expect(picked, ['rectangle']);
  });
}
