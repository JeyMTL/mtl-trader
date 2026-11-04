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

    test(
        'pan clamps to the list edges, allowing a blank shift past the last bar',
        () {
      final view = ChartViewport()..fit(300);
      view.pan(-1000);
      view.clampTo(300);
      expect(view.start, 0);
      view.pan(1000);
      view.clampTo(300);
      expect(view.start, view.maxStart(300));
      // Half a pane of blank space past the newest candle, no more.
      expect(view.start + view.span, closeTo(300 + 45, 0.001));
    });

    test('the newest candle can be dragged in from the right edge', () {
      final view = ChartViewport()..fit(300);
      expect(view.isAtEdge(300), isTrue);
      view.pan(20);
      view.clampTo(300);
      expect(view.start, 230);
      expect(view.isAtEdge(300), isFalse);

      // Coming back to live takes the blank space away again.
      view.pinToEdge(300);
      expect(view.start + view.span, 300);
      expect(view.isAtEdge(300), isTrue);
    });

    test('pinToEdge follows the newest bar without changing the zoom', () {
      final view = ChartViewport()..fit(300);
      final span = view.span;
      view.pinToEdge(305);
      expect(view.span, span);
      expect(view.start + view.span, 305);
      expect(view.isAtEdge(305), isTrue);
    });

    test('anchorLeftEdge holds the bar the trader was looking at', () {
      final view = ChartViewport()..fit(300);
      view.pan(-150);
      view.clampTo(300);
      expect(view.start, 60);
      expect(view.isAtEdge(300), isFalse);

      // The window slid by one bar; the same index is now a bar later in time.
      view.anchorLeftEdge(61, 301);
      expect(view.start, 61);
      expect(view.isAtEdge(301), isFalse);
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

    test('snap settles the left edge on a whole candle', () {
      final view = ChartViewport()..fit(300);
      view.start = 40.37;
      view.snap(300);
      expect(view.start, 40);

      view.start = 40.6;
      view.snap(300);
      expect(view.start, 41);
    });

    test('snap cannot push the window past the newest bars', () {
      final view = ChartViewport()..fit(300);
      view.start = 299.7;
      view.snap(300);
      expect(view.start, view.maxStart(300));
    });

    test('a fling travels further the faster it was thrown, and always stops',
        () {
      final slow = ChartViewport()..fit(300);
      final fast = ChartViewport()..fit(300);
      final slowRest = slow.flingRest(-30, 300);
      final fastRest = fast.flingRest(-120, 300);
      expect(slowRest, lessThan(slow.start));
      expect(fastRest, lessThan(slowRest));
      expect(fastRest, greaterThanOrEqualTo(0));
    });

    test('a fling never lands outside the loaded history', () {
      final view = ChartViewport()..fit(300);
      expect(view.flingRest(-10000, 300), 0);
      expect(view.flingRest(10000, 300), view.maxStart(300));
    });

    test('sitting at the oldest bar is reported, so history can be fetched',
        () {
      final view = ChartViewport()..fit(300);
      expect(view.isAtStart, isFalse);
      view.pan(-1000);
      view.clampTo(300);
      expect(view.isAtStart, isTrue);
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
