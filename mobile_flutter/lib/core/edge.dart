import '../models/models.dart';

class EdgePeriod {
  const EdgePeriod({
    required this.key,
    required this.label,
    required this.trades,
    required this.wins,
    required this.losses,
    required this.pnl,
  });

  final String key;
  final String label;
  final int trades;
  final int wins;
  final int losses;
  final double pnl;

  double get winRate => trades > 0 ? (wins / trades) * 100 : 0;
}

class EdgeReport {
  const EdgeReport({
    this.bestHour,
    this.worstHour,
    this.bestSession,
    this.worstSession,
    this.minTrades = 3,
  });

  final EdgePeriod? bestHour;
  final EdgePeriod? worstHour;
  final EdgePeriod? bestSession;
  final EdgePeriod? worstSession;
  final int minTrades;
}

String hourRange(int hour) {
  final start = hour.clamp(0, 23).toInt();
  final end = start == 23 ? 24 : start + 1;
  return '${start.toString().padLeft(2, '0')}:00–${end.toString().padLeft(2, '0')}:00';
}

EdgePeriod hourPeriod(HourStat row) => EdgePeriod(
      key: 'hour-${row.hour}',
      label: hourRange(row.hour),
      trades: row.trades,
      wins: row.wins,
      losses: row.losses,
      pnl: row.pnl,
    );

EdgePeriod sessionPeriod(SessionStat row) => EdgePeriod(
      key: 'session-${row.session}',
      label: '${row.session} (${row.firstHour.toString().padLeft(2, '0')}:00–'
          '${(row.lastHour + 1).toString().padLeft(2, '0')}:00)',
      trades: row.trades,
      wins: row.wins,
      losses: row.losses,
      pnl: row.pnl,
    );

/// A full 24-hour series so quiet hours keep their place on the chart.
List<EdgePeriod> hourlySeries(TimeStats stats) {
  final byHour = <int, HourStat>{for (final row in stats.hours) row.hour: row};
  return List.generate(24, (hour) {
    final row = byHour[hour];
    return hourPeriod(
      row ?? HourStat(hour: hour, trades: 0, wins: 0, losses: 0, pnl: 0),
    );
  });
}

EdgeReport timeEdgeReport(TimeStats stats, {int minTrades = 3}) {
  final hours = _pick(hourlySeries(stats), minTrades);
  final sessions = _pick(stats.sessions.map(sessionPeriod).toList(), minTrades);
  return EdgeReport(
    bestHour: hours.$1,
    worstHour: hours.$2,
    bestSession: sessions.$1,
    worstSession: sessions.$2,
    minTrades: minTrades,
  );
}

(EdgePeriod?, EdgePeriod?) _pick(List<EdgePeriod> periods, int minTrades) {
  final eligible = periods.where((row) => row.trades >= minTrades).toList();
  if (eligible.isEmpty) return (null, null);

  var best = eligible.first;
  var worst = eligible.first;
  for (final row in eligible) {
    if (row.pnl > best.pnl) best = row;
    if (row.pnl < worst.pnl) worst = row;
  }
  return (best.pnl > 0 ? best : null, worst.pnl < 0 ? worst : null);
}
