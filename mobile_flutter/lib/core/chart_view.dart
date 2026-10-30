import 'dart:math' as math;

/// The visible window over a candle list: `start` is the index of the first
/// visible candle (fractional while panning), `span` how many candles fit.
/// Kept free of Flutter so the pan/zoom maths can be unit tested.
class ChartViewport {
  ChartViewport({this.start = 0, this.span = 90});

  double start;
  double span;

  /// Never show fewer than this many candles, so zooming stays readable.
  static const double minSpan = 12;

  /// Show the most recent candles, `preferred` of them at most.
  void fit(int count, {double preferred = 90}) {
    if (count <= 0) return;
    final upper = count.toDouble();
    span = preferred.clamp(math.min(minSpan, upper), upper);
    start = upper - span;
    clampTo(count);
  }

  void clampTo(int count) {
    if (count <= 0) {
      start = 0;
      return;
    }
    final upper = count.toDouble();
    span = span.clamp(math.min(minSpan, upper), upper);
    start = start.clamp(0.0, math.max(0.0, upper - span));
  }

  void pan(double candles) => start += candles;

  /// Zooms by `scale` while keeping the candle under `anchorRatio` fixed.
  /// `baseSpan`/`baseStart` are the viewport values when the gesture began,
  /// because Flutter reports cumulative scale for the whole gesture.
  void zoomAround({
    required double scale,
    required double anchorRatio,
    required int count,
    required double baseSpan,
    required double baseStart,
  }) {
    if (count <= 0) return;
    final upper = count.toDouble();
    final anchor = baseStart + anchorRatio * baseSpan;
    span = (baseSpan / scale).clamp(math.min(minSpan, upper), upper);
    start = anchor - anchorRatio * span;
    clampTo(count);
  }

  /// Candle index under a horizontal ratio (0 = left edge, 1 = right edge).
  int indexAt(double ratio, int count) {
    if (count <= 0) return 0;
    final raw = start + ratio.clamp(0.0, 1.0) * span;
    return raw.floor().clamp(0, count - 1);
  }

  /// Price under a vertical ratio (0 = top edge, 1 = bottom edge).
  double priceAt(double ratioFromTop, double min, double max) =>
      max - ratioFromTop.clamp(0.0, 1.0) * (max - min);

  /// The candle indices currently visible, clamped to the list.
  ({int first, int last}) visible(int count) {
    if (count <= 0) return (first: 0, last: 0);
    final first = start.floor().clamp(0, count - 1);
    final last = (start + span).ceil().clamp(first + 1, count);
    return (first: first, last: last);
  }
}
