import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/edge.dart';
import '../core/format.dart';
import '../models/models.dart';
import '../services/journal_api.dart';
import '../ui/theme.dart';
import 'subscription_screen.dart';
import '../ui/widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.api,
    required this.onOpenEdge,
    required this.onEdit,
  });

  final JournalApi api;
  final VoidCallback onOpenEdge;
  final ValueChanged<String> onEdit;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.dashboard();
  }

  Future<void> _refresh() async {
    final next = widget.api.dashboard();
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
        centerTitle: true,
        title: _BrandMark(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SubscriptionScreen(api: widget.api),
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh, size: 20, color: AppColors.muted),
          ),
        ],
      ),
      body: FutureBuilder<DashboardData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          if (snapshot.hasError) {
            return _LoadError(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final data = snapshot.data;
          if (data == null) return const SizedBox.shrink();
          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            child: _DashboardBody(
              data: data,
              onOpenEdge: widget.onOpenEdge,
              onEdit: widget.onEdit,
            ),
          );
        },
      ),
    );
  }
}

/// The centred MTL wordmark. It breathes slowly so the header has a focal
/// point, and tapping it is the shortcut to the payment plans.
class _BrandMark extends StatefulWidget {
  const _BrandMark({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<_BrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  late final Animation<double> _pulse = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'MTL Trader — open payment plans',
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final t = _pulse.value;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scale: 1 + t * 0.05,
                        child: Text(
                          'MTL',
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.8 + t * 1.4,
                            shadows: [
                              Shadow(
                                color: AppColors.primary.withAlpha(
                                  (36 + 54 * t).round(),
                                ),
                                blurRadius: 8 + 10 * t,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(
                            (120 + 135 * t).round(),
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    longDay(DateTime.now()),
                    style: TextStyle(
                      color: AppColors.faint,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.data,
    required this.onOpenEdge,
    required this.onEdit,
  });

  final DashboardData data;
  final VoidCallback onOpenEdge;
  final ValueChanged<String> onEdit;

  @override
  Widget build(BuildContext context) {
    final summary = data.summary;
    final edge = timeEdgeReport(data.timeStats);
    final hours = hourlySeries(data.timeStats);
    final drawdown = _maxDrawdown(data.equity, data.deposits);
    final hasHours = hours.any((row) => row.trades > 0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 110),
      children: [
        if (summary.totalTrades == 0) ...[
          _StartCard(onOpenEdge: onOpenEdge),
          const SizedBox(height: 10),
        ],
        FlatCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'ACCOUNT BALANCE',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  Pill(
                    text: summary.totalPnl >= 0 ? 'IN PROFIT' : 'IN DRAWDOWN',
                    tone: summary.totalPnl >= 0 ? Tone.positive : Tone.negative,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  money(data.balance),
                  style: tabular.copyWith(
                    color: AppColors.text,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${signedMoney(summary.totalPnl)} net · ${summary.totalTrades} closed · '
                '${summary.wins}W / ${summary.losses}L',
                style: TextStyle(color: AppColors.muted, fontSize: 11.5),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 116,
                child: data.equity.isEmpty
                    ? Center(
                        child: Text(
                          'Import history to plot the curve',
                          style: TextStyle(
                            color: AppColors.faint,
                            fontSize: 11,
                          ),
                        ),
                      )
                    : _EquityChart(
                        points: data.equity,
                        deposits: data.deposits,
                      ),
              ),
              const SizedBox(height: 12),
              const ListDivider(),
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                      label: 'Deposits',
                      value: money(data.deposits),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniStat(
                      label: 'Best trade',
                      value: summary.totalTrades > 0
                          ? signedMoney(summary.bestTrade)
                          : '—',
                      tone: summary.totalTrades > 0
                          ? Tone.positive
                          : Tone.muted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniStat(
                      label: 'Worst trade',
                      value: summary.totalTrades > 0
                          ? signedMoney(summary.worstTrade)
                          : '—',
                      tone: summary.totalTrades > 0
                          ? Tone.negative
                          : Tone.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.72,
          children: [
            MetricCard(
              label: 'Win rate',
              value: percent(summary.winRate),
              foot: '${summary.wins} winners',
              icon: Icons.track_changes,
            ),
            MetricCard(
              label: 'Profit factor',
              value: summary.profitFactor > 0
                  ? summary.profitFactor.toStringAsFixed(2)
                  : '—',
              foot:
                  '${money(summary.grossProfit)} / ${money(summary.grossLoss)}',
              icon: Icons.balance,
            ),
            MetricCard(
              label: 'Max drawdown',
              value: '${drawdown.toStringAsFixed(1)}%',
              foot: 'Peak to trough',
              tone: drawdown >= 10 ? Tone.negative : Tone.neutral,
              icon: Icons.trending_down,
            ),
            MetricCard(
              label: 'Avg / trade',
              value:
                  summary.totalTrades > 0 ? money(summary.averageTrade) : '—',
              foot: 'Expectancy',
              tone: summary.averageTrade >= 0 ? Tone.positive : Tone.negative,
              icon: Icons.functions,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _MonthCard(summary: summary),
        const SizedBox(height: 10),
        FlatCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                title: 'Time edge',
                subtitle:
                    'Entry hours in ${data.timeStats.timezone}; sessions in UTC. '
                    'Median hold ${durationText(data.timeStats.medianMinutes)}.',
                trailing: TextButton(
                  onPressed: onOpenEdge,
                  child: const Text('Report'),
                ),
              ),
              const SizedBox(height: 4),
              if (!hasHours)
                const EmptyState(
                  icon: Icons.schedule,
                  title: 'No timed trades yet',
                  body:
                      'Set the entry and exit time on a trade. The hour and session report builds itself from that window.',
                )
              else ...[
                _EdgeRow(
                  label: 'Most profitable hour',
                  period: edge.bestHour,
                  positive: true,
                ),
                const ListDivider(),
                _EdgeRow(
                  label: 'Most losses',
                  period: edge.worstHour,
                  positive: false,
                ),
                const ListDivider(),
                _EdgeRow(
                  label: 'Best session',
                  period: edge.bestSession,
                  positive: true,
                ),
                const ListDivider(),
                _EdgeRow(
                  label: 'Weakest session',
                  period: edge.worstSession,
                  positive: false,
                ),
                const SizedBox(height: 8),
                SizedBox(height: 84, child: _HourChart(hours: hours)),
                const SizedBox(height: 4),
                Text(
                  'Hours with fewer than 3 trades are left out of the best/worst call.',
                  style: TextStyle(
                    color: AppColors.faint,
                    fontSize: 9.5,
                    height: 1.4,
                  ),
                ),
              ],
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
                padding: EdgeInsets.fromLTRB(14, 14, 14, 6),
                child: SectionTitle(
                  title: 'Journal',
                  subtitle:
                      'The notes, screenshots and voice notes behind the fills.',
                ),
              ),
              if (data.journalFeed.isEmpty)
                const EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: 'Nothing journaled yet',
                  body:
                      'Open a trade and add a screenshot or a voice note — it becomes the entry you read later.',
                )
              else
                ...data.journalFeed.map(
                  (entry) => Column(
                    children: [
                      _JournalRow(entry: entry, onTap: () => onEdit(entry.id)),
                      const ListDivider(),
                    ],
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
                padding: EdgeInsets.fromLTRB(14, 14, 14, 6),
                child: SectionTitle(title: 'Recent fills'),
              ),
              if (data.recentTrades.isEmpty)
                const EmptyState(
                  icon: Icons.show_chart,
                  title: 'No fills recorded',
                )
              else
                ...data.recentTrades.map(
                  (trade) => Column(
                    children: [
                      InkWell(
                        onTap: () => onEdit(trade.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Pill(
                                text: trade.type,
                                tone: trade.type == 'BUY'
                                    ? Tone.positive
                                    : Tone.negative,
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
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      dayOf(trade.tradedAt),
                                      style: TextStyle(
                                        color: AppColors.faint,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                signedMoney(trade.pnl),
                                style: tabular.copyWith(
                                  color: trade.pnl >= 0
                                      ? AppColors.success
                                      : AppColors.danger,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const ListDivider(),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EquityChart extends StatelessWidget {
  const _EquityChart({required this.points, required this.deposits});

  final List<EquityPoint> points;
  final double deposits;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (var index = 0; index < points.length; index++)
        FlSpot(index.toDouble(), deposits + points[index].cumulative),
    ];
    final values = spots.map((spot) => spot.y).toList();
    final minValue = values.reduce((a, b) => math.min(a, b));
    final maxValue = values.reduce((a, b) => math.max(a, b));
    final padding = math.max((maxValue - minValue) * 0.12, 1.0);
    final profit = (spots.last.y - spots.first.y) >= 0;
    final color = profit ? AppColors.success : AppColors.danger;
    final interval = math.max(1.0, (points.length / 4).floorToDouble());

    return LineChart(
      LineChartData(
        minY: minValue - padding,
        maxY: maxValue + padding,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: AppColors.border, strokeWidth: 1),
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
                style: TextStyle(color: AppColors.faint, fontSize: 9),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: interval,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    isoDayLabel(points[index].day),
                    style: TextStyle(color: AppColors.faint, fontSize: 9),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: color,
            barWidth: 2,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: color.withAlpha(18)),
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
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 16,
              interval: 6,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}h',
                style: TextStyle(color: AppColors.faint, fontSize: 8.5),
              ),
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
                  width: 5,
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

class _EdgeRow extends StatelessWidget {
  const _EdgeRow({
    required this.label,
    required this.period,
    required this.positive,
  });

  final String label;
  final EdgePeriod? period;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = positive ? AppColors.success : AppColors.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.faint,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  period?.label ?? 'Needs 3+ trades',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                period == null ? '—' : signedMoney(period!.pnl),
                style: tabular.copyWith(
                  color: period == null ? AppColors.faint : color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                period == null
                    ? '—'
                    : '${period!.trades} trades · ${percent(period!.winRate)} win',
                style: TextStyle(color: AppColors.faint, fontSize: 9.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _JournalRow extends StatelessWidget {
  const _JournalRow({required this.entry, required this.onTap});

  final JournalEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Pill(
                  text: entry.type,
                  tone: entry.type == 'BUY' ? Tone.positive : Tone.negative,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.symbol,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  signedMoney(entry.pnl),
                  style: tabular.copyWith(
                    color:
                        entry.pnl >= 0 ? AppColors.success : AppColors.danger,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (entry.notes != null) ...[
              const SizedBox(height: 4),
              Text(
                entry.notes!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                if (entry.imageCount > 0) ...[
                  Icon(
                    Icons.image_outlined,
                    size: 11,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${entry.imageCount}',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 9.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (entry.audioCount > 0) ...[
                  Icon(
                    Icons.mic_none,
                    size: 11,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${entry.audioCount}',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 9.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    [
                      '${timeOf(entry.openTime)} → ${timeOf(entry.closeTime)}',
                      if (entry.strategy != null) entry.strategy!,
                      if (entry.tags.isNotEmpty)
                        entry.tags.take(2).map((tag) => '#$tag').join(' '),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.faint,
                      fontSize: 9.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard({required this.onOpenEdge});

  final VoidCallback onOpenEdge;

  @override
  Widget build(BuildContext context) {
    return FlatCard(
      borderColor: AppColors.primary.withAlpha(80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'START HERE',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Three steps to a journal that pays you back.',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          const _StartStep(
            number: '1',
            text: 'Import MT5 history or log your first fill.',
          ),
          const _StartStep(
            number: '2',
            text: 'Add the entry and exit time — that powers the edge report.',
          ),
          const _StartStep(
            number: '3',
            text: 'Attach the chart screenshot and a voice note.',
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onOpenEdge,
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: const Text('See the time report →'),
          ),
        ],
      ),
    );
  }
}

class _StartStep extends StatelessWidget {
  const _StartStep({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 16,
            height: 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary.withAlpha(90)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              number,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppColors.danger, size: 26),
            const SizedBox(height: 10),
            Text(
              'Could not load the desk',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
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
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// One column of the statement strip under the equity curve.
class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    this.tone = Tone.neutral,
  });

  final String label;
  final String value;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.faint,
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: tabular.copyWith(
              color: toneColor(tone),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// Current-month scoreboard: the desk shows the month you are trading in, not
/// only the all-time totals.
class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.summary});

  final TradeSummary summary;

  @override
  Widget build(BuildContext context) {
    final hasTrades = summary.monthTrades > 0;
    final positive = summary.monthPnl >= 0;
    final losses = math.max(0, summary.monthTrades - summary.monthWins);
    final rate = (summary.monthWinRate / 100).clamp(0.0, 1.0).toDouble();

    return FlatCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'THIS MONTH',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Pill(text: '${summary.monthTrades} trades', tone: Tone.muted),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    hasTrades ? signedMoney(summary.monthPnl) : '—',
                    style: tabular.copyWith(
                      color: !hasTrades
                          ? AppColors.faint
                          : positive
                              ? AppColors.success
                              : AppColors.danger,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${summary.monthWins} W / $losses L',
                    style: tabular.copyWith(
                      color: AppColors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${summary.monthWinningDays} green days',
                    style: TextStyle(color: AppColors.faint, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Month win rate',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ),
              Text(
                percent(summary.monthWinRate),
                style: tabular.copyWith(
                  color: AppColors.text,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 5,
              backgroundColor: AppColors.surfaceAlt,
              valueColor: AlwaysStoppedAnimation<Color>(
                hasTrades && !positive ? AppColors.danger : AppColors.success,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

double _maxDrawdown(List<EquityPoint> points, double deposits) {
  var peak = deposits;
  var worst = 0.0;
  for (final point in points) {
    final balance = deposits + point.cumulative;
    if (balance > peak) peak = balance;
    if (peak > 0) {
      final drawdown = ((peak - balance) / peak) * 100;
      if (drawdown > worst) worst = drawdown;
    }
  }
  return worst;
}
