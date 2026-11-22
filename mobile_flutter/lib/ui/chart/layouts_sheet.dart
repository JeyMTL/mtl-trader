import 'package:flutter/material.dart';

import '../../core/chart_layouts.dart';
import '../theme.dart';

/// What the layouts manager answered.
@immutable
class LayoutsResult {
  const LayoutsResult.open(this.layout) : delete = null, saveCurrent = false;

  const LayoutsResult.remove(this.delete)
      : layout = null,
        saveCurrent = false;

  const LayoutsResult.saveCurrent()
      : layout = null,
        delete = null,
        saveCurrent = true;

  final ChartLayout? layout;
  final ChartLayout? delete;

  /// The trader asked to save the chart they are on as a new layout; the sheet
  /// does not know the current palette or interval, so the screen does the work.
  final bool saveCurrent;
}

/// The saved-layout library, opened from the analysis hub.
///
/// The spec's shape: a titled full-height sheet with a search box, a list whose
/// active row is filled rather than outlined, a star on every row and a bin on
/// the right. The star and the bin are one tap because that is how often a
/// trader changes their mind about which layout is theirs.
Future<LayoutsResult?> showLayoutsManager(
  BuildContext context, {
  required List<ChartLayout> layouts,
  required String? activeId,
  required String currentSymbol,
  required String currentIntervalKey,
}) {
  return showModalBottomSheet<LayoutsResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _LayoutsSheet(
      layouts: layouts,
      activeId: activeId,
      currentSymbol: currentSymbol,
      currentIntervalKey: currentIntervalKey,
    ),
  );
}

class _LayoutsSheet extends StatefulWidget {
  const _LayoutsSheet({
    required this.layouts,
    required this.activeId,
    required this.currentSymbol,
    required this.currentIntervalKey,
  });

  final List<ChartLayout> layouts;
  final String? activeId;
  final String currentSymbol;
  final String currentIntervalKey;

  @override
  State<_LayoutsSheet> createState() => _LayoutsSheetState();
}

class _LayoutsSheetState extends State<_LayoutsSheet> {
  late List<ChartLayout> _layouts;
  late String? _activeId;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _layouts = [...widget.layouts];
    _activeId = widget.activeId;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ChartLayout> get _visible {
    final needle = _search.text.trim().toLowerCase();
    if (needle.isEmpty) return _layouts;
    return _layouts
        .where(
          (layout) =>
              layout.name.toLowerCase().contains(needle) ||
              layout.symbol.toLowerCase().contains(needle),
        )
        .toList();
  }

  Future<void> _toggleStar(ChartLayout layout) async {
    final next = [
      for (final item in _layouts)
        item.id == layout.id ? item.copyWith(starred: !item.starred) : item,
    ];
    next.sort((a, b) {
      if (a.starred != b.starred) return a.starred ? -1 : 1;
      return b.savedAt.compareTo(a.savedAt);
    });
    setState(() => _layouts = next);
    await ChartLayoutStore.save(_layouts);
  }

  Future<void> _delete(ChartLayout layout) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this layout?'),
        content: Text(
          '“${layout.name}” is removed from the library. Drawings on '
          '${layout.symbol} are not touched — they live with the chart.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _layouts = _layouts.where((item) => item.id != layout.id).toList();
      if (_activeId == layout.id) _activeId = null;
    });
    await ChartLayoutStore.save(_layouts);
    if (_activeId == null) await ChartLayoutStore.setActive(null);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.9,
      child: Column(
        children: [
          _header(),
          _searchField(),
          const Divider(height: 1),
          Expanded(
            child: visible.isEmpty
                ? _empty()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                        child: Text(
                          'LAYOUT NAME',
                          style: TextStyle(
                            color: AppColors.faint,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      for (final layout in visible)
                        _row(layout, active: layout.id == _activeId),
                    ],
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(
                  const LayoutsResult.saveCurrent(),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Save this chart as a layout'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  foregroundColor: AppColors.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Layouts',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, size: 20, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        style: TextStyle(color: AppColors.text, fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search layouts',
          hintStyle: TextStyle(color: AppColors.faint, fontSize: 13),
          prefixIcon: Icon(Icons.search, size: 18, color: AppColors.faint),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () => setState(_search.clear),
                  icon: Icon(Icons.close, size: 16, color: AppColors.faint),
                ),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _empty() {
    final searching = _search.text.trim().isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off : Icons.dashboard_customize_outlined,
              size: 26,
              color: AppColors.faint,
            ),
            const SizedBox(height: 10),
            Text(
              searching
                  ? 'No layout matches “${_search.text.trim()}”.'
                  : 'No saved layouts yet. Save the chart you are looking at '
                      'and it comes back exactly like this.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(ChartLayout layout, {required bool active}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: active ? AppColors.text : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () =>
              Navigator.of(context).pop(LayoutsResult.open(layout)),
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: active ? AppColors.text : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: layout.starred ? 'Unstar' : 'Star',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _toggleStar(layout),
                  icon: Icon(
                    layout.starred ? Icons.star : Icons.star_border,
                    size: 18,
                    color: layout.starred
                        ? AppColors.primaryLight
                        : (active ? AppColors.background : AppColors.faint),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        layout.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active ? AppColors.background : AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        layout.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active
                              ? AppColors.background.withAlpha(170)
                              : AppColors.faint,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete ${layout.name}',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _delete(layout),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: active ? AppColors.background : AppColors.danger,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
