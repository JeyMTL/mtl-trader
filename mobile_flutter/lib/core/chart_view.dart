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

  /// How much blank space past the newest candle a drag may pull in, as a share
  /// of the visible span.
  ///
  /// Without it the live bar is welded to the right edge: the window cannot
  /// move at all once it is there, which reads as a dead chart to a trader
  /// trying to look at the candle they are actually trading. Half a pane is
  /// enough to park the newest bar mid-chart and still leaves the rest for
  /// price. `pinToEdge` takes the space back, so it is never stuck that way.
  static const double maxShift = 0.5;

  /// Show the most recent candles, `preferred` of them at most.
  void fit(int count, {double preferred = 90}) {
    if (count <= 0) return;
    final upper = count.toDouble();
    span = preferred.clamp(math.min(minSpan, upper), upper);
    start = upper - span;
    clampTo(count);
  }

  /// The furthest right `start` may sit: the newest candle at the right edge,
  /// plus the blank shift a drag can pull in.
  double maxStart(int count) {
    if (count <= 0) return 0;
    final upper = count.toDouble();
    final visibleSpan = span.clamp(math.min(minSpan, upper), upper);
    return math.max(0.0, upper - visibleSpan + visibleSpan * maxShift);
  }

  void clampTo(int count) {
    if (count <= 0) {
      start = 0;
      return;
    }
    final upper = count.toDouble();
    span = span.clamp(math.min(minSpan, upper), upper);
    start = start.clamp(0.0, maxStart(count));
  }

  void pan(double candles) => start += candles;

  /// Settles the left edge onto a whole candle.
  ///
  /// A gesture leaves `start` fractional, so the chart can come to rest halfway
  /// between two bars with the crosshair pointing at neither. Desktop platforms
  /// snap; so does this, as the last step after a drag or a fling.
  void snap(int count) {
    start = start.roundToDouble();
    clampTo(count);
  }

  /// True while the oldest loaded bar is on screen, so the caller can fetch an
  /// earlier window instead of letting the chart stop at a wall.
  bool get isAtStart => start <= 0.5;

  /// Where a fling coasts to, from a speed in candles per second.
  ///
  /// Exponential friction: distance = speed / friction. Clamped to the loaded
  /// bars, so a hard throw lands on the first or last bar rather than past it.
  double flingRest(double candlesPerSecond, int count,
      {double friction = 5.5}) {
    if (count <= 0) return 0;
    final upper = maxStart(count);
    final travel = candlesPerSecond / friction;
    return (start + travel).clamp(0.0, upper).toDouble();
  }

  /// True when the newest candle sits on the right edge, i.e. the view is pinned
  /// to the live edge. Half a bar of slack, because `start` is fractional while
  /// a finger is panning and the edge would otherwise flicker in and out of
  /// "at edge".
  ///
  /// A chart shifted into the blank space is deliberately *not* at the edge:
  /// the caller then offers the way back instead of silently re-pinning the live
  /// bar every time a new candle arrives.
  bool isAtEdge(int count) {
    if (count <= 0) return true;
    final overshoot = start + span - count;
    return overshoot >= -0.5 && overshoot <= 0.5;
  }

  /// Pins the newest candle to the right edge without changing the zoom. Used
  /// when bars arrive while the trader is already watching the live edge, so the
  /// chart follows the market instead of stalling behind it.
  void pinToEdge(int count) {
    if (count <= 0) {
      start = 0;
      return;
    }
    final upper = count.toDouble();
    span = span.clamp(math.min(minSpan, upper), upper);
    start = math.max(0.0, upper - span);
  }

  /// Puts `index` under the left edge, then clamps.
  ///
  /// A live window drops its oldest bar as a new one arrives, so holding the
  /// same index would drag a panned-back chart a bar forward on every refresh
  /// until it snapped to the newest candle. Anchoring on the bar the trader was
  /// looking at keeps the chart where they put it.
  void anchorLeftEdge(double index, int count) {
    start = index;
    clampTo(count);
  }

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
