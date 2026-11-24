import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/journal_freshness.dart';

void main() {
  final now = DateTime.utc(2026, 11, 24, 22, 5);

  test('a trade closed seconds ago is news', () {
    expect(
      isJustJournaled(
        {
          'symbol': 'BTCUSDM',
          'open_time': '2026-11-24T22:02:49+00:00',
          'close_time': '2026-11-24T22:03:02+00:00',
        },
        now: now,
      ),
      isTrue,
    );
  });

  test('a backfilled trade from an hour ago is not', () {
    // The exact row that produced "EURUSDM journaled" during a BTC session.
    expect(
      isJustJournaled(
        {
          'symbol': 'EURUSDM',
          'open_time': '2026-11-24T21:20:09+00:00',
          'close_time': '2026-11-24T21:20:18+00:00',
        },
        now: now,
      ),
      isFalse,
    );
  });

  test('falls back to the open time when there is no close', () {
    expect(
      isJustJournaled(
        {'open_time': '2026-11-24T22:04:00+00:00'},
        now: now,
      ),
      isTrue,
    );
  });

  test('a row with no usable time is not announced', () {
    expect(isJustJournaled({'symbol': 'BTCUSDM'}, now: now), isFalse);
    expect(isJustJournaled({'close_time': 'not a date'}, now: now), isFalse);
  });

  test('a broker clock a little ahead of the phone still counts', () {
    expect(
      isJustJournaled(
        {'close_time': '2026-11-24T22:06:30+00:00'},
        now: now,
      ),
      isTrue,
    );
  });

  test('the window is a parameter', () {
    final row = {'close_time': '2026-11-24T21:30:00+00:00'};

    expect(isJustJournaled(row, now: now), isFalse); // 35 minutes
    expect(
      isJustJournaled(row, now: now, window: const Duration(hours: 1)),
      isTrue,
    );
  });
}
