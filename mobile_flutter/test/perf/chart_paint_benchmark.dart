// Chart paint benchmark — not part of the suite (no `_test.dart` suffix).
//
//   flutter test test/perf/chart_paint_benchmark.dart
//
// Times the painter's real work through a PictureRecorder: candles, volume,
// studies, session bands, separators, axes and labels, at the window a trader
// sees (90 candles) inside a fully loaded series (5,000).
//
// This is host-side. A phone with a slower CPU and a real Skia/Impeller surface
// will be slower in absolute terms; the useful signal here is the shape —
// whether the frame cost tracks the visible window or the whole series — and
// whether a change makes it worse.
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

void main() {
  testWidgets('paint cost at 90 visible of 5,000 loaded', (tester) async {
    final candles = series(5000);
    var low = candles.first.low;
    var high = candles.first.high;
    for (final candle in candles) {
      if (candle.low < low) low = candle.low;
      if (candle.high > high) high = candle.high;
    }

    final painter = debugChartPainter(
      candles: candles,
      start: candles.length - 90,
      span: 90,
      minPrice: low,
      maxPrice: high,
      decimals: 5,
      interval: ChartInterval.fifteenMinutes,
      style: ChartStyle.current,
    );

    const size = Size(392, 380);

    void once() {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, size);
      recorder.endRecording().dispose();
    }

    // Warm up the text shaper and the JIT.
    for (var i = 0; i < 20; i++) {
      once();
    }

    const runs = 100;
    final watch = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      once();
    }
    watch.stop();

    final perFrame = watch.elapsedMicroseconds / runs;
    // ignore: avoid_print
    print('PAINT ${perFrame.toStringAsFixed(1)} us/frame over $runs frames '
        '(90 visible of ${candles.length})');

    expect(perFrame, greaterThan(0));
  });
}
