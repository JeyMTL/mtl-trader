import 'package:flutter_test/flutter_test.dart';

import 'package:mtl_trader_mobile/services/market_data.dart';

Candle bar(int minute, double close) => Candle(
      time: DateTime.utc(2026, 11, 20, 20).add(Duration(minutes: minute)),
      open: close,
      high: close + 0.0002,
      low: close - 0.0002,
      close: close,
      volume: 12,
    );

void main() {
  test('a device copy comes back with its candles and its moment', () {
    final at = DateTime.utc(2026, 11, 20, 21, 5);
    final candles = [bar(0, 1.0961), bar(1, 1.0963), bar(2, 1.0959)];

    final restored = decodeOfflineCandles(encodeOfflineCandles(candles, at));

    expect(restored, isNotNull);
    // The stamp comes back in the device's own clock, which is what the header
    // prints; the instant is what has to survive.
    expect(restored!.at.millisecondsSinceEpoch, at.millisecondsSinceEpoch);
    expect(restored.candles, hasLength(3));
    expect(restored.candles.last.close, closeTo(1.0959, 1e-9));
    expect(restored.candles.last.time, candles.last.time);
    expect(restored.candles.last.volume, 12);
  });

  test('every window joins the archive instead of replacing it', () {
    // Thursday's session, then Monday's, fetched in the other order.
    final thursday = [bar(0, 1.10), bar(1, 1.101), bar(2, 1.102)];
    final monday = [
      bar(-3 * 24 * 60, 1.09),
      bar(-3 * 24 * 60 + 1, 1.091),
    ];

    final merged = mergeCandles(thursday, monday);

    expect(merged, hasLength(5));
    expect(merged.first.close, closeTo(1.09, 1e-9));
    expect(merged.last.close, closeTo(1.102, 1e-9));
    // Oldest first, so the chart can paint it without sorting again.
    for (var i = 1; i < merged.length; i++) {
      expect(
        merged[i].time.isAfter(merged[i - 1].time),
        isTrue,
        reason: 'the archive is ordered by candle time',
      );
    }
  });

  test('a re-read bar replaces the stored one rather than duplicating it', () {
    final stored = [bar(0, 1.10), bar(1, 1.101)];
    // The newest candle moves while it prints: same minute, new close.
    final fresh = [bar(1, 1.104), bar(2, 1.105)];

    final merged = mergeCandles(stored, fresh);

    expect(merged, hasLength(3));
    expect(merged[1].close, closeTo(1.104, 1e-9));
  });

  test('only the newest bars are kept, so the store stays bounded', () {
    final many = [for (var i = 0; i < 13000; i++) bar(i, 1.10 + i * 0.00001)];

    final restored = decodeOfflineCandles(
      encodeOfflineCandles(many, DateTime.utc(2026, 11, 20, 22)),
    );

    expect(restored!.candles, hasLength(MarketDataService.historyLimit));
    expect(restored.candles.last.close, closeTo(many.last.close, 1e-9));
    expect(
      restored.candles.first.time,
      many[many.length - MarketDataService.historyLimit].time,
    );
  });

  test('merging a huge fresh window still bounds the archive', () {
    final stored = [for (var i = 0; i < 11000; i++) bar(i, 1.10)];
    final fresh = [
      for (var i = 0; i < 3000; i++)
        bar(11000 + i, 1.11),
    ];

    expect(mergeCandles(stored, fresh), hasLength(MarketDataService.historyLimit));
  });

  test('nothing stored, garbage, or all-bad rows read as no copy at all', () {
    expect(decodeOfflineCandles(null), isNull);
    expect(decodeOfflineCandles(''), isNull);
    expect(decodeOfflineCandles('not json'), isNull);
    expect(decodeOfflineCandles('{"at":1}'), isNull);
    expect(
      decodeOfflineCandles('{"at":1,"c":[[1,2,3]]}'),
      isNull,
      reason: 'a row without five numbers is not a candle',
    );
  });
}
