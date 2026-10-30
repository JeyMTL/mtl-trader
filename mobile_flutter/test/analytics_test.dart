import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/analytics.dart';
import 'package:mtl_trader_mobile/models/models.dart';

DailyPnlPoint point(String day, double pnl, int trades) =>
    DailyPnlPoint(day: day, pnl: pnl, trades: trades);

void main() {
  group('monthTotals', () {
    test('groups days into months and keeps empty months', () {
      final totals = monthTotals(
        [
          point('2026-08-03', 120, 2),
          point('2026-08-20', -20, 1),
          point('2026-10-01', 50, 1),
        ],
        months: 3,
        now: DateTime(2026, 10, 28),
      );

      expect(totals.map((month) => month.key), ['2026-08', '2026-09', '2026-10']);
      expect(totals[0].pnl, 100);
      expect(totals[0].trades, 3);
      expect(totals[1].isEmpty, isTrue);
      expect(totals[2].pnl, 50);
    });

    test('ignores points outside the window', () {
      final totals = monthTotals(
        [point('2026-01-05', 900, 4), point('2026-10-05', 10, 1)],
        months: 2,
        now: DateTime(2026, 10, 28),
      );

      expect(totals.length, 2);
      expect(totals.fold<double>(0, (sum, month) => sum + month.pnl), 10);
    });
  });

  group('recentDays', () {
    test('returns a zero row for days without trades and ends today', () {
      final days = recentDays(
        [point('2026-10-26', 75, 2)],
        days: 5,
        now: DateTime(2026, 10, 28),
      );

      expect(days.length, 5);
      expect(days.first.day, '2026-10-24');
      expect(days.last.day, '2026-10-28');
      expect(days[2].pnl, 75);
      expect(days[2].trades, 2);
      expect(days.last.trades, 0);
    });
  });

  group('best and worst day', () {
    test('ignore days with no trades', () {
      final days = [
        point('2026-10-01', -400, 1),
        point('2026-10-02', 250, 2),
        point('2026-10-03', 0, 0),
      ];

      expect(bestDay(days)!.day, '2026-10-02');
      expect(worstDay(days)!.day, '2026-10-01');
    });

    test('return null when nothing traded', () {
      expect(bestDay([point('2026-10-01', 0, 0)]), isNull);
      expect(worstDay(const []), isNull);
    });
  });

  group('monthGrid', () {
    test('pads the leading blanks and completes whole weeks', () {
      final grid = monthGrid(DateTime(2026, 10));

      // 1 October 2026 is a Thursday, so Monday-first leaves three blanks.
      expect(grid.take(3), everyElement(isNull));
      expect(grid[3], DateTime(2026, 10, 1));
      expect(grid.length % 7, 0);
      expect(grid.whereType<DateTime>().length, 31);
    });

    test('starts on the first cell when the month begins on a Monday', () {
      // 1 June 2026 is a Monday.
      final grid = monthGrid(DateTime(2026, 6));
      expect(grid.first, DateTime(2026, 6, 1));
    });
  });

  test('monthSummary only counts the requested month', () {
    final summary = monthSummary(
      [
        point('2026-09-30', 500, 3),
        point('2026-10-01', 40, 1),
        point('2026-10-01', 10, 0),
        point('2026-10-15', -15, 2),
      ],
      DateTime(2026, 10),
    );

    expect(summary.pnl, 25);
    expect(summary.trades, 3);
    expect(summary.days, 2);
  });

  test('monthLabel and isoDay use the shapes Postgres returns', () {
    expect(isoDay(DateTime(2026, 3, 7)), '2026-03-07');
    expect(monthLabel('2026-10'), 'Oct 26');
  });
}
