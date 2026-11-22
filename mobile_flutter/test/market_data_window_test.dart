import 'package:flutter_test/flutter_test.dart';

import 'package:mtl_trader_mobile/services/market_data.dart';

void main() {
  final end = DateTime.utc(2026, 11, 20, 16);

  test('a one-day five-second window keeps only the bars the feed will serve',
      () {
    final clamped = clampWindowToFeed(
      end.subtract(const Duration(days: 1)),
      end,
      ChartInterval.fiveSeconds,
    );

    expect(clamped.to, end);
    expect(
      clamped.to.difference(clamped.from),
      const Duration(seconds: 5) * maxCandlesPerRequest,
    );
    expect(
      candleCountFor(clamped.to.difference(clamped.from), ChartInterval.fiveSeconds),
      maxCandlesPerRequest,
    );
  });

  test('a window that already fits is left exactly as asked', () {
    final from = end.subtract(const Duration(hours: 2));
    final clamped =
        clampWindowToFeed(from, end, ChartInterval.fiveSeconds);
    expect(clamped.from, from);
    expect(clamped.to, end);
  });

  test('minute and hourly windows are untouched', () {
    final from = end.subtract(const Duration(days: 1));
    for (final interval in [
      ChartInterval.oneMinute,
      ChartInterval.fiveMinutes,
      ChartInterval.oneHour,
    ]) {
      final clamped = clampWindowToFeed(from, end, interval);
      expect(clamped.from, from, reason: interval.key);
      expect(clamped.to, end, reason: interval.key);
    }
  });

  test('a 30-second window clamps instead of returning nothing', () {
    final from = end.subtract(const Duration(days: 2));
    final clamped = clampWindowToFeed(from, end, ChartInterval.thirtySeconds);
    expect(
      candleCountFor(clamped.to.difference(clamped.from), ChartInterval.thirtySeconds),
      maxCandlesPerRequest,
    );
  });
}
