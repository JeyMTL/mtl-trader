import 'dart:math' as math;

/// Cursor for market replay: which candle of the loaded series counts as "now".
///
/// The chart hides every candle after [index], so stepping forward looks like
/// the market printing the next bar and pinning levels works exactly as it does
/// live. Pure and immutable so the stepping rules are testable without a widget
/// tree.
class ReplayCursor {
  const ReplayCursor({required this.count, required this.index});

  /// Starts with roughly a third of the series still to come, which is enough
  /// to step through without hunting for a start point — and keeps the last
  /// third of the range available for levels and targets.
  factory ReplayCursor.start({required int count}) {
    if (count <= 1) return ReplayCursor(count: count, index: 0);
    return ReplayCursor(
      count: count,
      index: math.max(1, (count * 2 / 3).floor()),
    );
  }

  /// Candles loaded for the current range.
  final int count;

  /// Index of the last visible candle.
  final int index;

  /// How many candles the chart should draw.
  int get visible => count == 0 ? 0 : index + 1;

  bool get atStart => index <= 0;

  bool get atEnd => count == 0 || index >= count - 1;

  ReplayCursor next() =>
      atEnd ? this : ReplayCursor(count: count, index: index + 1);

  ReplayCursor previous() =>
      atStart ? this : ReplayCursor(count: count, index: index - 1);
}
