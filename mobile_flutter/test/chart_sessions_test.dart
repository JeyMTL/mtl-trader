import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/chart_sessions.dart';

/// 2026-11-02 is a Monday, so week boundaries land where the tests expect.
DateTime utc(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 11, day, hour, minute);

void main() {
  group('session windows', () {
    test('the Asian session is the UTC morning', () {
      expect(TradingSession.asian.contains(utc(2, 0)), isTrue);
      expect(TradingSession.asian.contains(utc(2, 8, 59)), isTrue);
      // Half-open: 09:00 belongs to London, so Asia cannot claim it too.
      expect(TradingSession.asian.contains(utc(2, 9)), isFalse);
      expect(TradingSession.asian.contains(utc(2, 14)), isFalse);
    });

    test('a session wrapped over midnight is inside on both sides', () {
      expect(TradingSession.sydney.contains(utc(2, 23)), isTrue);
      expect(TradingSession.sydney.contains(utc(2, 2)), isTrue);
      expect(TradingSession.sydney.contains(utc(2, 12)), isFalse);
    });

    test('overlapping sessions both claim their shared hours', () {
      final time = utc(2, 13);
      expect(TradingSession.london.contains(time), isTrue);
      expect(TradingSession.newYork.contains(time), isTrue);
    });

    test('a local DateTime is read as UTC, not by its own local hour', () {
      // 02:00 UTC viewed from any zone must still be the Asian session.
      final local = utc(2, 2).toLocal();
      expect(TradingSession.asian.contains(local), isTrue);
    });
  });

  group('session bands', () {
    test('one continuous run is one band', () {
      final bands = sessionBands(
        [utc(2, 1), utc(2, 2), utc(2, 3)],
        TradingSession.asian,
      ).toList();
      expect(bands, hasLength(1));
      expect(bands.single.firstIndex, 0);
      expect(bands.single.lastIndex, 2);
      expect(bands.single.length, 3);
    });

    test('two runs of the same session stay separate', () {
      // 01:00 and 02:00 are Asian, 12:00 is not, so the band is cut.
      final bands = sessionBands(
        [utc(2, 1), utc(2, 12), utc(2, 2)],
        TradingSession.asian,
      ).toList();
      expect(bands, hasLength(2));
      expect(bands.first.firstIndex, 0);
      expect(bands.first.lastIndex, 0);
      expect(bands.last.firstIndex, 2);
      expect(bands.last.lastIndex, 2);
    });

    test('a band running to the end of the series is closed', () {
      final bands = sessionBands(
        [utc(2, 0), utc(2, 1)],
        TradingSession.asian,
      ).toList();
      expect(bands.single.lastIndex, 1);
    });

    test('a session no candle falls inside yields nothing', () {
      expect(sessionBands([utc(2, 12), utc(2, 13)], TradingSession.asian),
          isEmpty);
    });

    test('an empty series yields nothing', () {
      expect(sessionBands(const <DateTime>[], TradingSession.london), isEmpty);
    });
  });

  group('session ownership', () {
    test('the most recently opened session wins an overlap', () {
      // 13:00 UTC is inside both London and New York; New York opened later, so
      // it is the answer a trader reading the label wants.
      final hit = sessionHitOf(
        index: 0,
        length: 1,
        timeAt: (_) => utc(2, 13),
      );
      expect(hit?.session, TradingSession.newYork);
    });

    test('a session wrapped over midnight does not steal the Asian morning',
        () {
      // Sydney also covers 02:00 UTC, but it opened five hours ago.
      final hit = sessionHitOf(
        index: 0,
        length: 1,
        timeAt: (_) => utc(2, 2),
      );
      expect(hit?.session, TradingSession.asian);
      expect(TradingSession.sydney.hoursInto(utc(2, 2)), 5);
    });

    test('a hit reports the run around the index, not the whole series', () {
      final times = [utc(2, 1), utc(2, 2), utc(2, 12)];
      final hit = sessionHitOf(index: 1, length: 3, timeAt: (i) => times[i]);
      expect(hit?.firstIndex, 0);
      expect(hit?.lastIndex, 1);
      expect(hit?.length, 2);
    });

    test('an index outside the series has no session', () {
      expect(
        sessionHitOf(index: 5, length: 3, timeAt: (i) => utc(2, i + 1)),
        isNull,
      );
      expect(
        sessionHitOf(index: -1, length: 3, timeAt: (i) => utc(2, i + 1)),
        isNull,
      );
    });
  });

  group('period boundaries', () {
    test('a new UTC day is a boundary, the same day is not', () {
      expect(
        isPeriodBoundary(utc(2, 23), utc(3, 0), SeparatorGrain.day),
        isTrue,
      );
      expect(
        isPeriodBoundary(utc(2, 1), utc(2, 2), SeparatorGrain.day),
        isFalse,
      );
    });

    test('a new month is a boundary; a new day inside it is not', () {
      expect(
        isPeriodBoundary(
          DateTime.utc(2026, 11, 30, 23),
          DateTime.utc(2026, 12, 1, 0),
          SeparatorGrain.month,
        ),
        isTrue,
      );
      expect(
        isPeriodBoundary(
          DateTime.utc(2026, 12, 1, 0),
          DateTime.utc(2026, 12, 2, 0),
          SeparatorGrain.month,
        ),
        isFalse,
      );
    });

    test('the week turns over on Monday, not on the first candle of a day', () {
      // 2026-11-01 is a Sunday, so the following midnight starts a new week.
      expect(
        isPeriodBoundary(
          DateTime.utc(2026, 11, 1, 23),
          DateTime.utc(2026, 11, 2, 0),
          SeparatorGrain.week,
        ),
        isTrue,
      );
      expect(
        isPeriodBoundary(
          DateTime.utc(2026, 11, 3, 0),
          DateTime.utc(2026, 11, 4, 0),
          SeparatorGrain.week,
        ),
        isFalse,
      );
    });
  });

  group('separator indices', () {
    test('only the candle that opens a new day is marked', () {
      final times = [
        utc(2, 22),
        utc(2, 23),
        utc(3, 0),
        utc(3, 1),
      ];
      expect(
        periodSeparatorIndices(times, SeparatorGrain.day).toList(),
        [2],
      );
    });

    test('the first candle is never a separator', () {
      expect(
        periodSeparatorIndices([utc(2, 0), utc(2, 1)], SeparatorGrain.day),
        isEmpty,
      );
    });

    test('a single candle cannot produce a boundary', () {
      expect(
        periodSeparatorIndices([utc(2, 0)], SeparatorGrain.day),
        isEmpty,
      );
    });
  });
}
