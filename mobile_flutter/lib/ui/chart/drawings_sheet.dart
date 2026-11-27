import 'package:flutter/material.dart';

import '../../core/chart_magnet.dart';
import '../../core/chart_tools.dart';
import '../theme.dart';

/// One drawing tool as the sheet lists it. `id` is what the chart screen maps
/// back onto a creation method, so the sheet owns the labels and the screen owns
/// the geometry.
class _Tool {
  const _Tool(this.id, this.label, this.icon, this.category,
      {this.aliases = const []});

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
  _Tool('ellipse', 'Ellipse', Icons.circle_outlined, 'Shapes',
      aliases: ['circle']),
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

/// Category ids in the order the strip lists them, with the short label it
/// shows. A pill is a thumb target, not a sentence: "Fib" is read at a glance
/// where "Fibonacci" was being clipped by the screen edge.
const List<(String, String)> _categories = <(String, String)>[
  ('All', 'All'),
  ('Positions', 'Position'),
  ('Trend', 'Trend'),
  ('Shapes', 'Shapes'),
  ('Fibonacci', 'Fib'),
  ('Annotation', 'Notes'),
  ('Measure', 'Measure'),
];

_Tool? _toolById(String id) {
  for (final tool in _tools) {
    if (tool.id == id) return tool;
  }
  return null;
}

/// The tool sheet: pinned favourites, a search box, category pills and the
/// tools themselves, with the two drawing modes on a bar at the base.
///
/// Search runs across every category, because a trader who types "fib" should
/// not have to clear the filter they set two sessions ago. Picking a tool pops
/// the sheet with its id.
class DrawingsPanel extends StatefulWidget {
  const DrawingsPanel({
    super.key,
    required this.onPick,
    this.keepDrawing = false,
    this.onKeepDrawingChanged,
    this.magnet = MagnetMode.off,
    this.onMagnetChanged,
  });

  final void Function(String id) onPick;

  /// Whether the tool stays armed after it places an object.
  final bool keepDrawing;

  /// Null hides the Continuous toggle: a panel with nobody listening must not
  /// show a control that does nothing.
  final ValueChanged<bool>? onKeepDrawingChanged;

  final MagnetMode magnet;

  /// Null hides the Magnet toggle, for the same reason.
  final ValueChanged<MagnetMode>? onMagnetChanged;

  @override
  State<DrawingsPanel> createState() => _DrawingsPanelState();
}

class _DrawingsPanelState extends State<DrawingsPanel> {
  final TextEditingController _search = TextEditingController();
  String _category = 'All';
  late bool _keepDrawing = widget.keepDrawing;

  /// The pinned strip, in order. The defaults stand until the stored list
  /// arrives, so the sheet never opens with an empty row that fills in a frame
  /// later.
  List<String> _pinned = ToolFavourites.defaults;

  @override
  void initState() {
    super.initState();
    _loadPinned();
  }

  Future<void> _loadPinned() async {
    final pinned =
        await ToolFavourites.load(_tools.map((tool) => tool.id).toSet());
    if (!mounted) return;
    setState(() => _pinned = pinned);
  }

  @override
  void didUpdateWidget(covariant DrawingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keepDrawing != widget.keepDrawing) {
      _keepDrawing = widget.keepDrawing;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Pins or unpins a tool. Long-press is the only gesture that changes this:
  /// the strip is a quick-access row, and a tap on a chip has to place the tool
  /// it names.
  Future<void> _togglePin(String id) async {
    final wasPinned = _pinned.contains(id);
    final next = ToolFavourites.toggle(_pinned, id);
    setState(() => _pinned = next);
    await ToolFavourites.save(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1200),
        content: Text(
          wasPinned
              ? '${_toolById(id)?.label ?? 'Tool'} unpinned'
              : '${_toolById(id)?.label ?? 'Tool'} pinned to the top',
        ),
      ),
    );
  }

  void _setKeepDrawing(bool value) {
    setState(() => _keepDrawing = value);
    widget.onKeepDrawingChanged?.call(value);
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
        _favouritesStrip(),
        const SizedBox(height: 10),
        if (!searching) _categoryStrip(),
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
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.05,
            children: [
              for (final tool in visible)
                _ToolTile(
                  tool: tool,
                  pinned: _pinned.contains(tool.id),
                  onTap: () => widget.onPick(tool.id),
                  onLongPress: () => _togglePin(tool.id),
                ),
            ],
          ),
        const SizedBox(height: 12),
        _modeBar(),
      ],
    );
  }

  Widget _favouritesStrip() {
    final tools = [
      for (final id in _pinned) _toolById(id),
    ].whereType<_Tool>().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.push_pin, size: 11, color: AppColors.primary),
            const SizedBox(width: 5),
            Text(
              'PINNED',
              style: TextStyle(
                color: AppColors.primaryLight,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const Spacer(),
            Text(
              tools.isEmpty ? 'Long-press a tool to pin it' : 'Long-press to remove',
              style: TextStyle(color: AppColors.faint, fontSize: 9.5),
            ),
          ],
        ),
        if (tools.isNotEmpty) ...[
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final tool in tools) ...[
                  _FavouriteChip(
                    tool: tool,
                    onTap: () => widget.onPick(tool.id),
                    onLongPress: () => _togglePin(tool.id),
                  ),
                  if (tool != tools.last) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// The categories, with the right edge faded out so a clipped pill reads as
  /// "there is more to the right" rather than as a layout bug.
  Widget _categoryStrip() {
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0, 0.82, 1],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (id, label) in _categories) ...[
              _CategoryChip(
                label: label,
                selected: id == _category,
                onTap: () => setState(() => _category = id),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  /// Magnet and Continuous, fixed under the grid the way a desk puts its mode
  /// switches at the foot of the tool palette.
  Widget _modeBar() {
    final magnet = widget.magnet;
    final showContinuous = widget.onKeepDrawingChanged != null;
    final showMagnet = widget.onMagnetChanged != null;
    if (!showContinuous && !showMagnet) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          if (showMagnet)
            Expanded(
              child: _ModeToggle(
                icon: Icons.grid_on,
                label: 'Magnet',
                value: magnet.label,
                active: magnet != MagnetMode.off,
                onTap: () => widget.onMagnetChanged?.call(magnet.next),
              ),
            ),
          if (showMagnet && showContinuous) const SizedBox(width: 8),
          if (showContinuous)
            Expanded(
              child: _ModeToggle(
                icon: Icons.repeat,
                label: 'Continuous',
                value: _keepDrawing ? 'On' : 'Off',
                active: _keepDrawing,
                onTap: () => _setKeepDrawing(!_keepDrawing),
              ),
            ),
        ],
      ),
    );
  }
}

class _FavouriteChip extends StatelessWidget {
  const _FavouriteChip({
    required this.tool,
    required this.onTap,
    required this.onLongPress,
  });

  final _Tool tool;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${tool.label}, pinned',
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: AppColors.primary.withAlpha(120)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tool.icon, size: 15, color: AppColors.primaryLight),
              const SizedBox(width: 6),
              Text(
                tool.label,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
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
        height: 30,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color:
              selected ? AppColors.primary.withAlpha(28) : AppColors.surfaceAlt,
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

/// One tool in the grid. A pinned tool carries a gold border and a pin dot, so
/// the strip above and the grid agree about what is pinned.
class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.tool,
    required this.pinned,
    required this.onTap,
    required this.onLongPress,
  });

  final _Tool tool;
  final bool pinned;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: pinned ? '${tool.label}, pinned' : tool.label,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadius.field),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.field),
            border: Border.all(
              color: pinned ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(tool.icon, size: 24, color: AppColors.text),
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
              if (pinned)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(
                    Icons.push_pin,
                    size: 10,
                    color: AppColors.primaryLight,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A labelled mode switch, 44px tall so it meets the touch-target minimum
/// without looking like a settings row.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = active ? AppColors.primaryLight : AppColors.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withAlpha(22) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.field),
          border: Border.all(
            color: active ? AppColors.primary.withAlpha(150) : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: tone),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tone,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
