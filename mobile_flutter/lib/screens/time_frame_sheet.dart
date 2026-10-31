import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/market_data.dart';
import '../ui/theme.dart';

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
      DateTime(picked.year, picked.month, picked.day, current.hour, current.minute),
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
      DateTime(current.year, current.month, current.day, picked.hour, picked.minute),
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
        OutlinedButton(
          onPressed: () => _pickTime(start: start),
          child: Text(DateFormat('HH:mm').format(value)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final bars = _bars;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chart time frame',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick the period and the candle size. Both are sent to the feed as-is.',
              style: TextStyle(
                color: AppColors.faint,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'QUICK SPANS',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final shortcut in _shortcuts.entries)
                  OutlinedButton(
                    onPressed: () => _applyShortcut(shortcut.value),
                    child: Text(shortcut.key),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'FROM · TO',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            _row('From', _from, start: true),
            const SizedBox(height: 8),
            _row('To', _to, start: false),
            const SizedBox(height: 14),
            Text(
              'CANDLE SIZE',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
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
                  : '≈ $bars candles',
              style: TextStyle(
                color: bars == null ? AppColors.danger : AppColors.faint,
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
            if (problem != null) ...[
              const SizedBox(height: 6),
              Text(
                problem,
                style: TextStyle(color: AppColors.danger, fontSize: 11.5),
              ),
            ],
            const SizedBox(height: 16),
            Row(
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
          ],
        ),
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
          color: selected ? AppColors.primary.withAlpha(30) : AppColors.surfaceAlt,
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
