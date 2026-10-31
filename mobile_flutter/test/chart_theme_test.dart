import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/chart_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('presets are unique and cover both dark and light canvases', () {
    final ids = ChartStyle.presets.map((style) => style.id).toSet();
    expect(ids.length, ChartStyle.presets.length);
    expect(ChartStyle.presets.any((style) => style.isLight), isTrue);
    expect(ChartStyle.presets.any((style) => !style.isLight), isTrue);
  });

  test('every preset keeps the bars visible against its background', () {
    for (final style in ChartStyle.presets) {
      final background = style.background.computeLuminance();
      expect(style.bull, isNot(style.bear), reason: style.id);
      expect(
        (style.bull.computeLuminance() - background).abs(),
        greaterThan(0.15),
        reason: '${style.id} bull',
      );
      expect(
        (style.bear.computeLuminance() - background).abs(),
        greaterThan(0.15),
        reason: '${style.id} bear',
      );
      expect(
        (style.text.computeLuminance() - background).abs(),
        greaterThan(0.1),
        reason: '${style.id} text',
      );
    }
  });

  test('copyWith recolours one side and leaves the rest alone', () {
    final custom = ChartStyle.slate.copyWith(
      bull: ChartStyle.candlePalette.first,
      showGrid: false,
    );

    expect(custom.id, ChartStyle.slate.id);
    expect(custom.name, ChartStyle.slate.name);
    expect(custom.background, ChartStyle.slate.background);
    expect(custom.bull, ChartStyle.candlePalette.first);
    expect(custom.bear, ChartStyle.slate.bear);
    expect(custom.showGrid, isFalse);
    expect(custom.showCrosshair, ChartStyle.slate.showCrosshair);
    // The preset itself is untouched, so the sheet can still reset to it.
    expect(ChartStyle.slate.showGrid, isTrue);
  });

  test('a chosen style carries over to the next chart screen', () {
    addTearDown(() => ChartStyle.current = ChartStyle.ink);

    ChartStyle.current = ChartStyle.paper;
    expect(ChartStyle.current.id, 'paper');
    expect(ChartStyle.current.isLight, isTrue);
  });

  test('a saved style survives a restart', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    addTearDown(() => ChartStyle.current = ChartStyle.ink);

    ChartStyle.current = ChartStyle.paper.copyWith(
      bull: ChartStyle.candlePalette[2],
      showGrid: false,
    );
    await ChartStyle.save();

    // Simulate the next cold start.
    ChartStyle.current = ChartStyle.ink;
    await ChartStyle.restore();

    expect(ChartStyle.current.id, 'paper');
    expect(ChartStyle.current.bull, ChartStyle.candlePalette[2]);
    expect(ChartStyle.current.showGrid, isFalse);
    expect(ChartStyle.current.showCrosshair, ChartStyle.paper.showCrosshair);
  });

  test('an unreadable saved style keeps the default instead of throwing', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{
      ChartStyle.storageKey: 'not json',
    });
    addTearDown(() => ChartStyle.current = ChartStyle.ink);

    ChartStyle.current = ChartStyle.slate;
    await ChartStyle.restore();

    expect(ChartStyle.current.id, 'slate');
  });
}
