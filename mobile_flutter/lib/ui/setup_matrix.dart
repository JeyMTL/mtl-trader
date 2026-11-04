import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/strategy_colors.dart';
import '../models/models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Tags and strategy labels side by side.
///
/// They answer the same question — "how does this model perform?" — so they are
/// one comparison rather than two lists the trader has to hold in their head.
/// The two kinds stay separate rows because they are different fields on the
/// journal form, and a tag can legitimately share a name with a strategy.
class SetupMatrix extends StatefulWidget {
  const SetupMatrix({
    super.key,
    required this.tags,
    required this.strategies,
  });

  final List<TagStat> tags;
  final List<StrategyStat> strategies;

  @override
  State<SetupMatrix> createState() => _SetupMatrixState();
}

class _SetupRow {
  const _SetupRow({
    required this.label,
    required this.kind,
    required this.trades,
    required this.pnl,
    required this.winRate,
    required this.expectancy,
  });

  final String label;

  /// `tag` or `strategy`.
  final String kind;

  final int trades;
  final double pnl;
  final double winRate;
  final double expectancy;

  String get key => '$kind:$label';
}

class _SetupMatrixState extends State<SetupMatrix> {
  /// Store what is switched off, not what is on, so a setup that appears after
  /// the next refresh is visible by default instead of silently filtered.
  final Set<String> _hidden = <String>{};

  /// Multi-select: the point of colour filtering is comparing models that share
  /// a hue, so a single selection would hide half of the comparison.
  final Set<Color> _colorFilter = <Color>{};

  List<_SetupRow> get _rows {
    final rows = <_SetupRow>[
      for (final tag in widget.tags)
        _SetupRow(
          label: tag.tag,
          kind: 'tag',
          trades: tag.trades,
          pnl: tag.pnl,
          winRate: tag.winRate,
          expectancy: tag.trades > 0 ? tag.pnl / tag.trades : 0,
        ),
      for (final strategy in widget.strategies)
        _SetupRow(
          label: strategy.strategy,
          kind: 'strategy',
          trades: strategy.trades,
          pnl: strategy.pnl,
          winRate: strategy.winRate,
          expectancy: strategy.expectancy,
        ),
    ];
    rows.sort((a, b) {
      final byPnl = b.pnl.compareTo(a.pnl);
      return byPnl != 0 ? byPnl : b.trades.compareTo(a.trades);
    });
    return rows;
  }

  /// Distinct colours in use, most-used first, with how many setups each covers.
  List<MapEntry<Color, int>> get _colorGroups {
    final counts = <Color, int>{};
    for (final row in _rows) {
      final color = strategyColor(row.key);
      counts.update(color, (value) => value + 1, ifAbsent: () => 1);
    }
    final groups = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows.isEmpty) return const SizedBox.shrink();
    final groups = _colorGroups;
    final visible = rows
        .where(
          (row) =>
              !_hidden.contains(row.key) &&
              (_colorFilter.isEmpty ||
                  _colorFilter.contains(strategyColor(row.key))),
        )
        .toList();

    return FlatCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.grid_view_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Setup matrix',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Compare your trading models directly. Tap a setup to include or remove it.',
            style:
                TextStyle(color: AppColors.faint, fontSize: 11.5, height: 1.45),
          ),
          if (groups.length > 1) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'COLOUR',
                  style: TextStyle(
                    color: AppColors.faint,
                    fontSize: kMinLabelSize,
                    letterSpacing: 0.6,
                  ),
                ),
                for (final group in groups)
                  Semantics(
                    button: true,
                    selected: _colorFilter.contains(group.key),
                    label: 'Filter by colour: ${group.value} setups',
                    child: InkWell(
                      onTap: () => setState(() {
                        if (!_colorFilter.remove(group.key)) {
                          _colorFilter.add(group.key);
                        }
                      }),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _colorFilter.contains(group.key)
                              ? AppColors.primary.withAlpha(30)
                              : AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _colorFilter.contains(group.key)
                                ? AppColors.primary.withAlpha(120)
                                : AppColors.border,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: group.key,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${group.value}',
                              style: TextStyle(
                                color: _colorFilter.contains(group.key)
                                    ? AppColors.text
                                    : AppColors.muted,
                                fontSize: kMinLabelSize,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_colorFilter.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_colorFilter.clear),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Clear',
                      style: TextStyle(fontSize: kMinLabelSize),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final row in rows)
                _Chip(
                  label: row.label,
                  kind: row.kind,
                  active: !_hidden.contains(row.key),
                  onTap: () => setState(() {
                    if (!_hidden.remove(row.key)) _hidden.add(row.key);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (visible.isEmpty)
            Text(
              _colorFilter.isNotEmpty &&
                      rows.any((row) => !_hidden.contains(row.key))
                  ? 'No setup on this list matches the colour filter.'
                  : 'Every setup is hidden — tap one above to bring it back.',
              style: TextStyle(color: AppColors.faint, fontSize: 11.5),
            )
          else
            for (var index = 0; index < visible.length; index++) ...[
              if (index > 0) const ListDivider(),
              _MatrixRow(row: visible[index]),
            ],
          const SizedBox(height: 6),
          Text(
            'Sorted by net P&L. Labels match exactly after trimming, so two spellings of one model '
            'appear as two rows; rename them on the journal form to combine them.',
            style: TextStyle(
                color: AppColors.faint, fontSize: kMinLabelSize, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.kind,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String kind;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: '$label, $kind',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color:
                active ? AppColors.primary.withAlpha(30) : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color:
                  active ? AppColors.primary.withAlpha(110) : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: strategyColor('$kind:$label'),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '$label · $kind',
                style: TextStyle(
                  color: active ? AppColors.primary : AppColors.faint,
                  fontSize: kMinLabelSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatrixRow extends StatelessWidget {
  const _MatrixRow({required this.row});

  final _SetupRow row;

  @override
  Widget build(BuildContext context) {
    final tone = row.pnl >= 0 ? AppColors.success : AppColors.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 8, top: 2),
            decoration: BoxDecoration(
              color: strategyColor(row.key),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${row.trades}T · ${percent(row.winRate)} win · ${money(row.expectancy)}/trade',
                  style: TextStyle(
                      color: AppColors.faint, fontSize: kMinLabelSize),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            money(row.pnl),
            style: TextStyle(
              color: tone,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
