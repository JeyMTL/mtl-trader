import 'package:flutter/material.dart';

import '../core/analytics.dart';
import '../core/format.dart';
import '../models/models.dart';
import '../services/journal_api.dart';
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
                  const Expanded(
                    child: Text(
                      'Analytics',
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
                    tooltip: 'Refresh',
                    icon: const Icon(
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
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
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
                )
              else if (data.summary.totalTrades == 0)
                const EmptyState(
                  title: 'No trades to analyse yet',
                  body:
                      'Journal a few entries and the breakdowns fill in automatically.',
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
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Time edge',
                              style: TextStyle(
                                color: AppColors.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Best and worst entry hour, sessions and the 24-hour curve.',
                              style: TextStyle(
                                color: AppColors.faint,
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
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
          const Text(
            'Could not load analytics',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Check your connection and try again.',
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
            child: const Text('Retry'),
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
    final cards = [
      (
        'Trades',
        '${summary.totalTrades}',
        summary.monthTrades > 0 ? '${summary.monthTrades} this month' : null,
        Tone.neutral,
      ),
      (
        'Win rate',
        percent(summary.winRate),
        '${summary.wins}W · ${summary.losses}L',
        Tone.neutral,
      ),
      (
        'Profit factor',
        summary.grossLoss > 0 ? summary.profitFactor.toStringAsFixed(2) : '—',
        'Gross ${money(summary.grossProfit)} / ${money(summary.grossLoss)}',
        Tone.neutral,
      ),
      (
        'Average trade',
        signedMoney(summary.averageTrade),
        'Net ${signedMoney(summary.totalPnl)}',
        summary.averageTrade >= 0 ? Tone.positive : Tone.negative,
      ),
      (
        'Best trade',
        signedMoney(summary.bestTrade),
        'Worst ${signedMoney(summary.worstTrade)}',
        Tone.positive,
      ),
      (
        'This month',
        signedMoney(summary.monthPnl),
        '${summary.monthWinningDays} winning days',
        summary.monthPnl >= 0 ? Tone.positive : Tone.negative,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'Performance summary',
          subtitle: 'Every closed trade in your journal.',
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.55,
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
    final months = monthTotals(daily, months: 6);
    final maxAbs = months.fold<double>(
      0,
      (max, month) => month.pnl.abs() > max ? month.pnl.abs() : max,
    );

    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: 'Monthly P&L', subtitle: 'Last six months'),
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
                          Text(
                            month.isEmpty
                                ? '—'
                                : compactMoney(month.pnl.abs()),
                            style: TextStyle(
                              color: month.isEmpty
                                  ? AppColors.faint
                                  : (month.pnl >= 0
                                      ? AppColors.success
                                      : AppColors.danger),
                              fontSize: 9,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: maxAbs == 0
                                ? 2
                                : (month.pnl.abs() / maxAbs) * 78 + 2,
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
                          const SizedBox(height: 6),
                          Text(
                            monthLabel(month.key),
                            style: const TextStyle(
                              color: AppColors.faint,
                              fontSize: 9.5,
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
    final days = recentDays(daily, days: 30);
    final best = bestDay(days);
    final worst = worstDay(days);
    final maxAbs = days.fold<double>(
      0,
      (max, day) => day.pnl.abs() > max ? day.pnl.abs() : max,
    );

    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: 'P&L by day',
            subtitle: best == null
                ? 'Last 30 days'
                : 'Best ${isoDayLabel(best.day)} ${signedMoney(best.pnl)} · '
                    'Worst ${isoDayLabel(worst!.day)} ${signedMoney(worst.pnl)}',
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (final day in days)
                  Expanded(
                    child: GestureDetector(
                      onTap: day.trades == 0
                          ? null
                          : () => onOpenDay(parseDay(day.day) ?? DateTime.now()),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 0.8),
                        child: Align(
                          alignment: Alignment.center,
                          child: Container(
                            height: maxAbs == 0
                                ? 2
                                : (day.pnl.abs() / maxAbs) * 44 + 2,
                            decoration: BoxDecoration(
                              color: day.trades == 0
                                  ? AppColors.border
                                  : (day.pnl >= 0
                                      ? AppColors.success
                                      : AppColors.danger),
                              borderRadius: const BorderRadius.all(
                                Radius.circular(1.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '30 days ago',
                style: TextStyle(color: AppColors.faint, fontSize: 9.5),
              ),
              Text(
                'Today',
                style: TextStyle(color: AppColors.faint, fontSize: 9.5),
              ),
            ],
          ),
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
    return FlatCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            title: 'Performance by symbol',
            subtitle: 'Sorted by net P&L',
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
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${symbols[index].trades}T · '
                      '${percent(symbols[index].winRate)} win',
                      style: const TextStyle(
                        color: AppColors.faint,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Text(
                    signedMoney(symbols[index].pnl),
                    style: TextStyle(
                      color: symbols[index].pnl >= 0
                          ? AppColors.success
                          : AppColors.danger,
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
    return FlatCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            title: 'Performance by tag',
            subtitle: 'Tags you add to a trade, rolled up.',
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
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${tags[index].trades}T · '
                          '${tags[index].wins}W ${tags[index].losses}L · '
                          '${percent(tags[index].winRate)}',
                          style: const TextStyle(
                            color: AppColors.faint,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    signedMoney(tags[index].pnl),
                    style: TextStyle(
                      color: tags[index].pnl >= 0
                          ? AppColors.success
                          : AppColors.danger,
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
