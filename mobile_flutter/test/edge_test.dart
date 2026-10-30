import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/edge.dart';
import 'package:mtl_trader_mobile/models/models.dart';

void main() {
  const stats = TimeStats(
    timezone: 'Europe/London',
    hours: [
      HourStat(hour: 8, trades: 5, wins: 4, losses: 1, pnl: 420),
      HourStat(hour: 9, trades: 4, wins: 3, losses: 1, pnl: 180),
      HourStat(hour: 14, trades: 6, wins: 1, losses: 5, pnl: -360),
      HourStat(hour: 22, trades: 1, wins: 1, losses: 0, pnl: 900),
    ],
    sessions: [
      SessionStat(
        session: 'London',
        firstHour: 8,
        lastHour: 12,
        trades: 9,
        wins: 7,
        losses: 2,
        pnl: 600,
      ),
      SessionStat(
        session: 'New York',
        firstHour: 16,
        lastHour: 20,
        trades: 6,
        wins: 2,
        losses: 4,
        pnl: -260,
      ),
    ],
    holdTrades: 12,
    medianMinutes: 95,
    averageMinutes: 120,
  );

  test('formats hour ranges', () {
    expect(hourRange(8), '08:00–09:00');
    expect(hourRange(23), '23:00–24:00');
    expect(hourRange(-1), '00:00–01:00');
  });

  test('builds a 24-hour series with zero buckets', () {
    final series = hourlySeries(stats);
    expect(series, hasLength(24));
    expect(series[8].pnl, 420);
    expect(series[8].winRate, 80);
    expect(series[3].trades, 0);
    expect(series[3].label, '03:00–04:00');
  });

  test('ignores small samples and picks best/worst', () {
    final report = timeEdgeReport(stats);
    expect(report.bestHour?.label, '08:00–09:00');
    expect(report.worstHour?.label, '14:00–15:00');
    expect(report.bestSession?.label, 'London (08:00–13:00)');
    expect(report.worstSession?.label, 'New York (16:00–21:00)');
  });

  test('returns no best window when every qualifying window loses', () {
    final report = timeEdgeReport(
      const TimeStats(
        timezone: 'UTC',
        hours: [
          HourStat(hour: 1, trades: 4, wins: 1, losses: 3, pnl: -20),
          HourStat(hour: 2, trades: 5, wins: 1, losses: 4, pnl: -80),
        ],
        sessions: [],
        holdTrades: 0,
        medianMinutes: null,
        averageMinutes: null,
      ),
    );
    expect(report.bestHour, isNull);
    expect(report.worstHour?.pnl, -80);
  });
}
