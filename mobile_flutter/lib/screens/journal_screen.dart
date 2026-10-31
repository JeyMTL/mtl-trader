import 'dart:async';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../models/models.dart';
import '../services/journal_api.dart';
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
      builder: (context) => AlertDialog(
        title: const Text('Delete this trade?'),
        content: Text(
          '${trade.symbol} and its photos or voice notes will be removed. This cannot be undone.',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await widget.api.deleteTrade(trade.id);
      if (!mounted) return;
      setState(() => _deleting = false);
      await _load(reset: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Trade deleted.')));
      widget.onDataChanged?.call();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the trade: $error')),
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
      builder: (context) => AlertDialog(
        title: const Text('Clear the journal?'),
        content: Text(
          'Every trade, photo and voice note in this account is removed. This cannot be undone.',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Clear all',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
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
        SnackBar(content: Text('Could not clear the journal: $error')),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal'),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 20, color: AppColors.muted),
            color: AppColors.surfaceAlt,
            onSelected: (value) {
              if (value == 'clear') _clearJournal();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'clear',
                child: Text(
                  'Clear journal',
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
                            ? 'Loading…'
                            : '$_total trades · ${signedMoney(_totalPnl)}',
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
                    hintText: 'Search symbol, strategy or tag',
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
                    for (final option in const [
                      ('all', 'All'),
                      ('wins', 'Wins'),
                      ('losses', 'Losses'),
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
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load the journal',
            body: _error,
            action: OutlinedButton(
              onPressed: () => _load(reset: true),
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          EmptyState(
            icon: Icons.menu_book_outlined,
            title: 'No trades found',
            body:
                'Tap + to journal a fill, or import your MT5 history on the web desk.',
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
                  : const Text('Load more'),
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
                Text(
                  trade.symbol,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Pill(
                  text: trade.type,
                  tone: trade.type == 'BUY' ? Tone.positive : Tone.negative,
                ),
                const Spacer(),
                Text(
                  signedMoney(trade.pnl),
                  style: tabular.copyWith(
                    color:
                        trade.pnl >= 0 ? AppColors.success : AppColors.danger,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '${dayOf(trade.tradedAt)} · ${trade.entryPrice} → ${trade.exitPrice} · ${trade.lotSize} lots',
              style: TextStyle(color: AppColors.muted, fontSize: 10.5),
            ),
            if (trade.timeWindow != null) ...[
              const SizedBox(height: 2),
              Text(
                trade.timeWindow!,
                style: tabular.copyWith(color: AppColors.faint, fontSize: 10),
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
                        fontSize: 9.5,
                      ),
                    ),
                  for (final tag in trade.tags.take(3))
                    Text(
                      '#$tag',
                      style: TextStyle(
                        color: AppColors.faint,
                        fontSize: 9.5,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 5),
            Row(
              children: [
                if (trade.imageCount > 0) ...[
                  Icon(
                    Icons.image_outlined,
                    size: 11,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${trade.imageCount}',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 9.5,
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                if (trade.audioCount > 0) ...[
                  Icon(
                    Icons.mic_none,
                    size: 11,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${trade.audioCount}',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 9.5,
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
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
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
