import 'dart:math' as math;

/// Maps a price onto a 0..1 ratio from the top of the price pane.
///
/// The painter, the tap-to-price maths and the tests all go through here, so a
/// log axis cannot drift between drawing and hit testing. Non-positive bounds
/// fall back to linear, because a log scale has no meaning there.
double ratioForPrice({
  required double price,
  required double min,
  required double max,
  required bool logScale,
}) {
  if (max - min < 1e-9) return 0.5;
  if (logScale && min > 0 && price > 0) {
    final logMax = math.log(max);
    final logMin = math.log(min);
    if (logMax - logMin > 1e-12) {
      return ((logMax - math.log(price)) / (logMax - logMin))
          .clamp(0.0, 1.0)
          .toDouble();
    }
  }
  return ((max - price) / (max - min)).clamp(0.0, 1.0).toDouble();
}

/// Inverse of [ratioForPrice]: the price at a 0..1 ratio from the pane top.
double priceForRatio({
  required double ratio,
  required double min,
  required double max,
  required bool logScale,
}) {
  final r = ratio.clamp(0.0, 1.0).toDouble();
  if (logScale && min > 0 && max > 0) {
    final logMax = math.log(max);
    final logMin = math.log(min);
    if (logMax - logMin > 1e-12) {
      return math.exp(logMax - r * (logMax - logMin));
    }
  }
  return max - r * (max - min);
}
