import 'package:flutter/material.dart';

import '../theme.dart';

/// One drawing tool as the sheet lists it. `id` is what the chart screen maps
/// back onto a creation method, so the sheet owns the labels and the screen owns
/// the geometry.
class _Tool {
  const _Tool(this.id, this.label, this.icon, this.category, {this.aliases = const []});

  final String id;
  final String label;
  final IconData icon;
  final String category;

  /// Extra words the search should match, so "box" finds the rectangle and
  /// "trend" finds both lines without the label having to contain them.
  final List<String> aliases;

  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    if (label.toLowerCase().contains(needle)) return true;
    for (final alias in aliases) {
      if (alias.contains(needle)) return true;
    }
    return false;
  }
}

const List<_Tool> _tools = <_Tool>[
  _Tool('long', 'Long position', Icons.trending_up, 'Positions',
      aliases: ['buy', 'risk', 'reward', 'target']),
  _Tool('short', 'Short position', Icons.trending_down, 'Positions',
      aliases: ['sell', 'risk', 'reward', 'target']),
  _Tool('trend', 'Trend line', Icons.show_chart, 'Trend',
      aliases: ['line', 'diagonal']),
  _Tool('ray', 'Horizontal ray', Icons.horizontal_rule, 'Trend',
      aliases: ['line', 'support', 'resistance', 'level']),
  _Tool('vline', 'Vertical line', Icons.more_vert, 'Trend',
      aliases: ['time', 'session', 'event']),
  _Tool('rectangle', 'Rectangle', Icons.crop_square, 'Shapes',
      aliases: ['box', 'zone', 'supply', 'demand']),
  _Tool('ellipse', 'Ellipse', Icons.circle_outlined, 'Shapes', aliases: ['circle']),
  _Tool('fib', 'Fib retracement', Icons.format_line_spacing, 'Fibonacci',
      aliases: ['fibonacci', 'golden', 'levels', 'retrace']),
  _Tool('fibExtension', 'Fib extension', Icons.stacked_line_chart, 'Fibonacci',
      aliases: ['fibonacci', 'target', 'extension']),
  _Tool('measure', 'Measure', Icons.straighten, 'Measure',
      aliases: ['distance', 'risk', 'bars', 'move']),
  _Tool('text', 'Text', Icons.title, 'Annotation', aliases: ['note', 'label']),
  _Tool('arrowUp', 'Arrow up', Icons.north_east, 'Annotation',
      aliases: ['mark', 'point', 'up']),
  _Tool('arrowDown', 'Arrow down', Icons.south_east, 'Annotation',
      aliases: ['mark', 'point', 'down']),
  _Tool('brush', 'Brush', Icons.gesture, 'Annotation',
      aliases: ['draw', 'freehand', 'pen', 'scribble']),
];

const List<String> _categories = <String>[
  'All',
  'Positions',
  'Trend',
  'Shapes',
  'Fibonacci',
  'Annotation',
  'Measure',
];

/// The tool picker: a search box, a row of categories and the tools themselves.
///
/// Search runs across every category, because a trader who types "fib" should
/// not have to clear the filter they set two sessions ago. Picking one pops the
/// sheet with the tool id.
class DrawingsPanel extends StatefulWidget {
  const DrawingsPanel({super.key, required this.onPick});

  final void Function(String id) onPick;

  @override
  State<DrawingsPanel> createState() => _DrawingsPanelState();
}

class _DrawingsPanelState extends State<DrawingsPanel> {
  final TextEditingController _search = TextEditingController();
  String _category = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text;
    final searching = query.trim().isNotEmpty;
    final visible = [
      for (final tool in _tools)
        if ((searching || _category == 'All' || tool.category == _category) &&
            tool.matches(query))
          tool,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: AppColors.text, fontSize: 12.5),
          decoration: InputDecoration(
            hintText: 'Search tools',
            prefixIcon: Icon(Icons.search, size: 17, color: AppColors.faint),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        if (!searching)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final category in _categories) ...[
                  _CategoryChip(
                    label: category,
                    selected: category == _category,
                    onTap: () => setState(() => _category = category),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text(
                'No tool matches “${query.trim()}”.',
                style: TextStyle(color: AppColors.faint, fontSize: 11.5),
              ),
            ),
          )
        else
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1.15,
            children: [
              for (final tool in visible)
                _ToolTile(tool: tool, onTap: () => widget.onPick(tool.id)),
            ],
          ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withAlpha(28) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primaryLight : AppColors.muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool, required this.onTap});

  final _Tool tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.field),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(tool.icon, size: 19, color: AppColors.text),
            const SizedBox(height: 6),
            Text(
              tool.label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 9.5,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
