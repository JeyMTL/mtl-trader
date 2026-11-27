import 'package:flutter/material.dart';

import '../services/market_data.dart';
import '../ui/theme.dart';

/// Longest window `/api/market/candles` accepts for an explicit range.
const Duration maxChartTimeFrame = Duration(days: 62);

/// The candle sizes in the order a trader reads a chart: minutes, then hours,
/// then the day. Not alphabetical, not enum order — the order the buttons sit
/// in on a desk, smallest detail first.
const List<ChartInterval> chartTimeFrames = <ChartInterval>[
  ChartInterval.fiveSeconds,
  ChartInterval.tenSeconds,
  ChartInterval.fifteenSeconds,
  ChartInterval.thirtySeconds,
  ChartInterval.fortyFiveSeconds,
  ChartInterval.oneMinute,
  ChartInterval.fiveMinutes,
  ChartInterval.fifteenMinutes,
  ChartInterval.thirtyMinutes,
  ChartInterval.oneHour,
  ChartInterval.fourHours,
  ChartInterval.oneDay,
];

/// The candle sizes sold with Pro. Basic keeps 30s and 45s and every size from a
/// minute up; the 5s/10s/15s sizes are what a scalper pays for, so they stay on
/// the sheet with a Pro tag instead of disappearing from it.
const Set<String> proTimeFrameKeys = {'5s', '10s', '15s'};

/// Whether this candle size needs Pro.
bool isProTimeFrame(ChartInterval interval) =>
    proTimeFrameKeys.contains(interval.key);

/// The sub-minute sizes Basic buys. The free chart runs from a minute up, so a
/// seconds size is always either Basic or Pro — never free. Tagged on the sheet
/// for the same reason the Pro sizes are: the trader should see the price of
/// the size before choosing it.
const Set<String> basicTimeFrameKeys = {'30s', '45s'};

/// Whether this candle size needs Basic (or Pro).
bool isBasicTimeFrame(ChartInterval interval) =>
    basicTimeFrameKeys.contains(interval.key);

/// What the trader chose: the live tail, or an explicit window and candle size.
///
/// The window is kept as a type because the loader still understands it, but
/// the picker only ever returns the live tail with a candle size. A range is
/// something you pan into, not something you set before looking.
class ChartTimeFrame {
  const ChartTimeFrame.live({this.interval})
      : isLive = true,
        from = null,
        to = null;

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

/// Asks for the candle size. Null when dismissed.
Future<ChartTimeFrame?> showChartTimeFrameSheet({
  required BuildContext context,
  required ChartInterval interval,
  Set<ChartInterval> refused = const {},
}) {
  return showModalBottomSheet<ChartTimeFrame>(
    context: context,
    backgroundColor: AppColors.surface,
    // Twelve sizes on a phone need the taller sheet; the cap keeps a strip of
    // chart visible above it so the choice is not made blind.
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxWidth: 460,
      maxHeight: MediaQuery.sizeOf(context).height * 0.78,
    ),
    builder: (_) => _TimeFrameSheet(interval: interval, refused: refused),
  );
}

class _TimeFrameSheet extends StatelessWidget {
  const _TimeFrameSheet({required this.interval, required this.refused});

  final ChartInterval interval;

  /// Sizes this account's feed answered with "Unknown candle interval". They
  /// stay listed but cannot be picked, because a row that looks available and
  /// then empties the chart is worse than a row that says why.
  final Set<ChartInterval> refused;

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Time frame',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                Text(
                  'LIVE',
                  style: TextStyle(
                    color: AppColors.primaryLight,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  for (final entry in chartTimeFrames)
                    _TimeFrameRow(
                      interval: entry,
                      selected: entry == interval,
                      refused: refused.contains(entry),
                      badge: isProTimeFrame(entry)
                          ? 'PRO'
                          : (isBasicTimeFrame(entry) ? 'BASIC' : null),
                      onTap: refused.contains(entry)
                          ? null
                          : () => Navigator.of(context).pop(
                                ChartTimeFrame.live(interval: entry),
                              ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One candle size. A full-width row rather than a chip: the sizes read as a
/// list, and a row is a target the thumb finds without aiming.
class _TimeFrameRow extends StatelessWidget {
  const _TimeFrameRow({
    required this.interval,
    required this.selected,
    required this.onTap,
    this.refused = false,
    this.badge,
  });

  final ChartInterval interval;
  final bool selected;
  final bool refused;

  /// The plan that sells this size (`PRO` or `BASIC`), or null when it is free.
  /// The row still answers: the caller refuses and explains, so the trader
  /// learns the price instead of finding a dead row.
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = refused
        ? AppColors.faint
        : (selected ? AppColors.primaryLight : AppColors.text);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Container(
        height: 42,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withAlpha(24) : null,
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              child: Text(
                interval.key.toUpperCase(),
                style: TextStyle(
                  color: ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            Expanded(
              child: Text(
                refused ? 'Not served by this chart feed yet' : interval.detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: refused
                      ? AppColors.faint
                      : (selected
                          ? AppColors.primaryLight
                          : AppColors.muted),
                  fontSize: 11.5,
                ),
              ),
            ),
            if (badge != null && !refused)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(28),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    color: AppColors.primaryLight,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            if (badge != null && !refused) const SizedBox(width: 6),
            if (selected && !refused)
              Icon(Icons.check, size: 16, color: AppColors.primaryLight),
          ],
        ),
      ),
    );
  }
}
