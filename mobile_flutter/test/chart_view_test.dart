import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/chart_view.dart';

void main() {
  group('ChartViewport', () {
    test('fit shows the latest candles at the right edge', () {
      final view = ChartViewport()..fit(300);
      expect(view.span, 90);
      expect(view.start, 210);
      expect(view.start + view.span, 300);
    });

    test('fit never shows fewer candles than the list has', () {
      final view = ChartViewport()..fit(8);
      expect(view.span, 8);
      expect(view.start, 0);
    });

    test('pan clamps to the list edges', () {
      final view = ChartViewport()..fit(300);
      view.pan(-1000);
      view.clampTo(300);
      expect(view.start, 0);
      view.pan(1000);
      view.clampTo(300);
      expect(view.start, 210);
    });

    test('zoom keeps the anchored candle under the focal point', () {
      final view = ChartViewport()..fit(300);
      final baseStart = view.start;
      final baseSpan = view.span;
      view.zoomAround(
        scale: 2,
        anchorRatio: 0.5,
        count: 300,
        baseSpan: baseSpan,
        baseStart: baseStart,
      );
      expect(view.span, 45);
      // The candle in the middle of the old window stays in the middle.
      final anchorBefore = baseStart + 0.5 * baseSpan;
      expect(view.start + 0.5 * view.span, closeTo(anchorBefore, 0.001));
    });

    test('zoom is clamped so the chart stays readable', () {
      final view = ChartViewport()..fit(300);
      view.zoomAround(
        scale: 500,
        anchorRatio: 0.5,
        count: 300,
        baseSpan: view.span,
        baseStart: view.start,
      );
      expect(view.span, ChartViewport.minSpan);
      expect(view.start, greaterThanOrEqualTo(0));
      expect(view.start + view.span, lessThanOrEqualTo(300));
    });

    test('maps ratios to candles and prices', () {
      final view = ChartViewport()..fit(300);
      expect(view.indexAt(0, 300), 210);
      expect(view.indexAt(1, 300), 299);
      expect(view.priceAt(0, 100, 200), 200);
      expect(view.priceAt(1, 100, 200), 100);
      expect(view.priceAt(0.5, 100, 200), 150);
    });

    test('visible returns a non-empty clamped range', () {
      final view = ChartViewport()..fit(300);
      final range = view.visible(300);
      expect(range.first, 210);
      expect(range.last, 300);
      expect(range.last, greaterThan(range.first));
    });
  });
}
