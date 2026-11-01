// Chart paint benchmark — not part of the suite (no `_test.dart` suffix).
//
//   flutter test test/perf/chart_paint_benchmark.dart
//
// Times the painter's real work through a PictureRecorder at a 90-candle window
// inside a fully loaded 5,000-candle series.
//
// Reports the MEDIAN of five interleaved rounds of 100 frames, not a single
// average, because this machine's single-run spread turned out to be wider than
// the differences between layers (see the numbers below). A figure that moves by
// hundreds of microseconds between identical runs cannot justify an optimisation
// on its own.
//
// Host-side only: display-list building, no rasterisation. Use it for A/B on the
// same machine, not as a prediction of a phone's frame time — the in-app overlay
// (Account → Diagnostics) is what measures a real handset.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/chart_theme.dart';
import 'package:mtl_trader_mobile/screens/chart_picker_screen.dart';
import 'package:mtl_trader_mobile/services/market_data.dart';

List<Candle> series(int count) {
  final start = DateTime.utc(2026, 9, 1);
  var price = 1.0850;
  final out = <Candle>[];
  for (var i = 0; i < count; i++) {
    final drift = (i % 17) - 8;
    final open = price;
    final close = open + drift * 0.00001;
    out.add(
      Candle(
        time: start.add(Duration(minutes: 15 * i)),
        open: open,
        high: close + 0.00005,
        low: open - 0.00005,
        close: close,
        volume: 800 + (i % 40) * 12,
      ),
    );
    price = close;
  }
  return out;
}

const Size kSize = Size(392, 380);
const int kFrames = 100;
const int kRounds = 5;

double timePaint(
  List<Candle> candles,
  double low,
  double high,
  ChartStyle style,
) {
  final painter = debugChartPainter(
    candles: candles,
    start: candles.length - 90,
    span: 90,
    minPrice: low,
    maxPrice: high,
    decimals: 5,
    interval: ChartInterval.fifteenMinutes,
    style: style,
  );

  void once() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, kSize);
    recorder.endRecording().dispose();
  }

  for (var i = 0; i < 20; i++) {
    once();
  }
  final watch = Stopwatch()..start();
  for (var i = 0; i < kFrames; i++) {
    once();
  }
  watch.stop();
  return watch.elapsedMicroseconds / kFrames;
}

double median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

void main() {
  testWidgets('paint cost by layer, median of $kRounds rounds', (tester) async {
    final candles = series(5000);
    var low = candles.first.low;
    var high = candles.first.high;
    for (final candle in candles) {
      if (candle.low < low) low = candle.low;
      if (candle.high > high) high = candle.high;
    }

    final base = ChartStyle.current;
    final variants = <String, ChartStyle>{
      'with volume': base,
      'no volume': base.copyWith(showVolume: false),
      'no grids': base.copyWith(showGrid: false),
      'no session bands': base.copyWith(showSessions: false),
      'no separators/breaks': base.copyWith(
        showSeparators: false,
        showSessionBreaks: false,
      ),
      'line instead of candles': base.copyWith(chartType: ChartType.line),
      'RSI pane': base.copyWith(oscillator: Oscillator.rsi),
    };

    // Interleaved so a slow patch of machine time hits every variant, not just
    // whichever one happened to run during it.
    final samples = <String, List<double>>{
      for (final name in variants.keys) name: <double>[],
    };
    for (var round = 0; round < kRounds; round++) {
      for (final entry in variants.entries) {
        samples[entry.key]!.add(timePaint(candles, low, high, entry.value));
      }
    }

    for (final entry in samples.entries) {
      final values = entry.value;
      final spread = values.reduce((a, b) => a > b ? a : b) -
          values.reduce((a, b) => a < b ? a : b);
      // ignore: avoid_print
      print(
        '${median(values).toStringAsFixed(1).padLeft(7)} us/frame  '
        '(spread ${spread.toStringAsFixed(0)})   ${entry.key}',
      );
    }

    expect(base, isNotNull);
  });
}
