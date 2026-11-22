
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/chart_drawings.dart';
import '../../core/chart_theme.dart';
import '../color_wheel.dart';
import '../theme.dart';

/// What the object sheet answered.
///
/// A settings sheet is not only an edit: the same panel is where TradingView
/// lets you clone and remove the very object you are looking at, and making the
/// trader close it first to do either is pure friction. So the answer carries
/// the object *and* the action, rather than overloading null.
@immutable
class ObjectSettingsResult {
  const ObjectSettingsResult.change(this.drawing, {this.order})
      : clone = false,
        remove = false;

  const ObjectSettingsResult.clone(this.drawing)
      : clone = true,
        remove = false,
        order = null;

  const ObjectSettingsResult.remove()
      : drawing = null,
        clone = false,
        remove = true,
        order = null;

  final ChartDrawing? drawing;
  final bool clone;
  final bool remove;

  /// Where the object lands in the drawing order, when the trader asked for it.
  /// Last drawn is painted last, so "front" means the end of the list.
  final ObjectOrder? order;
}

/// Bring to front or send to back.
enum ObjectOrder { front, back }

/// The object's settings, the way a charting app is expected to offer them.
///
/// Style, coordinates and text live behind tabs instead of being one long form,
/// because they answer different questions: what the object looks like, exactly
/// where it sits, and what it says. Everything is a draft until Ok — a trader
/// widening a box and changing their mind must get the old box back, not a
/// half-restyled one.
Future<ObjectSettingsResult?> showObjectSettings(
  BuildContext context, {
  required ChartDrawing drawing,
  required String title,
  required int decimals,
}) {
  return showModalBottomSheet<ObjectSettingsResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) => _ObjectSettings(
      drawing: drawing,
      title: title,
      decimals: decimals,
    ),
  );
}

class _ObjectSettings extends StatefulWidget {
  const _ObjectSettings({
    required this.drawing,
    required this.title,
    required this.decimals,
  });

  final ChartDrawing drawing;
  final String title;
  final int decimals;

  @override
  State<_ObjectSettings> createState() => _ObjectSettingsState();
}

class _ObjectSettingsState extends State<_ObjectSettings> {
  late DrawingLook _look;
  late PositionSide _side;
  late double _entry;
  late double _stop;
  late double _target;
  late int _startMs;
  late int _endMs;
  late double _rayPrice;
  late List<ChartPoint> _points;
  late final List<TextEditingController> _priceFields;
  late final TextEditingController _textField;

  /// 0 = Style, 1 = Coordinates, 2 = Text (only for objects that carry words).
  int _tab = 0;

  ChartDrawing get _drawing => widget.drawing;

  @override
  void initState() {
    super.initState();
    final drawing = widget.drawing;
    _look = drawing.look;
    _side = drawing.side ?? PositionSide.long;
    _entry = drawing.entry ?? 0;
    _stop = drawing.stop ?? 0;
    _target = drawing.target ?? 0;
    _startMs = drawing.startMs;
    _endMs = drawing.endMs;
    _rayPrice = drawing.price ?? 0;

    // Trend lines keep their anchors in two fields rather than in `points`, so
    // the sheet folds them into the same list the shape tools already use. One
    // coordinate table then serves every kind that has anchors.
    if (drawing.kind == DrawingKind.trend) {
      _points = <ChartPoint>[
        ChartPoint(ms: drawing.startMs, price: drawing.startPrice),
        ChartPoint(ms: drawing.endMs, price: drawing.endPrice),
      ];
    } else {
      _points = <ChartPoint>[...drawing.points];
    }

    _priceFields = <TextEditingController>[
      for (final point in _points)
        TextEditingController(
          text: point.price.toStringAsFixed(widget.decimals),
        ),
    ];
    _textField = TextEditingController(text: drawing.text ?? '');
    if (drawing.kind == DrawingKind.ray) {
      _priceFields.add(
        TextEditingController(text: drawing.price?.toStringAsFixed(widget.decimals)),
      );
    }
    if (drawing.isPosition) {
      _priceFields
        ..clear()
        ..addAll(<TextEditingController>[
          TextEditingController(text: _entry.toStringAsFixed(widget.decimals)),
          TextEditingController(text: _stop.toStringAsFixed(widget.decimals)),
          TextEditingController(text: _target.toStringAsFixed(widget.decimals)),
        ]);
    }
  }

  @override
  void dispose() {
    for (final controller in _priceFields) {
      controller.dispose();
    }
    _textField.dispose();
    super.dispose();
  }

  double _read(TextEditingController controller, double fallback) {
    final value = double.tryParse(controller.text.trim().replaceAll(',', ''));
    return value == null || value <= 0 ? fallback : value;
  }

  /// The object as the sheet currently holds it.
  ChartDrawing _build() {
    final drawing = _drawing;
    switch (drawing.kind) {
      case DrawingKind.trend:
        return ChartDrawing.trend(
          id: drawing.id,
          editedAtMs: drawing.editedAtMs,
          look: _look,
          startMs: _points[0].ms,
          startPrice: _read(_priceFields[0], _points[0].price),
          endMs: _points[1].ms,
          endPrice: _read(_priceFields[1], _points[1].price),
        );
      case DrawingKind.ray:
        return ChartDrawing.ray(
          id: drawing.id,
          editedAtMs: drawing.editedAtMs,
          look: _look,
          price: _read(_priceFields.first, _rayPrice),
        );
      case DrawingKind.position:
        return ChartDrawing.position(
          id: drawing.id,
          editedAtMs: drawing.editedAtMs,
          look: _look,
          side: _side,
          startMs: _startMs,
          endMs: _endMs,
          entry: _read(_priceFields[0], _entry),
          stop: _read(_priceFields[1], _stop),
          target: _read(_priceFields[2], _target),
        );
      default:
        return ChartDrawing.points(
          id: drawing.id,
          editedAtMs: drawing.editedAtMs,
          look: _look,
          kind: drawing.kind,
          points: <ChartPoint>[
            for (var i = 0; i < _points.length; i++)
              ChartPoint(
                ms: _points[i].ms,
                price: _read(_priceFields[i], _points[i].price),
              ),
          ],
          text: drawing.supportsLabel
              ? (_textField.text.trim().isEmpty ? null : _textField.text.trim())
              : drawing.text,
        );
    }
  }

  Future<void> _pickColour() async {
    final picked = await showColorWheelPicker(
      context,
      initial: _look.tint ?? drawingColor,
      title: '${widget.title} colour',
      quickPicks: ChartStyle.candlePalette,
    );
    if (picked == null || !mounted) return;
    setState(() => _look = _look.copyWith(tint: picked));
  }

  /// Changes one anchor's time. Price is edited in a field because it is a
  /// number a trader knows; the time is picked because it is not.
  Future<void> _pickTime(int index) async {
    if (index < 0 || index >= _points.length) return;
    final current = DateTime.fromMillisecondsSinceEpoch(_points[index].ms);
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Anchor date',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: 'Anchor time',
    );
    if (time == null || !mounted) return;
    final next = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      _points[index] = ChartPoint(
        ms: next.millisecondsSinceEpoch,
        price: _points[index].price,
      );
    });
  }

  Future<void> _pickBoxEdge({required bool start}) async {
    final current = DateTime.fromMillisecondsSinceEpoch(start ? _startMs : _endMs);
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: start ? 'Box start date' : 'Box end date',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: start ? 'Box start time' : 'Box end time',
    );
    if (time == null || !mounted) return;
    final next = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).millisecondsSinceEpoch;
    setState(() {
      if (start) {
        _startMs = next;
        if (_endMs < _startMs) _endMs = _startMs;
      } else {
        _endMs = next < _startMs ? _startMs : next;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <String>[
      'Style',
      'Coordinates',
      if (_drawing.supportsLabel) 'Text',
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          children: [
            _header(),
            _tabRow(tabs),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                child: switch (_tab) {
                  0 => _styleTab(),
                  1 => _coordinatesTab(),
                  _ => _textTab(),
                },
              ),
            ),
            const Divider(height: 1),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 16,
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

  Widget _tabRow(List<String> tabs) {
    // Height is a minimum, not a fixed box: at twice the system text size the
    // labels need a second line, and a clipped tab is a tab nobody can read.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      // Scrolls rather than squeezes: with the system text at 200% three tabs
      // are wider than a 320pt phone, and a tab pushed off the edge is a tab
      // the trader cannot open.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
          const SizedBox(width: 4),
          for (var i = 0; i < tabs.length; i++)
            InkWell(
              key: ValueKey<String>('object-tab-$i'),
              onTap: () => setState(() => _tab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _tab == i ? AppColors.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  tabs[i],
                  style: TextStyle(
                    color: _tab == i ? AppColors.text : AppColors.muted,
                    fontSize: 12.5,
                    fontWeight: _tab == i ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _row(String label, Widget control) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Flexible, not fixed: at 200% text a five-chip row is wider than the
          // phone, and a control pushed off the edge cannot be tapped.
          Flexible(child: control),
        ],
      ),
    );
  }

  Widget _styleTab() {
    final drawing = _drawing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Line'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final colour in ChartStyle.candlePalette)
              _Swatch(
                colour: colour,
                selected: _look.tint == colour,
                onTap: () => setState(
                  () => _look = _look.copyWith(tint: colour),
                ),
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(
              label: 'Custom…',
              active: false,
              onTap: _pickColour,
            ),
            _Chip(
              label: 'Chart colour',
              active: _look.tint == null,
              onTap: () => setState(() => _look = _look.copyWith(clearTint: true)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _row(
          'Width',
          Wrap(
            spacing: 6,
            children: [
              for (final width in const <double>[1, 2, 3, 4])
                _Chip(
                  label: '${width.toInt()}px',
                  active: _look.weight == width,
                  onTap: () => setState(() => _look = _look.copyWith(weight: width)),
                ),
              _Chip(
                label: 'Auto',
                active: _look.weight == null,
                onTap: () =>
                    setState(() => _look = _look.copyWith(clearWeight: true)),
              ),
            ],
          ),
        ),
        _row(
          'Line style',
          Wrap(
            spacing: 6,
            children: [
              _Chip(
                label: 'Solid',
                active: !_look.dashed && !_look.dotted,
                onTap: () => setState(
                  () => _look = _look.copyWith(dashed: false, dotted: false),
                ),
              ),
              _Chip(
                label: 'Dashed',
                active: _look.dashed,
                onTap: () => setState(() => _look = _look.copyWith(dashed: true)),
              ),
              _Chip(
                label: 'Dotted',
                active: _look.dotted,
                onTap: () => setState(() => _look = _look.copyWith(dotted: true)),
              ),
            ],
          ),
        ),
        _row(
          'Order',
          Wrap(
            spacing: 6,
            children: [
              _Chip(
                label: 'Front',
                active: false,
                onTap: () => Navigator.of(context).pop(
                  ObjectSettingsResult.change(_build(), order: ObjectOrder.front),
                ),
              ),
              _Chip(
                label: 'Back',
                active: false,
                onTap: () => Navigator.of(context).pop(
                  ObjectSettingsResult.change(_build(), order: ObjectOrder.back),
                ),
              ),
            ],
          ),
        ),
        if (drawing.hasFill) ...[
          _section('Fill'),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: (_look.fill ?? 6).clamp(0, 60).toDouble(),
                    max: 60,
                    divisions: 12,
                    label: '${(_look.fill ?? 6).clamp(0, 60)}%',
                    onChanged: (value) => setState(
                      () => _look = _look.copyWith(fill: value.round()),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${(_look.fill ?? 6).clamp(0, 60)}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () =>
                  setState(() => _look = _look.copyWith(clearFill: true)),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 28),
                foregroundColor: AppColors.muted,
              ),
              child: const Text(
                'Reset to chart default',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
        _section('Object'),
        _toggle(
          label: 'Lock',
          hint: 'Stay put when the chart is panned or dragged',
          value: _look.locked,
          onChanged: (value) => setState(
            () => _look = _look.copyWith(locked: value),
          ),
        ),
        _toggle(
          label: 'Hide',
          hint: 'Keep it in the list, off the chart',
          value: _look.hidden,
          onChanged: (value) => setState(
            () => _look = _look.copyWith(hidden: value),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(
                  ObjectSettingsResult.clone(_build()),
                ),
                icon: const Icon(Icons.copy_all_outlined, size: 16),
                label: const Text('Clone'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(const ObjectSettingsResult.remove()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: BorderSide(color: AppColors.danger.withAlpha(110)),
                ),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Remove'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _toggle({
    required String label,
    required String hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: TextStyle(color: AppColors.faint, fontSize: 10.5),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _priceField(int index) {
    return SizedBox(
      width: 108,
      child: TextField(
        controller: _priceFields[index],
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: TextStyle(
          color: AppColors.text,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  /// A time the trader can actually change, formatted the way the chart's own
  /// axis reads it.
  Widget _timeChip(String label, {required VoidCallback onTap}) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        foregroundColor: AppColors.text,
        side: BorderSide(color: AppColors.border),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _coordinatesTab() {
    final drawing = _drawing;
    final timeFormat = DateFormat('d MMM HH:mm');

    if (drawing.isPosition) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section('Side'),
          Row(
            children: [
              Expanded(
                child: _Chip(
                  label: 'Long',
                  active: _side == PositionSide.long,
                  onTap: () => setState(() => _side = PositionSide.long),
                  tone: AppColors.success,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Chip(
                  label: 'Short',
                  active: _side == PositionSide.short,
                  onTap: () => setState(() => _side = PositionSide.short),
                  tone: AppColors.danger,
                ),
              ),
            ],
          ),
          _section('Levels'),
          _row('Entry', _priceField(0)),
          _row('Stop', _priceField(1)),
          _row('Target', _priceField(2)),
          _section('Box'),
          _row(
            'Start',
            _timeChip(
              timeFormat.format(DateTime.fromMillisecondsSinceEpoch(_startMs)),
              onTap: () => _pickBoxEdge(start: true),
            ),
          ),
          _row(
            'End',
            _timeChip(
              timeFormat.format(DateTime.fromMillisecondsSinceEpoch(_endMs)),
              onTap: () => _pickBoxEdge(start: false),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'End is the right edge of the box. A box that stops where the idea '
            'stopped stays honest about when it was drawn.',
            style: TextStyle(color: AppColors.faint, fontSize: 10.5, height: 1.4),
          ),
        ],
      );
    }

    if (drawing.kind == DrawingKind.ray) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section('Price'),
          _row('Level', _priceField(_priceFields.length - 1)),
          const SizedBox(height: 10),
          Text(
            'A level is the same price on every chart. Drag it to move it.',
            style: TextStyle(color: AppColors.faint, fontSize: 10.5),
          ),
        ],
      );
    }

    if (_points.length > 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section('Stroke'),
          Text(
            'This freehand object holds ${_points.length} points. Drag it on '
            'the chart to move it, or restyle it in Style.',
            style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.5),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Anchors'),
        for (var i = 0; i < _points.length; i++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    '#${i + 1}',
                    style: TextStyle(
                      color: AppColors.faint,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: _timeChip(
                    timeFormat.format(
                      DateTime.fromMillisecondsSinceEpoch(_points[i].ms),
                    ),
                    onTap: () => _pickTime(i),
                  ),
                ),
                if (drawing.kind != DrawingKind.vline) ...[
                  const SizedBox(width: 8),
                  _priceField(i),
                ],
              ],
            ),
          ),
        ],
        if (drawing.kind == DrawingKind.vline)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'A vertical line marks a moment, so only its time matters.',
              style: TextStyle(color: AppColors.faint, fontSize: 10.5),
            ),
          ),
        if (drawing.carriesText)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'The label sits above its anchor point.',
              style: TextStyle(color: AppColors.faint, fontSize: 10.5),
            ),
          ),
      ],
    );
  }

  Widget _textTab() {
    final placement = _drawing.carriesText
        ? 'The label sits above its anchor point.'
        : 'The label sits just above the object, so the note stays with the thing '
            'it is about.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Label'),
        TextField(
          controller: _textField,
          minLines: 3,
          maxLines: 6,
          maxLength: 200,
          style: TextStyle(color: AppColors.text, fontSize: 13.5, height: 1.4),
          decoration: const InputDecoration(
            hintText: 'What this mark is saying',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        Text(
          '$placement A short note beats a paragraph: the chart is read at a '
          'glance, and a label that needs reading twice is in the way.',
          style: TextStyle(color: AppColors.faint, fontSize: 10.5, height: 1.45),
        ),
      ],
    );
  }

  Widget _footer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  foregroundColor: AppColors.muted,
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  ObjectSettingsResult.change(_build()),
                ),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                child: const Text('Ok'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One colour in the picker. The ring is drawn outside the dot so the colour
/// itself is never tinted by its own selection state.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.colour,
    required this.selected,
    required this.onTap,
  });

  final Color colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 30,
        height: 30,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.text : Colors.transparent,
            width: 2,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colour,
            border: Border.all(color: AppColors.border),
          ),
        ),
      ),
    );
  }
}

/// A small segmented option: effective, and it reads at arm's length.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
    this.tone,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final colour = tone ?? AppColors.primary;
    return Material(
      color: active ? colour.withAlpha(30) : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.field),
        child: Container(
          height: 34,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.field),
            border: Border.all(
              color: active ? colour : AppColors.border,
              width: active ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? colour : AppColors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
