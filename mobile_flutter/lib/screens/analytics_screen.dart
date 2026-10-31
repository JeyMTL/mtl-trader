import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/analytics.dart';
import '../core/format.dart';
import '../l10n/gen/app_localizations.dart';
import '../models/models.dart';
import '../services/journal_api.dart';
import '../ui/a11y.dart';
import '../ui/shimmer.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Web parity for the Analytics page: performance summary, monthly P&L,
/// the last 30 days, performance by symbol and by tag, and a link to the
/// hour/session edge report.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({
    super.key,
    required this.api,
    required this.onOpenEdge,
    required this.onOpenDay,
  });

  final JournalApi api;
  final VoidCallback onOpenEdge;
  final ValueChanged<DateTime> onOpenDay;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsData {
  const _AnalyticsData({
    required this.summary,
    required this.daily,
    required this.symbols,
    required this.tags,
  });

  final TradeSummary summary;
  final List<DailyPnlPoint> daily;
  final List<SymbolStat> symbols;
  final List<TagStat> tags;
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late Future<_AnalyticsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_AnalyticsData> _load() async {
    final today = DateTime.now();
    final from = today.subtract(const Duration(days: 210));
    final results = await Future.wait<dynamic>([
      widget.api.summary(),
      widget.api.dailyPnl(from, today),
      widget.api.symbolStats(limit: 10),
      widget.api.tagStats(limit: 12),
    ]);
    return _AnalyticsData(
      summary: results[0] as TradeSummary,
      daily: results[1] as List<DailyPnlPoint>,
      symbols: results[2] as List<SymbolStat>,
      tags: results[3] as List<TagStat>,
    );
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {
      // The FutureBuilder shows the error and the retry affordance.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AnalyticsData>(
      future: _future,
      builder: (context, snapshot) {
        final l10n = AppLocalizations.of(context);
        final data = snapshot.data;
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
                      l10n.navAnalytics,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _refresh,
                    tooltip: l10n.refresh,
                    icon: Icon(
                      Icons.refresh,
                      size: 18,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (snapshot.hasError)
                _ErrorCard(onRetry: _refresh)
              else if (data == null)
                const _AnalyticsSkeleton()
              else if (data.summary.totalTrades == 0)
                EmptyState(
                  title: l10n.analyticsEmptyTitle,
                  body: l10n.analyticsEmptyBody,
                  icon: Icons.insights_outlined,
                )
              else ...[
                _SummaryGrid(summary: data.summary),
                const SizedBox(height: 14),
                _MonthlySection(daily: data.daily),
                const SizedBox(height: 14),
                _RecentSection(daily: data.daily, onOpenDay: widget.onOpenDay),
                const SizedBox(height: 14),
                _SymbolSection(symbols: data.symbols),
                const SizedBox(height: 14),
                _TagSection(tags: data.tags),
                const SizedBox(height: 14),
                FlatCard(
                  onTap: widget.onOpenEdge,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.timeEdge,
                              style: TextStyle(
                                color: AppColors.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              l10n.timeEdgeDescription,
                              style: TextStyle(
                                color: AppColors.faint,
                                fontSize: kMinLabelSize,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.faint,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).analyticsErrorTitle,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context).analyticsErrorBody,
            style: TextStyle(color: AppColors.faint, fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(AppLocalizations.of(context).retry),
          ),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final TradeSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Taller cards at larger text sizes, so a two-column grid never clips its
    // labels when the system text size is turned up.
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final cards = [
      (
        l10n.summaryTrades,
        '${summary.totalTrades}',
        summary.monthTrades > 0
            ? l10n.summaryTradesFoot(summary.monthTrades)
            : null,
        Tone.neutral,
      ),
      (
        l10n.winRate,
        percent(summary.winRate),
        l10n.summaryWinLoss(summary.wins, summary.losses),
        Tone.neutral,
      ),
      (
        l10n.profitFactor,
        summary.grossLoss > 0 ? summary.profitFactor.toStringAsFixed(2) : '—',
        l10n.summaryGrossFoot(
          money(summary.grossProfit),
          money(summary.grossLoss),
        ),
        Tone.neutral,
      ),
      (
        l10n.summaryAverageTrade,
        signedMoney(summary.averageTrade),
        l10n.summaryNetFoot(signedMoney(summary.totalPnl)),
        summary.averageTrade >= 0 ? Tone.positive : Tone.negative,
      ),
      (
        l10n.bestTrade,
        signedMoney(summary.bestTrade),
        l10n.summaryBestTradeFoot(signedMoney(summary.worstTrade)),
        Tone.positive,
      ),
      (
        l10n.thisMonth,
        signedMoney(summary.monthPnl),
        l10n.summaryMonthFoot(summary.monthWinningDays),
        summary.monthPnl >= 0 ? Tone.positive : Tone.negative,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: l10n.performanceSummaryTitle,
          subtitle: l10n.performanceSummarySubtitle,
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.55 / scale,
          children: [
            for (final card in cards)
              MetricCard(
                label: card.$1,
                value: card.$2,
                foot: card.$3,
                tone: card.$4,
              ),
          ],
        ),
      ],
    );
  }
}

class _MonthlySection extends StatelessWidget {
  const _MonthlySection({required this.daily});

  final List<DailyPnlPoint> daily;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final months = monthTotals(daily, months: 6);
    final maxAbs = months.fold<double>(
      0,
      (max, month) => month.pnl.abs() > max ? month.pnl.abs() : max,
    );

    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: l10n.monthlyPnlTitle,
            subtitle: l10n.monthlyPnlSubtitle,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 128,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final month in months)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Six columns in a phone width: the value scales
                          // down rather than overflowing its bar.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              month.isEmpty
                                  ? '—'
                                  : compactMoney(month.pnl.abs()),
                              style: TextStyle(
                                color: month.isEmpty
                                    ? AppColors.faint
                                    : (month.pnl >= 0
                                        ? AppColors.success
                                        : AppColors.danger),
                                fontSize: kMinLabelSize,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              begin: 0,
                              end: maxAbs == 0
                                  ? 2
                                  : (month.pnl.abs() / maxAbs) * 78 + 2,
                            ),
                            duration: const Duration(milliseconds: 650),
                            curve: Curves.easeOutCubic,
                            builder: (context, height, _) => Container(
                              height: height,
                              decoration: BoxDecoration(
                                color: month.isEmpty
                                    ? AppColors.border
                                    : (month.pnl >= 0
                                        ? AppColors.success
                                        : AppColors.danger),
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(2),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              monthLabel(month.key),
                              style: TextStyle(
                                color: AppColors.faint,
                                fontSize: kMinLabelSize,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentSection extends StatelessWidget {
  const _RecentSection({required this.daily, required this.onOpenDay});

  final List<DailyPnlPoint> daily;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final days = recentDays(daily, days: 30);
    final best = bestDay(days);
    final worst = worstDay(days);

    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: l10n.pnlByDayTitle,
            subtitle: best == null
                ? l10n.pnlByDayRecent
                : l10n.pnlByDayBestWorst(
                    isoDayLabel(best.day),
                    signedMoney(best.pnl),
                    isoDayLabel(worst!.day),
                    signedMoney(worst.pnl),
                  ),
          ),
          const SizedBox(height: 12),
          ChartSemantics(
            label: l10n.a11yRunningCurve,
            child: _DailyCurve(days: days),
          ),
          const SizedBox(height: 12),
          _PnlHeatmap(days: days, onOpenDay: onOpenDay),
          const SizedBox(height: 9),
          // Wrapped, not a row: three legend entries plus the hint do not fit
          // one line in French at a 2x text scale.
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _LegendDot(
                  color: AppColors.danger.withAlpha(190),
                  label: l10n.legendLoss),
              _LegendDot(
                  color: AppColors.surfaceAlt, label: l10n.legendNoTrades),
              _LegendDot(
                  color: AppColors.success.withAlpha(190),
                  label: l10n.legendProfit),
              Text(
                l10n.tapADay,
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

/// Running P&L over the last 30 days, drawn as a filled curve so the shape of
/// the month is readable before the numbers are.
class _DailyCurve extends StatelessWidget {
  const _DailyCurve({required this.days});

  final List<DailyPnlPoint> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final spots = <FlSpot>[];
    var running = 0.0;
    for (var index = 0; index < days.length; index++) {
      running += days[index].pnl;
      spots.add(FlSpot(index.toDouble(), running));
    }
    var minY = spots.first.y;
    var maxY = spots.first.y;
    for (final spot in spots) {
      if (spot.y < minY) minY = spot.y;
      if (spot.y > maxY) maxY = spot.y;
    }
    final pad = (maxY - minY).abs() < 1 ? 1.0 : (maxY - minY) * 0.12;

    return SizedBox(
      height: 92,
      child: LineChart(
        LineChartData(
          minY: minY - pad,
          maxY: maxY + pad,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.22,
              barWidth: 2.2,
              color: AppColors.primary,
              dotData: const FlDotData(show: false),
              shadow: Shadow(
                color: AppColors.primary.withAlpha(70),
                blurRadius: 10,
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primary.withAlpha(56),
                    AppColors.primary.withAlpha(0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A calendar of the last 30 days: green for profit, red for loss, intensity
/// by size. Tapping a day with trades opens it in the calendar tab.
class _PnlHeatmap extends StatelessWidget {
  const _PnlHeatmap({required this.days, required this.onOpenDay});

  final List<DailyPnlPoint> days;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final maxAbs = days.fold<double>(
      0,
      (max, day) => day.pnl.abs() > max ? day.pnl.abs() : max,
    );
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      childAspectRatio: 1.45,
      children: [
        for (final day in days)
          // A colour-only cell is invisible to a screen reader and to anyone
          // who cannot separate the greens from the reds, so each day states
          // its own date and amount.
          Semantics(
            button: day.trades > 0,
            label: day.trades == 0
                ? l10n.a11yHeatmapEmpty(isoDayLabel(day.day))
                : l10n.a11yHeatmapDay(
                    isoDayLabel(day.day),
                    signedMoney(day.pnl),
                    day.trades,
                  ),
            excludeSemantics: true,
            child: Tooltip(
              message: day.trades == 0
                  ? l10n.a11yHeatmapEmpty(isoDayLabel(day.day))
                  : l10n.a11yHeatmapDay(
                      isoDayLabel(day.day),
                      signedMoney(day.pnl),
                      day.trades,
                    ),
              child: GestureDetector(
                onTap: day.trades == 0
                    ? null
                    : () {
                        final parsed = parseDay(day.day);
                        if (parsed != null) onOpenDay(parsed);
                      },
                child: Container(
                  decoration: BoxDecoration(
                    color: _heatColor(day, maxAbs),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: AppColors.border.withAlpha(90)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Color _heatColor(DailyPnlPoint day, double maxAbs) {
    if (day.trades == 0) return AppColors.surfaceAlt;
    if (maxAbs <= 0) return AppColors.surfaceAlt;
    final intensity = (day.pnl.abs() / maxAbs).clamp(0.0, 1.0);
    final base = day.pnl >= 0 ? AppColors.success : AppColors.danger;
    return base.withAlpha((34 + 150 * intensity).round());
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: AppColors.faint,
            fontSize: kMinLabelSize,
          ),
        ),
      ],
    );
  }
}

class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: Column(
        children: [
          SkeletonCard(height: 128),
          SizedBox(height: 10),
          SkeletonCard(height: 168),
          SizedBox(height: 10),
          SkeletonCard(height: 178),
          SizedBox(height: 10),
          SkeletonCard(height: 108),
        ],
      ),
    );
  }
}

class _SymbolSection extends StatelessWidget {
  const _SymbolSection({required this.symbols});

  final List<SymbolStat> symbols;

  @override
  Widget build(BuildContext context) {
    if (symbols.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return FlatCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: l10n.performanceBySymbol,
            subtitle: l10n.performanceBySymbolSubtitle,
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < symbols.length; index++) ...[
            if (index > 0) const ListDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 78,
                    child: Text(
                      symbols[index].symbol,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      l10n.symbolStats(
                        symbols[index].trades,
                        percent(symbols[index].winRate),
                      ),
                      style: TextStyle(
                        color: AppColors.faint,
                        fontSize: kMinLabelSize,
                      ),
                    ),
                  ),
                  PnlText(
                    value: symbols[index].pnl,
                    glyph: false,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TagSection extends StatelessWidget {
  const _TagSection({required this.tags});

  final List<TagStat> tags;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return FlatCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: l10n.performanceByTag,
            subtitle: l10n.performanceByTagSubtitle,
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < tags.length; index++) ...[
            if (index > 0) const ListDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tags[index].tag,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.tagStats(
                            tags[index].trades,
                            tags[index].wins,
                            tags[index].losses,
                            percent(tags[index].winRate),
                          ),
                          style: TextStyle(
                            color: AppColors.faint,
                            fontSize: kMinLabelSize,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PnlText(
                    value: tags[index].pnl,
                    glyph: false,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
