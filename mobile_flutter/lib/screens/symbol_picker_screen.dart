import 'package:flutter/material.dart';

import '../core/instruments.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Searchable list of every instrument the app ships with.
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final term = _query.trim().toUpperCase();
    final items = term.isEmpty
        ? instrumentCatalog
        : instrumentCatalog
            .where(
              (item) =>
                  item.symbol.contains(term) ||
                  item.name.toUpperCase().contains(term),
            )
            .toList();

    final children = <Widget>[];
    for (final kind in InstrumentKind.values) {
      final group = items.where((item) => item.kind == kind).toList();
      if (group.isEmpty) continue;
      children.add(_GroupHeader(label: kind.label));
      children.addAll(
        group.map(
          (item) => _InstrumentTile(
            instrument: item,
            selected: item.symbol == widget.selected,
            onTap: () => Navigator.pop(context, item.symbol),
          ),
        ),
      );
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: TextField(
                controller: _search,
                autofocus: false,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'Search pairs, metals, indices, crypto',
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
            Expanded(
              child: items.isEmpty
                  ? const EmptyState(
                      title: 'No instrument matches',
                      body:
                          'Try a shorter search, or type the symbol directly.',
                      icon: Icons.search_off,
                    )
                  : ListView(children: children),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
              child: Text(
                '${instrumentCatalog.length} instruments · every chart is a live OANDA CFD quote',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.faint, fontSize: 9.5),
              ),
            ),
          ],
        ),
      ),
    );
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
    required this.onTap,
  });

  final Instrument instrument;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
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
                style: TextStyle(color: AppColors.muted, fontSize: 11.5),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Pill(
                text: 'LIVE',
                tone: Tone.positive,
              ),
            ),
            if (selected) Icon(Icons.check, size: 15, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
