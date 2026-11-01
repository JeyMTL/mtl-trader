import 'dart:async';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../l10n/gen/app_localizations.dart';
import '../models/models.dart';
import '../services/journal_api.dart';
import '../ui/a11y.dart';
import '../ui/shimmer.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({
    super.key,
    required this.api,
    required this.onEdit,
    this.onDataChanged,
  });

  final JournalApi api;
  final ValueChanged<String> onEdit;

  /// Called after a delete so the desk and edge tabs do not keep stale data.
  final VoidCallback? onDataChanged;

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  static const int _pageSize = 25;

  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  List<TradeRow> _items = const [];
  int _total = 0;
  double _totalPnl = 0;
  int _offset = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _deleting = false;
  String _filter = 'all';
  String _session = 'all';
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    // The first paint already shows the loader; defer the setState inside
    // `_load` until after the frame is built.
    Future.microtask(() => _load(reset: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (mounted) _load(reset: true);
    });
    setState(() {});
  }

  Future<void> _load({bool reset = false}) async {
    if (_deleting) return;
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _offset = 0;
        _items = const [];
        _hasMore = false;
      }
    });

    try {
      final page = await widget.api.tradePage(
        limit: _pageSize,
        offset: _offset,
        search: _search.text,
        filter: _filter,
        session: _session == 'all' ? null : _session,
      );
      // A newer search/filter request has taken over; drop this response.
      if (!mounted || requestId != _requestId) return;
      final items = reset ? page.trades : [..._items, ...page.trades];
      setState(() {
        _items = items;
        _total = page.total;
        _totalPnl = page.totalPnl;
        _offset = items.length;
        _hasMore = items.length < page.total;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _refresh() => _load(reset: true);

  Future<void> _deleteTrade(TradeRow trade) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.deleteTradeTitle),
          content: Text(
            l10n.deleteTradeBody(trade.symbol),
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                l10n.deleteAction,
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await widget.api.deleteTrade(trade.id);
      if (!mounted) return;
      setState(() => _deleting = false);
      await _load(reset: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).deleteDone)),
      );
      widget.onDataChanged?.call();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).deleteFailed('$error')),
        ),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _clearJournal() async {
    final userId = widget.api.userId;
    if (userId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.clearJournalTitle),
          content: Text(
            l10n.clearJournalBody,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                l10n.clearAllAction,
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await widget.api.clearTrades(userId);
      if (!mounted) return;
      setState(() => _deleting = false);
      await _load(reset: true);
      if (!mounted) return;
      widget.onDataChanged?.call();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).clearFailed('$error')),
        ),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.journalTitle),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 20, color: AppColors.muted),
            color: AppColors.surfaceAlt,
            tooltip: l10n.journalClearMenu,
            onSelected: (value) {
              if (value == 'clear') _clearJournal();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'clear',
                child: Text(
                  l10n.journalClearMenu,
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _loading && _items.isEmpty
                            ? l10n.journalLoading
                            : l10n.journalCountSummary(
                                _total,
                                signedMoney(_totalPnl),
                              ),
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    if (_deleting)
                      const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 1.6),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: l10n.journalSearchHint,
                    prefixIcon: Icon(
                      Icons.search,
                      size: 18,
                      color: AppColors.faint,
                    ),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _search.clear();
                              _load(reset: true);
                              setState(() {});
                            },
                            icon: Icon(
                              Icons.close,
                              size: 16,
                              color: AppColors.faint,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final option in [
                      ('all', l10n.journalFilterAll),
                      ('wins', l10n.journalFilterWins),
                      ('losses', l10n.journalFilterLosses),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _FilterTab(
                          label: option.$2,
                          active: _filter == option.$1,
                          onTap: () {
                            setState(() => _filter = option.$1);
                            _load(reset: true);
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                // Sessions sit on their own wrapped row: six chips do not fit
                // across a phone, and a horizontally scrolling filter row hides
                // the option a trader is looking for.
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final option in [
                      ('all', l10n.journalSessionAll),
                      ('asian', l10n.journalSessionAsian),
                      ('london', l10n.journalSessionLondon),
                      ('newyork', l10n.journalSessionNewYork),
                      ('sydney', l10n.journalSessionSydney),
                    ])
                      _FilterTab(
                        label: option.$2,
                        active: _session == option.$1,
                        onTap: () {
                          setState(() => _session = option.$1);
                          _load(reset: true);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          const ListDivider(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: AppColors.primary,
              backgroundColor: AppColors.surface,
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) {
      return const _JournalSkeleton();
    }
    if (_error != null && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          EmptyState(
            icon: Icons.cloud_off_outlined,
            title: AppLocalizations.of(context).journalErrorTitle,
            body: _error,
            action: OutlinedButton(
              onPressed: () => _load(reset: true),
              child: Text(AppLocalizations.of(context).retry),
            ),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          EmptyState(
            icon: Icons.menu_book_outlined,
            title: AppLocalizations.of(context).journalEmptyTitle,
            body: AppLocalizations.of(context).journalEmptyBody,
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 110),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: OutlinedButton(
              onPressed: _loading ? null : () => _load(),
              child: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(AppLocalizations.of(context).journalLoadMore),
            ),
          );
        }
        final trade = _items[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _TradeCard(
            trade: trade,
            onEdit: () => widget.onEdit(trade.id),
            onDelete: _deleting ? null : () => _deleteTrade(trade),
          ),
        );
      },
    );
  }
}

class _TradeCard extends StatelessWidget {
  const _TradeCard({
    required this.trade,
    required this.onEdit,
    required this.onDelete,
  });

  final TradeRow trade;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return FlatCard(
      padding: EdgeInsets.zero,
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 11, 8, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Hero(
                    tag: 'trade-${trade.id}',
                    child: Material(
                      type: MaterialType.transparency,
                      child: Text(
                        trade.symbol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Pill(
                    text: trade.type,
                    tone: trade.type == 'BUY' ? Tone.positive : Tone.negative,
                  ),
                ),
                const SizedBox(width: 8),
                // Takes the remaining width and shrinks instead of pushing the
                // symbol off the card at a large text size.
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: PnlText(
                      value: trade.pnl,
                      style: tabular.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '${dayOf(trade.tradedAt)} · ${trade.entryPrice} → ${trade.exitPrice} · ${trade.lotSize} lots',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: kMinLabelSize,
              ),
            ),
            if (trade.timeWindow != null) ...[
              const SizedBox(height: 2),
              Text(
                trade.timeWindow!,
                style: tabular.copyWith(
                  color: AppColors.faint,
                  fontSize: kMinLabelSize,
                ),
              ),
            ],
            if (trade.strategy != null || trade.tags.isNotEmpty) ...[
              const SizedBox(height: 5),
              Wrap(
                spacing: 5,
                runSpacing: 4,
                children: [
                  if (trade.strategy != null)
                    Text(
                      trade.strategy!,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: kMinLabelSize,
                      ),
                    ),
                  for (final tag in trade.tags.take(3))
                    Text(
                      '#$tag',
                      style: TextStyle(
                        color: AppColors.faint,
                        fontSize: kMinLabelSize,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 5),
            Row(
              children: [
                if (trade.imageCount > 0) ...[
                  CountBadge(
                    icon: Icons.image_outlined,
                    label: AppLocalizations.of(
                      context,
                    ).a11yScreenshots(trade.imageCount),
                    count: trade.imageCount,
                  ),
                  const SizedBox(width: 7),
                ],
                if (trade.audioCount > 0) ...[
                  CountBadge(
                    icon: Icons.mic_none,
                    label: AppLocalizations.of(
                      context,
                    ).a11yVoiceNotes(trade.audioCount),
                    count: trade.audioCount,
                  ),
                  const SizedBox(width: 7),
                ],
                SizedBox(
                  width: 56,
                  height: 18,
                  child: CustomPaint(
                    painter: _TradeSparkPainter(
                      entry: trade.entryPrice,
                      exit: trade.exitPrice,
                      color:
                          trade.pnl >= 0 ? AppColors.success : AppColors.danger,
                    ),
                  ),
                ),
                const Spacer(),
                if (onDelete != null)
                  InkWell(
                    onTap: onDelete,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: AppColors.faint,
                      ),
                    ),
                  ),
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: AppColors.faint,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalSkeleton extends StatelessWidget {
  const _JournalSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 110),
      children: const [
        Shimmer(
          child: Column(
            children: [
              SkeletonCard(height: 102),
              SizedBox(height: 8),
              SkeletonCard(height: 102),
              SizedBox(height: 8),
              SkeletonCard(height: 102),
              SizedBox(height: 8),
              SkeletonCard(height: 102),
            ],
          ),
        ),
      ],
    );
  }
}

/// The entry-to-exit move, drawn at card scale. Gives a row a visual shape even
/// when the trade has no screenshot attached to the list query.
class _TradeSparkPainter extends CustomPainter {
  const _TradeSparkPainter({
    required this.entry,
    required this.exit,
    required this.color,
  });

  final double entry;
  final double exit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final high = entry > exit ? entry : exit;
    final low = entry > exit ? exit : entry;
    final range = (high - low).abs() < 1e-9 ? 1.0 : high - low;
    double y(double value) =>
        size.height - 2 - ((value - low) / range) * (size.height - 4);
    final start = Offset(0, y(entry));
    final end = Offset(size.width, y(exit));
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        size.width * 0.35,
        start.dy,
        size.width * 0.65,
        end.dy,
        end.dx,
        end.dy,
      );
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withAlpha(46), color.withAlpha(0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(end, 1.8, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TradeSparkPainter oldDelegate) =>
      oldDelegate.entry != entry ||
      oldDelegate.exit != exit ||
      oldDelegate.color != color;
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withAlpha(26) : Colors.transparent,
          border: Border.all(
            color: active ? AppColors.primary.withAlpha(90) : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.primaryLight : AppColors.muted,
            fontSize: kMinLabelSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
