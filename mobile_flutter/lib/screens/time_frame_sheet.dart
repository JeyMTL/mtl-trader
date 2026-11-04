import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/market_data.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Longest window `/api/market/candles` accepts.
const Duration maxChartTimeFrame = Duration(days: 62);

/// What the trader chose: the live tail, or an explicit window and candle size.
class ChartTimeFrame {
  const ChartTimeFrame.live()
      : isLive = true,
        from = null,
        to = null,
        interval = null;

  const ChartTimeFrame.custom({
    required this.from,
    required this.to,
    required this.interval,
  }) : isLive = false;

  final bool isLive;
  final DateTime? from;
  final DateTime? to;
  final ChartInterval? interval;
}

/// Asks for the period and candle size to chart. Null when dismissed.
Future<ChartTimeFrame?> showChartTimeFrameSheet({
  required BuildContext context,
  required DateTime from,
  required DateTime to,
  required ChartInterval interval,
}) {
  return showModalBottomSheet<ChartTimeFrame>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    builder: (_) => _TimeFrameSheet(from: from, to: to, interval: interval),
  );
}

class _TimeFrameSheet extends StatefulWidget {
  const _TimeFrameSheet({
    required this.from,
    required this.to,
    required this.interval,
  });

  final DateTime from;
  final DateTime to;
  final ChartInterval interval;

  @override
  State<_TimeFrameSheet> createState() => _TimeFrameSheetState();
}

class _TimeFrameSheetState extends State<_TimeFrameSheet> {
  /// Common spans, one tap each: they end at the latest candle and pick a
  /// candle size that fits the span.
  static const Map<String, Duration> _shortcuts = {
    '1 Day': Duration(days: 1),
    '1 Week': Duration(days: 7),
    '1 Month': Duration(days: 30),
  };

  late DateTime _from = widget.from;
  late DateTime _to = widget.to;
  late ChartInterval _interval = widget.interval;

  Duration get _span => _to.difference(_from);

  int? get _bars => _span.isNegative ? null : candleCountFor(_span, _interval);

  bool get _valid => _problem == null;

  String? get _problem {
    if (!_to.isAfter(_from)) return 'The end has to come after the start.';
    if (_span > maxChartTimeFrame) return 'Keep the window within 62 days.';
    if (_bars == null) {
      return 'That needs more than $maxCandlesPerRequest candles. Pick a larger candle size or a shorter window.';
    }
    return null;
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final current = start ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isAfter(now) ? now : current,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      helpText: start ? 'Chart starts' : 'Chart ends',
    );
    if (picked == null || !mounted) return;
    _replace(
      start,
      DateTime(
          picked.year, picked.month, picked.day, current.hour, current.minute),
    );
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _from : _to;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: start ? 'Chart starts at' : 'Chart ends at',
    );
    if (picked == null || !mounted) return;
    _replace(
      start,
      DateTime(
          current.year, current.month, current.day, picked.hour, picked.minute),
    );
  }

  void _applyShortcut(Duration span) {
    final to = DateTime.now();
    Navigator.of(context).pop(
      ChartTimeFrame.custom(
        from: to.subtract(span),
        to: to,
        interval: defaultIntervalFor(span),
      ),
    );
  }

  void _replace(bool start, DateTime value) {
    setState(() {
      if (start) {
        _from = value;
      } else {
        _to = value;
      }
    });
  }

  Widget _row(String label, DateTime value, {required bool start}) {
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: OutlinedButton(
            onPressed: () => _pickDate(start: start),
            child: Text(DateFormat('d MMM yyyy').format(value)),
          ),
        ),
        const SizedBox(width: 8),
        // The app theme makes outlined buttons full-width, so a button in a
        // Row needs an explicit width or its infinite minimum size crashes
        // layout.
        SizedBox(
          width: 88,
          child: OutlinedButton(
            onPressed: () => _pickTime(start: start),
            child: Text(DateFormat('HH:mm').format(value)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final bars = _bars;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chart time frame',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Pick the period and the candle size, or jump to the newest candles.',
                  style: TextStyle(
                    color: AppColors.faint,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsSection(
                    title: 'Quick spans',
                    children: [
                      // Three equal targets rather than three fixed-width
                      // buttons that wrapped onto a second line on a narrow
                      // phone before anything else could be reached.
                      Row(
                        children: [
                          for (var i = 0; i < _shortcuts.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _applyShortcut(
                                  _shortcuts.values.elementAt(i),
                                ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                ),
                                child: Text(
                                  _shortcuts.keys.elementAt(i),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Each one ends at the newest candle and picks a candle size that fits.',
                        style: TextStyle(
                          color: AppColors.faint,
                          fontSize: 10,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: 'Window',
                    children: [
                      _row('From', _from, start: true),
                      const SizedBox(height: 8),
                      _row('To', _to, start: false),
                    ],
                  ),
                  SettingsSection(
                    title: 'Candle size',
                    trailing: _interval.key.toUpperCase(),
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final interval in ChartInterval.values)
                            _IntervalChip(
                              interval: interval,
                              selected: interval == _interval,
                              onTap: () => setState(() => _interval = interval),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        bars == null
                            ? 'Too many candles at this size.'
                            : '≈ $bars candles in this window',
                        style: TextStyle(
                          color:
                              bars == null ? AppColors.danger : AppColors.faint,
                          fontSize: 10.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                  if (problem != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
                      child: Text(
                        problem,
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(const ChartTimeFrame.live()),
                    child: const Text('Latest candles'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _valid
                        ? () => Navigator.of(context).pop(
                              ChartTimeFrame.custom(
                                from: _from,
                                to: _to,
                                interval: _interval,
                              ),
                            )
                        : null,
                    child: const Text('Apply'),
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

/// One selectable candle size.
class _IntervalChip extends StatelessWidget {
  const _IntervalChip({
    required this.interval,
    required this.selected,
    required this.onTap,
  });

  final ChartInterval interval;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color:
              selected ? AppColors.primary.withAlpha(30) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          interval.key.toUpperCase(),
          style: TextStyle(
            color: selected ? AppColors.primaryLight : AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
