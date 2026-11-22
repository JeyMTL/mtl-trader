import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/chart_magnet.dart';
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

  test('a canvas colour of its own survives a save', () {
    final edited = ChartStyle.ink.copyWith(background: const Color(0xFF0E1016));
    final decoded = ChartStyle.decode(ChartStyle.encode(edited));

    // Shared through the same JSON the web desk writes, so a template made
    // there lands on a canvas the phone can paint.
    expect(decoded.background, const Color(0xFF0E1016));
    expect(ChartStyle.decode(ChartStyle.encode(edited)).toJson()['background'],
        0xFF0E1016);
  });

  test('the symbol and scale switches survive a save', () {
    final edited = ChartStyle.slate.copyWith(
      colorBarsByPrevClose: true,
      showCandleBody: false,
      showCandleBorder: false,
      showCandleWick: false,
      precision: 3,
      showAxisPlus: false,
      showCountdown: true,
      dayOfWeekLabels: true,
      use24Hour: false,
      magnet: MagnetMode.strong,
    );

    final decoded = ChartStyle.decode(ChartStyle.encode(edited));

    expect(decoded.colorBarsByPrevClose, isTrue);
    expect(decoded.showCandleBody, isFalse);
    expect(decoded.showCandleBorder, isFalse);
    expect(decoded.showCandleWick, isFalse);
    expect(decoded.precision, 3);
    expect(decoded.showAxisPlus, isFalse);
    expect(decoded.showCountdown, isTrue);
    expect(decoded.dayOfWeekLabels, isTrue);
    expect(decoded.use24Hour, isFalse);
    // The magnet travels with the instrument: reopening a chart must not put a
    // trader back on the weak magnet they replaced.
    expect(decoded.magnet, MagnetMode.strong);
  });

  test('the canvas gradient and crosshair survive a save', () {
    final edited = ChartStyle.slate.copyWith(
      backgroundTo: const Color(0xFF101421),
      crosshairWidth: 2,
      crosshairStyle: CrosshairStyle.dotted,
    );
    final decoded = ChartStyle.decode(ChartStyle.encode(edited));

    expect(decoded.backgroundTo, const Color(0xFF101421));
    expect(decoded.crosshairWidth, 2);
    expect(decoded.crosshairStyle, CrosshairStyle.dotted);
    // A preset that never touched the crosshair keeps the desktop default.
    expect(
      ChartStyle.decode(ChartStyle.encode(ChartStyle.ink)).crosshairStyle,
      CrosshairStyle.dashed,
    );
  });

  test('alert line colours and the active-only filter survive a save', () {
    final edited = ChartStyle.slate.copyWith(
      alertUp: const Color(0xFFFFB020),
      alertDown: const Color(0xFF7C4DFF),
      onlyActiveAlerts: true,
    );
    final decoded = ChartStyle.decode(ChartStyle.encode(edited));

    expect(decoded.alertUp, const Color(0xFFFFB020));
    expect(decoded.alertDown, const Color(0xFF7C4DFF));
    expect(decoded.onlyActiveAlerts, isTrue);
    // An untouched chart leaves alert lines on the candle pair.
    expect(ChartStyle.ink.alertUp, isNull);
    expect(ChartStyle.ink.onlyActiveAlerts, isFalse);
  });

  test('a flat canvas clears the gradient colour', () {
    final gradient =
        ChartStyle.slate.copyWith(backgroundTo: const Color(0xFF101421));
    expect(gradient.copyWith(clearBackgroundTo: true).backgroundTo, isNull);
    expect(
      ChartStyle.decode(ChartStyle.encode(gradient)).backgroundTo,
      const Color(0xFF101421),
    );
  });

  test('a gradient is judged light or dark by both of its stops', () {
    expect(
      ChartStyle.paper.copyWith(backgroundTo: const Color(0xFFE8EBF0)).isLight,
      isTrue,
    );
    expect(
      ChartStyle.slate.copyWith(backgroundTo: const Color(0xFF0B0E14)).isLight,
      isFalse,
    );
  });

  test('precision goes back to the instrument when told to clear', () {
    final pinned = ChartStyle.ink.copyWith(precision: 2);
    expect(pinned.copyWith(clearPrecision: true).precision, isNull);
    // A copyWith that does not mention precision leaves it alone.
    expect(pinned.copyWith(logScale: true).precision, 2);
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

  test('the green/black candle scheme is offered', () {
    expect(ChartStyle.presets.map((preset) => preset.id), contains('classic'));
    expect(ChartStyle.classic.bull, const Color(0xFF4CAF50));
    expect(ChartStyle.classic.bear, const Color(0xFF131722));
    expect(ChartStyle.classic.isLight, isTrue);
    // The style sheet picks colours from the palette, so black must be in it.
    expect(ChartStyle.candlePalette, contains(const Color(0xFF131722)));
  });

  test('per-instrument storage keys are distinct', () {
    expect(
        ChartStyle.layoutKey('EURUSD'), isNot(ChartStyle.layoutKey('NAS100')));
    expect(ChartStyle.layoutKey('EURUSD'), contains('EURUSD'));
  });
}
