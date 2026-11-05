import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/edge.dart';
import '../core/format.dart';
import '../models/models.dart';
import '../services/journal_api.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class EdgeScreen extends StatefulWidget {
  const EdgeScreen({super.key, required this.api});

  final JournalApi api;

  @override
  State<EdgeScreen> createState() => _EdgeScreenState();
}

class _EdgeScreenState extends State<EdgeScreen> {
  late Future<TimeStats> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.timeStats();
  }

  Future<void> _refresh() async {
    final next = widget.api.timeStats();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {
      // The FutureBuilder renders the error and retry affordance.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edge'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh, size: 20, color: AppColors.muted),
          ),
        ],
      ),
      body: FutureBuilder<TimeStats>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: AppColors.danger,
                      size: 26,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Could not load the edge report',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.faint,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final stats = snapshot.data ?? TimeStats.empty;
          final hours = hourlySeries(stats);
          final edge = timeEdgeReport(stats);
          final sessions = stats.sessions.map(sessionPeriod).toList();
          final hasData = hours.any((row) => row.trades > 0);

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 110),
              children: [
                FlatCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'WHEN YOU WIN',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'The journal ranks every entry hour and session by realised P&L.',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 11.5,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Pill(text: '${stats.timezone} TIME', tone: Tone.neutral),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (!hasData)
                  const FlatCard(
                    child: EmptyState(
                      icon: Icons.schedule,
                      title: 'No time windows yet',
                      body:
                          'Open a trade and set the entry and exit time. The hour and session report is built from that window.',
                    ),
                  )
                else ...[
                  // Two labelled pairs instead of four identical cards in one
                  // stack, so it is obvious which two compare hours and which
                  // two compare sessions.
                  const _GroupLabel('Time of day'),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.35,
                    children: [
                      _EdgeCard(
                        title: 'Most profitable hour',
                        period: edge.bestHour,
                        positive: true,
                      ),
                      _EdgeCard(
                        title: 'Most losses',
                        period: edge.worstHour,
                        positive: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const _GroupLabel('Sessions'),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.35,
                    children: [
                      _EdgeCard(
                        title: 'Best session',
                        period: edge.bestSession,
                        positive: true,
                      ),
                      _EdgeCard(
                        title: 'Weakest session',
                        period: edge.worstSession,
                        positive: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FlatCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle(
                          title: 'P&L by entry hour',
                          subtitle:
                              '24-hour clock in your timezone; sessions use UTC.',
                        ),
                        const SizedBox(height: 12),
                        SizedBox(height: 190, child: _HourChart(hours: hours)),
                        const SizedBox(height: 8),
                        Text(
                          'Windows with fewer than ${edge.minTrades} trades are excluded from best/worst. '
                          'Median hold ${durationText(stats.medianMinutes)} across ${stats.holdTrades} timed trades.',
                          style: TextStyle(
                            color: AppColors.faint,
                            fontSize: 9.5,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  FlatCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(14, 14, 14, 4),
                          child: SectionTitle(
                            title: 'Sessions',
                            subtitle:
                                'UTC market windows: Asian 00–08 · London 08–13 · overlap 13–16 · New York 16–21 · late 21–24.',
                          ),
                        ),
                        const SizedBox(height: 4),
                        for (final session in sessions)
                          Column(
                            children: [
                              _SessionRow(
                                period: session,
                                best: edge.bestSession?.key == session.key,
                                worst: edge.worstSession?.key == session.key,
                              ),
                              const ListDivider(),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The label above a pair of comparison cards.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: AppColors.faint,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _EdgeCard extends StatelessWidget {
  const _EdgeCard({
    required this.title,
    required this.period,
    required this.positive,
  });

  final String title;
  final EdgePeriod? period;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = positive ? AppColors.success : AppColors.danger;
    return FlatCard(
      borderColor: color.withAlpha(55),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Icon(
                positive ? Icons.trending_up : Icons.trending_down,
                size: 13,
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            period?.label ?? 'Need 3+ trades',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const Spacer(),
          Text(
            period == null ? '—' : signedMoney(period!.pnl),
            style: tabular.copyWith(
              color: period == null ? AppColors.faint : color,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            period == null
                ? 'Not enough sample'
                : '${period!.trades} trades · ${percent(period!.winRate)} win',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.faint, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _HourChart extends StatelessWidget {
  const _HourChart({required this.hours});

  final List<EdgePeriod> hours;

  @override
  Widget build(BuildContext context) {
    final values = hours.map((row) => row.pnl).toList();
    final highest = values.reduce((a, b) => math.max(a, b));
    final lowest = values.reduce((a, b) => math.min(a, b));
    final maxY = math.max(highest, 0.0) + 1;
    final minY = math.min(lowest, 0.0) - 1;

    return BarChart(
      BarChartData(
        minY: minY,
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: AppColors.border, strokeWidth: 1),
        ),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => AppColors.surfaceAlt,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${group.x}:00\n${signedMoney(rod.toY)}',
                TextStyle(color: AppColors.text, fontSize: 10),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (value, meta) => Text(
                compactMoney(value),
                style: TextStyle(color: AppColors.faint, fontSize: 8.5),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 18,
              // Only every third hour has room; the chart otherwise prints all
              // 24 labels on top of each other.
              getTitlesWidget: (value, meta) {
                final hour = value.round();
                if (hour % 3 != 0) return const SizedBox.shrink();
                return Text(
                  '${hour}h',
                  style: TextStyle(color: AppColors.faint, fontSize: 8.5),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var index = 0; index < hours.length; index++)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: hours[index].pnl,
                  width: 6,
                  borderRadius: BorderRadius.zero,
                  color: hours[index].pnl >= 0
                      ? AppColors.success
                      : AppColors.danger,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.period,
    required this.best,
    required this.worst,
  });

  final EdgePeriod period;
  final bool best;
  final bool worst;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        period.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (best) ...[
                      const SizedBox(width: 5),
                      const Pill(text: 'BEST', tone: Tone.positive),
                    ],
                    if (worst) ...[
                      const SizedBox(width: 5),
                      const Pill(text: 'WEAK', tone: Tone.negative),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${period.trades} trades · ${percent(period.winRate)} win rate',
                  style: TextStyle(color: AppColors.faint, fontSize: 9.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            signedMoney(period.pnl),
            style: tabular.copyWith(
              color: period.pnl >= 0 ? AppColors.success : AppColors.danger,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
