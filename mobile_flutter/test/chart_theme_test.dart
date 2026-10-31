import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/chart_theme.dart';
import 'package:mtl_trader_mobile/core/indicators.dart';

void main() {
  test('round-trips a chart layout through JSON', () {
    final edited = ChartStyle.slate.copyWith(
      chartType: ChartType.area,
      studies: {OverlayStudy.sma20, OverlayStudy.ema21},
      studyPeriods: {'sma20': 9},
      showVolume: false,
      oscillator: Oscillator.rsi,
      rsiPeriod: 21,
      macdFast: 5,
      logScale: true,
    );

    final decoded = ChartStyle.decode(
      ChartStyle.encode(edited),
      fallback: ChartStyle.ink,
    );

    expect(decoded.id, 'slate');
    expect(decoded.chartType, ChartType.area);
    expect(decoded.studies, contains(OverlayStudy.sma20));
    expect(decoded.periodFor(OverlayStudy.sma20), 9);
    expect(decoded.periodFor(OverlayStudy.ema21), 21);
    expect(decoded.showVolume, isFalse);
    expect(decoded.oscillator, Oscillator.rsi);
    expect(decoded.rsiPeriod, 21);
    expect(decoded.macdFast, 5);
    expect(decoded.logScale, isTrue);
  });

  test('falls back for missing or corrupt layouts', () {
    expect(ChartStyle.decode(null, fallback: ChartStyle.paper).id, 'paper');
    expect(ChartStyle.decode('nope', fallback: ChartStyle.paper).id, 'paper');
    expect(ChartStyle.decode('[]', fallback: ChartStyle.mono).id, 'mono');
  });

  test('unknown presets keep the fallback while reading known fields', () {
    final decoded = ChartStyle.decode(
      '{"preset":"gone","logScale":true}',
      fallback: ChartStyle.ink,
    );
    expect(decoded.id, 'ink');
    expect(decoded.logScale, isTrue);
  });

  test('per-instrument storage keys are distinct', () {
    expect(ChartStyle.layoutKey('EURUSD'), isNot(ChartStyle.layoutKey('NAS100')));
    expect(ChartStyle.layoutKey('EURUSD'), contains('EURUSD'));
  });
}
