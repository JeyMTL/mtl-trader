import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/analytics.dart';
import '../core/format.dart';
import '../models/models.dart';
import '../services/journal_api.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Web parity for the Calendar page: one month of daily P&L, with the trades
/// behind any day one tap away.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.api,
    required this.onEdit,
    this.initialDay,
  });

  final JournalApi api;
  final ValueChanged<String> onEdit;

  /// Opens on this day's month when the caller already knows it.
  final DateTime? initialDay;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month = monthStart(widget.initialDay ?? DateTime.now());
  late Future<List<DailyPnlPoint>> _future = _load();

  static final DateFormat _monthTitle = DateFormat('MMMM yyyy');

  Future<List<DailyPnlPoint>> _load() {
    final start = monthStart(_month);
    final end = DateTime(start.year, start.month + 1, 0);
    return widget.api.dailyPnl(start, end);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {
      // The FutureBuilder renders the error and retry affordance.
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = addMonths(_month, delta);
      _future = _load();
    });
  }

  Future<void> _jumpToLatest() async {
    try {
      final latest = await widget.api.latestTradeDay();
      if (!mounted || latest == null) return;
      setState(() {
        _month = monthStart(latest);
        _future = _load();
      });
    } catch (_) {
      // Keep the current month when the lookup fails.
    }
  }

  Future<void> _openDay(DateTime day, DailyPnlPoint point) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetContext) => _DaySheet(
        api: widget.api,
        day: day,
        point: point,
        onEdit: (id) {
          Navigator.of(sheetContext).pop();
          widget.onEdit(id);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DailyPnlPoint>>(
      future: _future,
      builder: (context, snapshot) {
        final points = snapshot.data ?? const <DailyPnlPoint>[];
        final byDay = {for (final point in points) point.day: point};
        final summary = monthSummary(points, _month);
        final grid = monthGrid(_month);

        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 110),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Calendar',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _jumpToLatest,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Latest',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              FlatCard(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => _shiftMonth(-1),
                          tooltip: 'Previous month',
                          icon: Icon(
                            Icons.chevron_left,
                            size: 20,
                            color: AppColors.muted,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                _monthTitle.format(_month),
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                summary.trades == 0
                                    ? 'No trades'
                                    : '${signedMoney(summary.pnl)} · '
                                        '${summary.trades}T · '
                                        '${summary.days} days',
                                style: TextStyle(
                                  color: summary.trades == 0
                                      ? AppColors.faint
                                      : (summary.pnl >= 0
                                          ? AppColors.success
                                          : AppColors.danger),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _shiftMonth(1),
                          tooltip: 'Next month',
                          icon: Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final label in const [
                          'M',
                          'T',
                          'W',
                          'T',
                          'F',
                          'S',
                          'S',
                        ])
                          Expanded(
                            child: Center(
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: AppColors.faint,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (snapshot.hasError)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            Text(
                              'Could not load this month',
                              style: TextStyle(
                                color: AppColors.faint,
                                fontSize: 11.5,
                              ),
                            ),
                            TextButton(
                              onPressed: _refresh,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    else
                      for (var index = 0; index < grid.length; index += 7)
                        Row(
                          children: [
                            for (var offset = 0; offset < 7; offset++)
                              Expanded(
                                child: _DayCell(
                                  day: grid[index + offset],
                                  point: grid[index + offset] == null
                                      ? null
                                      : byDay[isoDay(grid[index + offset]!)],
                                  onTap: _openDay,
                                ),
                              ),
                          ],
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const _Legend(),
            ],
          ),
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.point, required this.onTap});

  final DateTime? day;
  final DailyPnlPoint? point;
  final void Function(DateTime day, DailyPnlPoint point) onTap;

  @override
  Widget build(BuildContext context) {
    final date = day;
    if (date == null) {
      return const SizedBox(height: 46);
    }
    final hasTrades = point != null && point!.trades > 0;
    final positive = (point?.pnl ?? 0) >= 0;
    final tint = hasTrades
        ? (positive ? AppColors.success : AppColors.danger)
        : AppColors.border;

    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: InkWell(
        onTap: hasTrades ? () => onTap(date, point!) : null,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
          decoration: BoxDecoration(
            color: hasTrades
                ? tint.withValues(alpha: positive ? 0.14 : 0.16)
                : Colors.transparent,
            borderRadius: const BorderRadius.all(Radius.circular(4)),
            border: Border.all(
              color: hasTrades ? tint.withValues(alpha: 0.35) : AppColors.border,
            ),
          ),
          child: Column(
            children: [
              Text(
                '${date.day}',
                style: TextStyle(
                  color: hasTrades ? AppColors.text : AppColors.faint,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (hasTrades)
                Text(
                  compactMoney(point!.pnl),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    color: positive ? AppColors.success : AppColors.danger,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.16),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
            borderRadius: const BorderRadius.all(Radius.circular(2)),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Winning day',
          style: TextStyle(color: AppColors.faint, fontSize: 10.5),
        ),
        const SizedBox(width: 14),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.16),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
            borderRadius: const BorderRadius.all(Radius.circular(2)),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Losing day',
          style: TextStyle(color: AppColors.faint, fontSize: 10.5),
        ),
      ],
    );
  }
}

class _DaySheet extends StatelessWidget {
  const _DaySheet({
    required this.api,
    required this.day,
    required this.point,
    required this.onEdit,
  });

  final JournalApi api;
  final DateTime day;
  final DailyPnlPoint point;
  final ValueChanged<String> onEdit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    longDay(day),
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  signedMoney(point.pnl),
                  style: TextStyle(
                    color: point.pnl >= 0 ? AppColors.success : AppColors.danger,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${point.trades} ${point.trades == 1 ? 'trade' : 'trades'}',
              style: TextStyle(color: AppColors.faint, fontSize: 11),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: FutureBuilder<List<TradeRow>>(
                future: api.dayTrades(day),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    );
                  }
                  final trades = snapshot.data ?? const <TradeRow>[];
                  if (snapshot.hasError || trades.isEmpty) {
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'No trades loaded for this day.',
                        style: TextStyle(color: AppColors.faint, fontSize: 11.5),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: trades.length,
                    separatorBuilder: (_, __) => const ListDivider(),
                    itemBuilder: (context, index) {
                      final trade = trades[index];
                      return InkWell(
                        onTap: () => onEdit(trade.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: (trade.type.toUpperCase() == 'BUY'
                                          ? AppColors.success
                                          : AppColors.danger)
                                      .withValues(alpha: 0.14),
                                  borderRadius: const BorderRadius.all(
                                    Radius.circular(3),
                                  ),
                                ),
                                child: Text(
                                  trade.type.toUpperCase(),
                                  style: TextStyle(
                                    color: trade.type.toUpperCase() == 'BUY'
                                        ? AppColors.success
                                        : AppColors.danger,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      trade.symbol,
                                      style: TextStyle(
                                        color: AppColors.text,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      trade.strategy?.isNotEmpty == true
                                          ? trade.strategy!
                                          : trade.timeWindow ?? '—',
                                      style: TextStyle(
                                        color: AppColors.faint,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                signedMoney(trade.pnl),
                                style: TextStyle(
                                  color: trade.pnl >= 0
                                      ? AppColors.success
                                      : AppColors.danger,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: AppColors.faint,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
