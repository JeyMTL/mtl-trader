import '../services/market_data.dart' show Candle;

/// Whether a stored trade type is a long. Anything that is not an explicit
/// `SELL` is a buy, matching the rest of the app; case and stray spaces from an
/// import are tolerated so a `sell` row is never read as a long.
bool isBuySide(String type) => type.trim().toUpperCase() != 'SELL';

/// What ended the trade.
enum ExitReason {
  /// The target was reached first.
  takeProfit,

  /// The stop was reached first.
  stopLoss,

  /// Neither level was reached inside the data; the exit is the latest price,
  /// marked so the entry is not silently counted as a win or a loss.
  latestPrice;

  String get label {
    switch (this) {
      case ExitReason.takeProfit:
        return 'Take profit hit first';
      case ExitReason.stopLoss:
        return 'Stop loss hit first';
      case ExitReason.latestPrice:
        return 'Neither level reached · marked at the latest price';
    }
  }
}

/// Where a trade closed, and why.
class ResolvedExit {
  const ResolvedExit({
    required this.price,
    required this.time,
    required this.reason,
  });

  final double price;
  final DateTime time;
  final ExitReason reason;

  bool get isTakeProfit => reason == ExitReason.takeProfit;

  bool get isStopLoss => reason == ExitReason.stopLoss;

  String get label => reason.label;
}

/// Resolves the exit the market actually gave a trade.
///
/// The trader pins entry, stop and target; the app does not ask for an exit
/// price, because a hand-typed exit is how a losing sell quietly gets recorded
/// as a profit. Instead the loaded candles are walked forward from the entry and
/// the first level touched wins:
///
/// * a buy is closed by the target when a candle's high reaches it, and by the
///   stop when a candle's low reaches it;
/// * a sell is the mirror image: the target is below entry and the stop above,
///   so the target is hit on a low and the stop on a high.
///
/// Both levels can print inside one bar. Nothing in a candle tells you which
/// came first, so the level closest to that bar's open is taken as the first
/// touch — the open is the only price known to have traded before either. An
/// exact tie goes to the stop, because a journal that flatters the trader is
/// worse than one that is slightly pessimistic.
///
/// Levels on the wrong side of entry are ignored rather than honoured: a sell
/// with a target above entry would otherwise book a profit the market never
/// offered. Returns null when there are no candles at or after the entry, which
/// means "ask for a range that covers the trade", not "the trade made zero".
ResolvedExit? resolveExit({
  required String type,
  required double entry,
  double? stop,
  double? take,
  required DateTime entryTime,
  required List<Candle> candles,
}) {
  final buy = isBuySide(type);
  final entryUtc = entryTime.toUtc();

  // Only levels on the correct side of entry count.
  final validTake = take != null && (buy ? take > entry : take < entry);
  final validStop = stop != null && (buy ? stop < entry : stop > entry);
  final takeLevel = validTake ? take : null;
  final stopLevel = validStop ? stop : null;

  final forward = candles
      .where((candle) => !candle.time.toUtc().isBefore(entryUtc))
      .toList()
    ..sort((a, b) => a.time.compareTo(b.time));

  if (forward.isEmpty) return null;

  for (final candle in forward) {
    final takeHit =
        takeLevel != null && (buy ? candle.high >= takeLevel : candle.low <= takeLevel);
    final stopHit =
        stopLevel != null && (buy ? candle.low <= stopLevel : candle.high >= stopLevel);

    if (takeHit && stopHit) {
      final takeDistance = (takeLevel - candle.open).abs();
      final stopDistance = (stopLevel - candle.open).abs();
      final hitTake = takeDistance < stopDistance;
      return ResolvedExit(
        price: hitTake ? takeLevel : stopLevel,
        time: candle.time,
        reason: hitTake ? ExitReason.takeProfit : ExitReason.stopLoss,
      );
    }
    if (takeHit) {
      return ResolvedExit(
        price: takeLevel,
        time: candle.time,
        reason: ExitReason.takeProfit,
      );
    }
    if (stopHit) {
      return ResolvedExit(
        price: stopLevel,
        time: candle.time,
        reason: ExitReason.stopLoss,
      );
    }
  }

  // The range ended with the trade still inside its brackets. The latest close
  // is the honest mark: it makes the entry usable without pretending either
  // level was reached.
  final last = forward.last;
  return ResolvedExit(
    price: last.close,
    time: last.time,
    reason: ExitReason.latestPrice,
  );
}
