import 'dart:async';

import 'package:flutter/material.dart';

import '../core/chart_zone.dart';
import 'theme.dart';
import 'widgets.dart';

/// A ticking wall clock for the zone the trader selected.
///
/// The account screen used to carry a refresh button in the app bar, which did
/// nothing visible: the tab already refreshes on open and on pull-to-refresh.
/// What a trader actually glances at is the time the journal is scoring in, so
/// this shows a 24-hour clock with seconds in the account's timezone, and the
/// zone plus its offset underneath so the reading is never ambiguous.
///
/// It ticks once a second off [DateTime.now], which means a timezone changed
/// elsewhere is picked up on the next tick without any notification plumbing.
class ZoneClock extends StatefulWidget {
  const ZoneClock({super.key, required this.zoneId, this.compact = false});

  /// IANA name, or empty for the device clock.
  final String zoneId;

  /// Drops the zone label, for a bar with no room for two lines.
  final bool compact;

  @override
  State<ZoneClock> createState() => _ZoneClockState();
}

class _ZoneClockState extends State<ZoneClock> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final zone = ChartZone.byId(widget.zoneId);
    final wall = zone.wall(_now.toUtc());
    final time = '${_two(wall.hour)}:${_two(wall.minute)}:${_two(wall.second)}';

    return Semantics(
      label: '$time ${zone.describe()}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              time,
              style: tabular.copyWith(
                color: AppColors.text,
                fontSize: widget.compact ? 14 : 15.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            if (!widget.compact)
              Text(
                zone.isDevice ? 'Device' : zone.label,
                style: TextStyle(
                  color: AppColors.faint,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
