import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/trade_exit.dart';
import 'package:mtl_trader_mobile/services/market_data.dart';

Candle bar(
  int minute,
  double open,
  double high,
  double low,
  double close,
) =>
    Candle(
      time: DateTime.utc(2026, 11, 11, 10, minute),
      open: open,
      high: high,
      low: low,
      close: close,
    );

void main() {
  final entryTime = DateTime.utc(2026, 11, 11, 10);

  test('a buy takes the target when the high reaches it first', () {
    final exit = resolveExit(
      type: 'BUY',
      entry: 1.1000,
      stop: 1.0980,
      take: 1.1040,
      entryTime: entryTime,
      candles: [
        bar(0, 1.1000, 1.1010, 1.0995, 1.1005),
        bar(5, 1.1005, 1.1045, 1.1000, 1.1040),
      ],
    );

    expect(exit, isNotNull);
    expect(exit!.reason, ExitReason.takeProfit);
    expect(exit.price, 1.1040);
    expect(exit.time, DateTime.utc(2026, 11, 11, 10, 5));
  });

  test('a sell takes the target when the low reaches it first', () {
    final exit = resolveExit(
      type: 'SELL',
      entry: 1.1000,
      stop: 1.1020,
      take: 1.0960,
      entryTime: entryTime,
      candles: [
        bar(0, 1.1000, 1.1008, 1.0990, 1.0995),
        bar(5, 1.0995, 1.1000, 1.0950, 1.0960),
      ],
    );

    expect(exit!.reason, ExitReason.takeProfit);
    expect(exit.price, 1.0960);
  });

  test('a sell stops out when the high reaches the stop, never booking a profit', () {
    final exit = resolveExit(
      type: 'SELL',
      entry: 1.1000,
      stop: 1.1020,
      take: 1.0960,
      entryTime: entryTime,
      candles: [
        bar(0, 1.1000, 1.1025, 1.0998, 1.1018),
      ],
    );

    expect(exit!.reason, ExitReason.stopLoss);
    expect(exit.price, 1.1020);
    // A sell stopped out is above entry: a loss, not a win.
    expect(exit.price > 1.1000, isTrue);
  });

  test('a lower-case sell is read as a short, not a long', () {
    final exit = resolveExit(
      type: ' sell ',
      entry: 1.1000,
      stop: 1.1020,
      take: 1.0960,
      entryTime: entryTime,
      candles: [
        bar(0, 1.1000, 1.1025, 1.0998, 1.1018),
      ],
    );

    expect(isBuySide(' sell '), isFalse);
    expect(exit!.reason, ExitReason.stopLoss);
  });

  test('a level on the wrong side of entry is ignored, so it cannot fake a win', () {
    // A sell with a target above entry is a typo; treating it as a target would
    // book a profit on a trade that could never have taken it.
    final exit = resolveExit(
      type: 'SELL',
      entry: 1.1000,
      stop: null,
      take: 1.1040,
      entryTime: entryTime,
      candles: [
        bar(0, 1.1000, 1.1050, 1.0990, 1.1030),
      ],
    );

    expect(exit!.reason, ExitReason.latestPrice);
    expect(exit.price, 1.1030);
    expect(exit.isTakeProfit, isFalse);
  });

  test('when both levels print inside one bar the stop is the conservative read', () {
    final exit = resolveExit(
      type: 'BUY',
      entry: 1.1000,
      stop: 1.0980,
      take: 1.1020,
      entryTime: entryTime,
      // The open sits exactly between the two levels.
      candles: [
        bar(0, 1.1000, 1.1025, 1.0975, 1.1000),
      ],
    );

    expect(exit!.reason, ExitReason.stopLoss);
  });

  test('the closer level to the bar open wins a same-bar tie', () {
    final exit = resolveExit(
      type: 'BUY',
      entry: 1.1000,
      stop: 1.0980,
      take: 1.1020,
      entryTime: entryTime,
      // Open near the target: the target was the first level in reach.
      candles: [
        bar(0, 1.1015, 1.1025, 1.0975, 1.1000),
      ],
    );

    expect(exit!.reason, ExitReason.takeProfit);
  });

  test('candles before the entry are ignored', () {
    final exit = resolveExit(
      type: 'BUY',
      entry: 1.1000,
      stop: 1.0980,
      take: 1.1020,
      entryTime: entryTime,
      candles: [
        // A bar earlier in the same hour touched the target, but it is history.
        Candle(
          time: DateTime.utc(2026, 11, 11, 9, 55),
          open: 1.1000,
          high: 1.1030,
          low: 1.0999,
          close: 1.1025,
        ),
        bar(5, 1.1000, 1.1005, 1.0975, 1.0980),
      ],
    );

    expect(exit!.reason, ExitReason.stopLoss);
  });

  test('no candles after entry means no resolution, not a zero exit', () {
    final exit = resolveExit(
      type: 'BUY',
      entry: 1.1000,
      stop: 1.0980,
      take: 1.1020,
      entryTime: entryTime.add(const Duration(hours: 1)),
      candles: [
        bar(0, 1.1000, 1.1005, 1.0995, 1.1000),
      ],
    );

    expect(exit, isNull);
  });
}
