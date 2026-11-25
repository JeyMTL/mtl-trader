import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/chart_projection.dart';
import 'package:mtl_trader_mobile/services/market_data.dart' show Candle;

Candle bar(int minute) => Candle(
      time: DateTime.utc(2026, 11, 25, 10).add(Duration(minutes: minute)),
      open: 1.09,
      high: 1.091,
      low: 1.089,
      close: 1.09,
    );

void main() {
  final candles = [for (var i = 0; i < 10; i++) bar(i * 5)];
  const interval = Duration(minutes: 5);
  const plotW = 300.0;
  const start = 0.0;
  const span = 10.0;

  test('the newest candle stops short of the price axis', () {
    final lastX = chartXForIndex(
      index: 9,
      start: start,
      span: span,
      plotW: plotW,
    );
    expect(lastX, lessThan(plotW));
    expect(plotW - lastX, greaterThan(plotW * chartFutureMargin));
    expect(
      plotW - lastX,
      lessThan(
        plotW * chartFutureMargin + chartCandleWidth(plotW) / span,
      ),
    );
  });

  test('a time past the last candle lands in the future gutter', () {
    final last = candles.last.time.millisecondsSinceEpoch;
    final x = chartXForTimeMs(
      ms: last + 2 * interval.inMilliseconds,
      candles: candles,
      interval: interval,
      start: start,
      span: span,
      plotW: plotW,
    );
    expect(x, isNotNull);
    expect(
        x!,
        greaterThan(chartXForIndex(
          index: 9,
          start: start,
          span: span,
          plotW: plotW,
        )));
    expect(x, lessThanOrEqualTo(plotW));
  });

  test('a finger in the gutter projects whole future bars', () {
    final last = candles.last.time.millisecondsSinceEpoch;
    final lastX = chartXForIndex(
      index: 9,
      start: start,
      span: span,
      plotW: plotW,
    );
    final barPx = chartCandleWidth(plotW) / span;
    final ms = chartTimeMsForX(
      dx: lastX + barPx * 1.2,
      candles: candles,
      interval: interval,
      start: start,
      span: span,
      plotW: plotW,
    );
    expect(ms, last + interval.inMilliseconds);
  });

  test('future times round-trip through x back to the dragged bar', () {
    final last = candles.last.time.millisecondsSinceEpoch;
    final future = last + interval.inMilliseconds;
    final x = chartXForTimeMs(
      ms: future,
      candles: candles,
      interval: interval,
      start: start,
      span: span,
      plotW: plotW,
    )!;
    final back = chartTimeMsForX(
      dx: x,
      candles: candles,
      interval: interval,
      start: start,
      span: span,
      plotW: plotW,
    );
    expect(back, future);
  });

  test('x inside the candles still names the bar under the finger', () {
    final x = chartXForIndex(
      index: 4,
      start: start,
      span: span,
      plotW: plotW,
    );
    final ms = chartTimeMsForX(
      dx: x,
      candles: candles,
      interval: interval,
      start: start,
      span: span,
      plotW: plotW,
    );
    expect(ms, candles[4].time.millisecondsSinceEpoch);
  });

  test('a time before the loaded series has no x', () {
    final x = chartXForTimeMs(
      ms: candles.first.time.millisecondsSinceEpoch - 1,
      candles: candles,
      interval: interval,
      start: start,
      span: span,
      plotW: plotW,
    );
    expect(x, isNull);
  });
}
