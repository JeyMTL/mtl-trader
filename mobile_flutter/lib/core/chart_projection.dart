import '../services/market_data.dart' show Candle;

/// How much of the chart's width is kept free to the right of the newest
/// candle, as a share of the plot area.
///
/// A desk leaves this space on purpose: it is where an object is projected
/// forward, past live price, without having to stretch it again on every new
/// bar. The value matches the narrow gutter MT5 leaves between the last candle
/// and the price axis.
const double chartFutureMargin = 0.12;

/// The width candles are drawn in: the plot minus the future gutter.
double chartCandleWidth(double plotW) =>
    plotW <= 0 ? 0 : plotW * (1 - chartFutureMargin);

/// The horizontal position of a candle index in the candle area.
double chartXForIndex({
  required double index,
  required double start,
  required double span,
  required double plotW,
}) {
  final width = chartCandleWidth(plotW);
  if (width <= 0 || span <= 0) return 0;
  return ((index + 0.5 - start) / span) * width;
}

/// The x position for an epoch-millisecond time, including times after the
/// newest candle.
///
/// Times beyond the loaded series are projected at the active bar spacing, so
/// an object dragged into the right-hand gutter keeps a real timestamp instead
/// of being clamped to the last bar. Null means the time is older than the
/// loaded series (the painter clamps those at the left edge).
double? chartXForTimeMs({
  required int ms,
  required List<Candle> candles,
  required Duration interval,
  required double start,
  required double span,
  required double plotW,
}) {
  if (candles.isEmpty || span <= 0) return null;
  final width = chartCandleWidth(plotW);
  if (width <= 0) return null;
  final firstMs = candles.first.time.millisecondsSinceEpoch;
  if (ms < firstMs) return null;

  final lastIndex = candles.length - 1;
  final lastMs = candles.last.time.millisecondsSinceEpoch;
  final double index;
  if (ms > lastMs) {
    final barMs = interval.inMilliseconds;
    if (barMs <= 0) return null;
    index = lastIndex + (ms - lastMs) / barMs;
  } else {
    var low = 0;
    var high = lastIndex;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (candles[mid].time.millisecondsSinceEpoch < ms) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    index = low.toDouble();
  }
  final x = ((index + 0.5 - start) / span) * width;
  if (!x.isFinite) return null;
  return x.clamp(0.0, plotW).toDouble();
}

/// The candle time under an x position, projected past the last candle.
///
/// Inside the candles this is the bar under the finger. To the right of the
/// newest bar's centre, the offset is measured in whole bar spacings and added
/// to the newest candle's time, which is what lets a handle be dragged into the
/// gutter and stay on a plausible future bar.
int? chartTimeMsForX({
  required double dx,
  required List<Candle> candles,
  required Duration interval,
  required double start,
  required double span,
  required double plotW,
}) {
  if (candles.isEmpty || span <= 0) return null;
  final width = chartCandleWidth(plotW);
  if (width <= 0) return null;
  final x = dx.clamp(0.0, plotW).toDouble();
  final lastIndex = candles.length - 1;
  final lastMs = candles.last.time.millisecondsSinceEpoch;
  final lastX = chartXForIndex(
    index: lastIndex.toDouble(),
    start: start,
    span: span,
    plotW: plotW,
  );

  if (x > lastX) {
    final barMs = interval.inMilliseconds;
    final barPx = width / span;
    if (barMs <= 0 || barPx <= 0) return lastMs;
    final deltaBars = (x - lastX) / barPx;
    return lastMs + deltaBars.round() * barMs;
  }

  final ratio = (x / width).clamp(0.0, 1.0).toDouble();
  final raw = start + ratio * span;
  final index = raw.floor().clamp(0, lastIndex);
  return candles[index].time.millisecondsSinceEpoch;
}
