import 'package:intl/intl.dart';

import '../models/models.dart';

/// One calendar month of realised P&L, for the monthly bars on Analytics.
class MonthTotal {
  const MonthTotal({
    required this.key,
    required this.pnl,
    required this.trades,
  });

  /// `2026-10`.
  final String key;
  final double pnl;
  final int trades;

  bool get isEmpty => trades == 0;
}

final DateFormat _monthLabel = DateFormat('MMM yy');

DateTime monthStart(DateTime date) => DateTime(date.year, date.month);

DateTime addMonths(DateTime date, int delta) =>
    DateTime(date.year, date.month + delta);

/// `2026-10-28`, the shape `daily_pnl` and `day_trades` return.
String isoDay(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime? parseDay(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// `2026-10` → `Oct 26`.
String monthLabel(String key) {
  final parsed = DateTime.tryParse('$key-01');
  return parsed == null ? key : _monthLabel.format(parsed);
}

/// Groups daily rows into the last [months] calendar months, oldest first.
/// Months without trades are kept, so the bars stay evenly spaced.
List<MonthTotal> monthTotals(
  List<DailyPnlPoint> points, {
  int months = 6,
  DateTime? now,
}) {
  final totals = <String, MonthTotal>{};
  for (final point in points) {
    if (point.day.length < 7) continue;
    final key = point.day.substring(0, 7);
    final current = totals[key];
    totals[key] = MonthTotal(
      key: key,
      pnl: (current?.pnl ?? 0) + point.pnl,
      trades: (current?.trades ?? 0) + point.trades,
    );
  }

  final anchor = monthStart(now ?? DateTime.now());
  return List<MonthTotal>.generate(months, (index) {
    final month = addMonths(anchor, index - (months - 1));
    final key = '${month.year.toString().padLeft(4, '0')}-'
        '${month.month.toString().padLeft(2, '0')}';
    return totals[key] ?? MonthTotal(key: key, pnl: 0, trades: 0);
  });
}

/// The last [days] days ending today, oldest first, with a zero row for days
/// without trades.
List<DailyPnlPoint> recentDays(
  List<DailyPnlPoint> points, {
  int days = 30,
  DateTime? now,
}) {
  final byDay = {for (final point in points) point.day: point};
  final anchor = now ?? DateTime.now();
  final today = DateTime(anchor.year, anchor.month, anchor.day);
  return List<DailyPnlPoint>.generate(days, (index) {
    final date = today.subtract(Duration(days: days - 1 - index));
    final key = isoDay(date);
    return byDay[key] ?? DailyPnlPoint(day: key, pnl: 0, trades: 0);
  });
}

DailyPnlPoint? bestDay(List<DailyPnlPoint> points) {
  final traded = points.where((point) => point.trades > 0).toList();
  if (traded.isEmpty) return null;
  return traded.reduce((a, b) => b.pnl > a.pnl ? b : a);
}

DailyPnlPoint? worstDay(List<DailyPnlPoint> points) {
  final traded = points.where((point) => point.trades > 0).toList();
  if (traded.isEmpty) return null;
  return traded.reduce((a, b) => b.pnl < a.pnl ? b : a);
}

/// A month laid out as weeks of seven cells; `null` pads the leading and
/// trailing blanks so day 1 lands under its weekday (Monday first).
List<DateTime?> monthGrid(DateTime month) {
  final first = monthStart(month);
  final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
  final leading = first.weekday - DateTime.monday;

  final cells = <DateTime?>[
    ...List<DateTime?>.filled(leading, null),
    for (var day = 1; day <= daysInMonth; day++)
      DateTime(first.year, first.month, day),
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return cells;
}

/// Month-to-date and per-week rollups used by the calendar header.
({double pnl, int trades, int days}) monthSummary(
  List<DailyPnlPoint> points,
  DateTime month,
) {
  final prefix = '${month.year.toString().padLeft(4, '0')}-'
      '${month.month.toString().padLeft(2, '0')}';
  var pnl = 0.0;
  var trades = 0;
  var days = 0;
  for (final point in points) {
    if (!point.day.startsWith(prefix) || point.trades == 0) continue;
    pnl += point.pnl;
    trades += point.trades;
    days++;
  }
  return (pnl: pnl, trades: trades, days: days);
}
