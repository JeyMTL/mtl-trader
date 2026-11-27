import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/instruments.dart';
import '../core/symbol_favorites.dart';
import '../l10n/gen/app_localizations.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Searchable list of every instrument the app ships with, split into the asset
/// classes a trader actually shops by.
Future<String?> showSymbolPicker(BuildContext context, {String? selected}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SymbolSheet(selected: selected),
  );
}

class _SymbolSheet extends StatefulWidget {
  const _SymbolSheet({this.selected});

  final String? selected;

  @override
  State<_SymbolSheet> createState() => _SymbolSheetState();
}

class _SymbolSheetState extends State<_SymbolSheet> {
  final _search = TextEditingController();
  String _query = '';

  /// `null` is Favorites, otherwise the asset class. The picker opens on
  /// favorites when there are any and on Forex when there are not, so the first
  /// screen is always the shortlist rather than sixty crosses.
  String? _category;
  bool _categoryResolved = false;
  Set<String> _favorites = {};

  static const String _favoritesKey = 'favorites';

  String get _activeCategory => _category ?? _favoritesKey;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final saved = await SymbolFavorites.load();
    if (!mounted) return;
    setState(() {
      _favorites = saved.toSet();
      if (!_categoryResolved) {
        _categoryResolved = true;
        _category = _favorites.isEmpty ? InstrumentKind.forex.label : null;
      }
    });
  }

  Future<void> _toggleFavorite(String symbol) async {
    HapticFeedback.selectionClick();
    final next = await SymbolFavorites.toggle(symbol);
    if (!mounted) return;
    setState(() => _favorites = next.toSet());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Instrument> _matching(String term) {
    if (term.isEmpty) return instrumentCatalog;
    return instrumentCatalog
        .where(
          (item) =>
              item.symbol.contains(term) ||
              item.name.toUpperCase().contains(term),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final term = _query.trim().toUpperCase();
    final matches = _matching(term);
    final favorites = [
      for (final item in matches)
        if (_favorites.contains(item.symbol)) item,
    ];

    // Search outranks the tab: typing EUR should not be silently filtered down
    // to whichever asset class happened to be selected.
    final onFavorites = _activeCategory == _favoritesKey;
    final items = term.isNotEmpty
        ? matches
        : onFavorites
            ? favorites
            : matches
                .where((item) => item.kind.label == _activeCategory)
                .toList();

    final children = <Widget>[];
    if (items.isNotEmpty) {
      children.add(
        _GroupHeader(
          label: term.isNotEmpty
              ? l10n.allAssets
              : onFavorites
                  ? l10n.symbolFavorites
                  : _activeCategory,
        ),
      );
      children.addAll(items.map(_tile));
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.86,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.symbolPickerTitle,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: l10n.cancel,
                    icon: Icon(Icons.close, size: 18, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: TextField(
                controller: _search,
                autofocus: false,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: l10n.symbolSearchHint,
                  prefixIcon: Icon(
                    Icons.search,
                    size: 18,
                    color: AppColors.faint,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(
                            Icons.close,
                            size: 16,
                            color: AppColors.faint,
                          ),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            _CategoryStrip(
              active: term.isEmpty ? _activeCategory : null,
              favoritesCount: favorites.length,
              onSelected: (key) {
                HapticFeedback.selectionClick();
                setState(() => _category = key);
              },
            ),
            Expanded(
              child: !_categoryResolved
                  ? Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : items.isEmpty
                      ? EmptyState(
                          title: onFavorites && term.isEmpty
                              ? l10n.symbolNoFavoritesTitle
                              : l10n.symbolNoMatchTitle,
                          body: onFavorites && term.isEmpty
                              ? l10n.symbolNoFavoritesBody
                              : l10n.symbolNoMatchBody,
                          icon: onFavorites && term.isEmpty
                              ? Icons.star_border
                              : Icons.search_off,
                        )
                      : ListView(children: children),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
              child: Text(
                l10n.symbolFooter(instrumentCatalog.length),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.faint, fontSize: 9.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Instrument item) {
    return _InstrumentTile(
      instrument: item,
      selected: item.symbol == widget.selected,
      favorite: _favorites.contains(item.symbol),
      onFavorite: () => _toggleFavorite(item.symbol),
      onTap: () => Navigator.pop(context, item.symbol),
    );
  }
}

/// The asset classes, as pills under the search field.
class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.active,
    required this.favoritesCount,
    required this.onSelected,
  });

  final String? active;
  final int favoritesCount;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = <(String, String, IconData)>[
      ('favorites', l10n.symbolFavorites, Icons.star_border),
      for (final kind in InstrumentKind.values)
        (kind.label, kind.label, _iconFor(kind)),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final entry = entries[index];
          final selected = entry.$1 == active;
          final isFavorites = entry.$1 == 'favorites';
          return GestureDetector(
            onTap: () => onSelected(entry.$1),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withAlpha(26)
                    : AppColors.background,
                borderRadius: const BorderRadius.all(Radius.circular(9)),
                border: Border.all(
                  color: selected
                      ? AppColors.primary.withAlpha(140)
                      : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    entry.$3,
                    size: 13,
                    color: selected ? AppColors.primary : AppColors.muted,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isFavorites && favoritesCount > 0
                        ? '${entry.$2} $favoritesCount'
                        : entry.$2,
                    style: TextStyle(
                      color: selected ? AppColors.primary : AppColors.muted,
                      fontSize: 11.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static IconData _iconFor(InstrumentKind kind) {
    switch (kind) {
      case InstrumentKind.forex:
        return Icons.currency_exchange;
      case InstrumentKind.metal:
        return Icons.workspace_premium_outlined;
      case InstrumentKind.indices:
        return Icons.show_chart;
      case InstrumentKind.crypto:
        return Icons.currency_bitcoin;
      case InstrumentKind.energy:
        return Icons.local_gas_station_outlined;
    }
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: AppColors.primary,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _InstrumentTile extends StatelessWidget {
  const _InstrumentTile({
    required this.instrument,
    required this.selected,
    required this.favorite,
    required this.onFavorite,
    required this.onTap,
  });

  final Instrument instrument;
  final bool selected;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(left: 14, right: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    SizedBox(
                      width: 74,
                      child: Text(
                        instrument.symbol,
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        instrument.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    if (selected)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.check,
                          size: 15,
                          color: AppColors.primary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Pinning is the one thing a trader does here besides picking, so
            // it gets its own target instead of hiding in a long press.
            IconButton(
              onPressed: onFavorite,
              tooltip: favorite
                  ? AppLocalizations.of(context).unpin
                  : AppLocalizations.of(context).pin,
              icon: Icon(
                favorite ? Icons.star : Icons.star_border,
                size: 17,
                color: favorite ? AppColors.primary : AppColors.faint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
