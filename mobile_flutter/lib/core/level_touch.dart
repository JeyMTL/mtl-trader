import 'package:flutter/foundation.dart';

/// A price the trader cares about, with the words that describe it.
///
/// The chart holds three kinds of level — the entry, stop and target of the
/// position tool, every horizontal ray, and the exit mark — and all of them mean
/// the same thing to an alert: "tell me when price gets here".
@immutable
class WatchedLevel {
  const WatchedLevel({required this.label, required this.price});

  final String label;
  final double price;

  @override
  bool operator ==(Object other) =>
      other is WatchedLevel && other.label == label && other.price == price;

  @override
  int get hashCode => Object.hash(label, price);

  @override
  String toString() => '$label @ $price';
}

/// The levels price passed through between two closes.
///
/// Two closes, not a high and a low: the live tail is polled, so the honest
/// question is "did the last price we saw sit on one side and the new one on the
/// other". A touch that happens and reverses inside a single poll is invisible to
/// the chart as well, so reporting it would be inventing information.
///
/// A close that lands exactly on a level counts as touched. Standing on a level
/// is the case the trader is watching for, and the app has no tick data to
/// distinguish it from a momentary poke.
List<WatchedLevel> touchedLevels({
  required double? from,
  required double to,
  required Iterable<WatchedLevel> levels,
  double tolerance = 1e-9,
}) {
  if (from == null || !to.isFinite || !from.isFinite) return const [];
  if (from == to) return const [];
  final low = from < to ? from : to;
  final high = from < to ? to : from;
  final hits = <WatchedLevel>[];
  for (final level in levels) {
    if (!level.price.isFinite) continue;
    // Strict at the start, inclusive at the end: a level price sat on last
    // poll has already been reported, and re-reporting it on every tick would
    // turn one touch into an alarm clock.
    final leftTheStart = (level.price - from).abs() > tolerance;
    final inside =
        level.price >= low - tolerance && level.price <= high + tolerance;
    if (leftTheStart && inside) hits.add(level);
  }
  return hits;
}
