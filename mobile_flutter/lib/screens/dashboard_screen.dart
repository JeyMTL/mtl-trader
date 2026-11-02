import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/edge.dart';
import '../core/format.dart';
import '../l10n/gen/app_localizations.dart';
import '../models/models.dart';
import '../services/journal_api.dart';
import '../ui/a11y.dart';
import '../ui/brand.dart';
import '../ui/motion.dart';
import '../ui/prop_compliance.dart';
import '../ui/shimmer.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'subscription_screen.dart';

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
        toolbarHeight: 64,
        title: BrandMark(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SubscriptionScreen(api: widget.api),
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: AppLocalizations.of(context).refresh,
            icon: Icon(Icons.refresh, size: 20, color: AppColors.muted),
          ),
        ],
      ),
      body: FutureBuilder<DashboardData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const _DashboardSkeleton();
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
              api: widget.api,
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

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.api,
    required this.data,
    required this.onOpenEdge,
    required this.onEdit,
  });

  final JournalApi api;
  final DashboardData data;
  final VoidCallback onOpenEdge;
  final ValueChanged<String> onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
        Reveal(
          index: 0,
          child: _BalanceHero(data: data, summary: summary),
        ),
        const SizedBox(height: 10),
        PropComplianceCard(api: api),
        const SizedBox(height: 10),
        Reveal(
          index: 1,
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            // Taller cards as the system text size grows: two columns of
            // 11 px labels turn into four wrapped lines at 2x.
            childAspectRatio: 1.72 /
                MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0),
            children: [
              MetricCard(
                label: l10n.winRate,
                value: percent(summary.winRate),
                foot: l10n.winnersCount(summary.wins),
                icon: Icons.track_changes,
              ),
              MetricCard(
                label: l10n.profitFactor,
                value: summary.profitFactor > 0
                    ? summary.profitFactor.toStringAsFixed(2)
                    : '—',
                foot:
                    '${money(summary.grossProfit)} / ${money(summary.grossLoss)}',
                icon: Icons.balance,
              ),
              MetricCard(
                label: l10n.maxDrawdown,
                value: '${drawdown.toStringAsFixed(1)}%',
                foot: l10n.peakToTrough,
                tone: drawdown >= 10 ? Tone.negative : Tone.neutral,
                icon: Icons.trending_down,
              ),
              MetricCard(
                label: l10n.avgPerTrade,
                value:
                    summary.totalTrades > 0 ? money(summary.averageTrade) : '—',
                foot: l10n.expectancy,
                tone: summary.averageTrade >= 0 ? Tone.positive : Tone.negative,
                semanticValue: summary.totalTrades > 0
                    ? pnlLabel(context, summary.averageTrade)
                    : null,
                icon: Icons.functions,
              ),
            ],
          ),
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
                title: l10n.timeEdge,
                subtitle: l10n.timeEdgeSubtitle(
                  data.timeStats.timezone,
                  durationText(data.timeStats.medianMinutes),
                ),
                trailing: TextButton(
                  onPressed: onOpenEdge,
                  child: Text(l10n.report),
                ),
              ),
              const SizedBox(height: 4),
              if (!hasHours)
                EmptyState(
                  icon: Icons.schedule,
                  title: l10n.noTimedTradesTitle,
                  body: l10n.noTimedTradesBody,
                )
              else ...[
                _EdgeRow(
                  label: l10n.mostProfitableHour,
                  period: edge.bestHour,
                ),
                const ListDivider(),
                _EdgeRow(
                  label: l10n.mostLosses,
                  period: edge.worstHour,
                ),
                const ListDivider(),
                _EdgeRow(
                  label: l10n.bestSession,
                  period: edge.bestSession,
                ),
                const ListDivider(),
                _EdgeRow(
                  label: l10n.weakestSession,
                  period: edge.worstSession,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 84,
                  child: ChartSemantics(
                    label: l10n.a11yHourChart,
                    child: _HourChart(hours: hours),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.thinSampleNote,
                  style: TextStyle(
                    color: AppColors.faint,
                    fontSize: kMinLabelSize,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                child: SectionTitle(
                  title: l10n.journalSectionTitle,
                  subtitle: l10n.journalSectionSubtitle,
                ),
              ),
              if (data.journalFeed.isEmpty)
                EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: l10n.nothingJournaledTitle,
                  body: l10n.nothingJournaledBody,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                child: SectionTitle(title: l10n.recentFills),
              ),
              if (data.recentTrades.isEmpty)
                EmptyState(
                  icon: Icons.show_chart,
                  title: l10n.noFillsTitle,
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
                              PnlText(
                                value: trade.pnl,
                                style: tabular.copyWith(
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

/// The balance is the screen's hero: a counting number over a gradient equity
/// curve, with a soft gold bloom bleeding in from the corner.
class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.data, required this.summary});

  final DashboardData data;
  final TradeSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FlatCard(
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned(
            top: -54,
            right: -42,
            child: IgnorePointer(
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withAlpha(58),
                      AppColors.primary.withAlpha(0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.accountBalance.toUpperCase(),
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: kMinLabelSize,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    // Flexible, because a Pill is an intrinsic-width box:
                    // in a plain Row it gets unbounded width and cannot clip
                    // its own label.
                    Flexible(
                      child: Pill(
                        text: (summary.totalPnl >= 0
                                ? l10n.inProfit
                                : l10n.inDrawdown)
                            .toUpperCase(),
                        tone: summary.totalPnl >= 0
                            ? Tone.positive
                            : Tone.negative,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _CountUp(
                    value: data.balance,
                    style: tabular.copyWith(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.netSummary(
                    signedMoney(summary.totalPnl),
                    summary.totalTrades,
                    summary.wins,
                    summary.losses,
                  ),
                  style: TextStyle(color: AppColors.muted, fontSize: 11.5),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 116,
                  child: data.equity.isEmpty
                      ? Center(
                          child: Text(
                            l10n.importHistoryHint,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.faint,
                              fontSize: kMinLabelSize,
                            ),
                          ),
                        )
                      : ChartSemantics(
                          label: l10n.a11yEquityCurve(
                            signedMoney(data.equity.last.cumulative),
                          ),
                          child: _EquityChart(
                            points: data.equity,
                            deposits: data.deposits,
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                const ListDivider(),
                const SizedBox(height: 11),
                Row(
                  children: [
                    Expanded(
                      child: _MiniStat(
                        label: l10n.deposits,
                        value: money(data.deposits),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MiniStat(
                        label: l10n.bestTrade,
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
                        label: l10n.worstTrade,
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
        ],
      ),
    );
  }
}

/// Counts the balance up on first paint and fills it with a gold gradient.
class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, required this.style});

  final double value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.text, AppColors.primaryLight],
          ).createShader(rect),
          child: Text(
            money(animated),
            style: style.copyWith(color: Colors.white),
          ),
        );
      },
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 110),
      children: const [
        Shimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonCard(height: 292),
              SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: SkeletonCard(height: 82)),
                  SizedBox(width: 8),
                  Expanded(child: SkeletonCard(height: 82)),
                ],
              ),
              SizedBox(height: 10),
              SkeletonCard(height: 132),
              SizedBox(height: 10),
              SkeletonCard(height: 108),
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
                style: TextStyle(color: AppColors.faint, fontSize: 10.5),
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
                    style: TextStyle(color: AppColors.faint, fontSize: 10.5),
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
            barWidth: 2.2,
            dotData: FlDotData(show: false),
            shadow: Shadow(color: color.withAlpha(80), blurRadius: 12),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [color.withAlpha(64), color.withAlpha(0)],
              ),
            ),
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
                style: TextStyle(color: AppColors.faint, fontSize: 10.5),
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
  const _EdgeRow({required this.label, required this.period});

  final String label;

  /// Null when the period has too few trades to call.
  final EdgePeriod? period;

  @override
  Widget build(BuildContext context) {
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
                    fontSize: kMinLabelSize,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  period?.label ?? AppLocalizations.of(context).needsMoreTrades,
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
              if (period == null)
                Text(
                  '—',
                  style: tabular.copyWith(
                    color: AppColors.faint,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                // The sign, not just the colour, says which way this period
                // went: the "most losses" row can still be green on a lucky
                // day, and colour alone would mislead.
                PnlText(
                  value: period!.pnl,
                  style: tabular.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              Text(
                period == null
                    ? '—'
                    : AppLocalizations.of(
                        context,
                      ).periodStats(period!.trades, percent(period!.winRate)),
                style: TextStyle(
                  color: AppColors.faint,
                  fontSize: kMinLabelSize,
                ),
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
                PnlText(
                  value: entry.pnl,
                  style: tabular.copyWith(
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
                // A bare "3" next to an icon tells a screen reader nothing,
                // so each counter carries its own sentence.
                if (entry.imageCount > 0) ...[
                  CountBadge(
                    icon: Icons.image_outlined,
                    label: AppLocalizations.of(
                      context,
                    ).a11yScreenshots(entry.imageCount),
                    count: entry.imageCount,
                  ),
                  const SizedBox(width: 8),
                ],
                if (entry.audioCount > 0) ...[
                  CountBadge(
                    icon: Icons.mic_none,
                    label: AppLocalizations.of(
                      context,
                    ).a11yVoiceNotes(entry.audioCount),
                    count: entry.audioCount,
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
    final l10n = AppLocalizations.of(context);
    return FlatCard(
      borderColor: AppColors.primary.withAlpha(80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.startHere.toUpperCase(),
            style: TextStyle(
              color: AppColors.primary,
              fontSize: kMinLabelSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.startHeadline,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          _StartStep(number: '1', text: l10n.startStep1),
          _StartStep(number: '2', text: l10n.startStep2),
          _StartStep(number: '3', text: l10n.startStep3),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onOpenEdge,
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: Text(l10n.seeTimeReport),
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
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary.withAlpha(90)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              number,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: kMinLabelSize,
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
              AppLocalizations.of(context).couldNotLoadDesk,
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
            OutlinedButton(
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context).retry),
            ),
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
            fontSize: kMinLabelSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
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
    final l10n = AppLocalizations.of(context);
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
                  l10n.thisMonth.toUpperCase(),
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: kMinLabelSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Pill(
                text: l10n.monthTrades(summary.monthTrades),
                tone: Tone.muted,
              ),
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
                    l10n.greenDays(summary.monthWinningDays),
                    style: TextStyle(
                      color: AppColors.faint,
                      fontSize: kMinLabelSize,
                    ),
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
                  l10n.monthWinRate,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: kMinLabelSize,
                  ),
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
