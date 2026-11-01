import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A frame-time readout drawn over the app, off unless someone turns it on.
///
/// DevTools needs a cable, a profile build and a desktop window. This answers the
/// only question a trader or a tester can actually ask on a handset — "does it
/// stutter?" — with numbers: the worst frame in the last second, split into the
/// build and raster halves, coloured against the 16.7 ms budget for 60 fps.
///
/// It is a debug aid, not telemetry: nothing is recorded, uploaded or persisted
/// except the on/off switch.
class FrameOverlaySettings {
  const FrameOverlaySettings._();

  static const String storageKey = 'debug.frameOverlay.v1';

  /// Read by the overlay and by the switch in Account.
  static final ValueNotifier<bool> visible = ValueNotifier<bool>(false);

  /// Restores the choice; a missing or unreadable value leaves it off.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      visible.value = prefs.getBool(storageKey) ?? false;
    } catch (_) {
      visible.value = false;
    }
  }

  static Future<void> set(bool value) async {
    visible.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(storageKey, value);
    } catch (_) {
      // A switch that cannot be remembered still works for this session.
    }
  }
}

class PerfOverlay extends StatefulWidget {
  const PerfOverlay({super.key, this.child});

  /// The app to draw over. Omitted when the overlay is used as a sibling.
  final Widget? child;

  @override
  State<PerfOverlay> createState() => _PerfOverlayState();
}

class _PerfOverlayState extends State<PerfOverlay> {
  static const int _windowSize = 60;
  static const double _budgetMs = 1000 / 60;

  final List<FrameTiming> _frames = <FrameTiming>[];

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!mounted || !FrameOverlaySettings.visible.value) return;
    _frames.addAll(timings);
    if (_frames.length > _windowSize) {
      _frames.removeRange(0, _frames.length - _windowSize);
    }
    // One rebuild per batch of frames, not one per frame.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: FrameOverlaySettings.visible,
      builder: (context, visible, child) {
        if (!visible) return child ?? const SizedBox.shrink();
        return Stack(
          children: [
            if (child != null) child,
            Positioned(
              right: 8,
              top: MediaQuery.of(context).padding.top + 8,
              child: IgnorePointer(child: _panel()),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }

  Widget _panel() {
    if (_frames.isEmpty) {
      return _chip('measuring…', const Color(0xFF6B7280));
    }
    var worstTotal = 0.0;
    var sumBuild = 0.0;
    var sumRaster = 0.0;
    for (final frame in _frames) {
      final total = frame.totalSpan.inMicroseconds / 1000;
      if (total > worstTotal) worstTotal = total;
      sumBuild += frame.buildDuration.inMicroseconds / 1000;
      sumRaster += frame.rasterDuration.inMicroseconds / 1000;
    }
    final count = _frames.length;
    final fps = worstTotal > 0 ? (1000 / worstTotal).clamp(0, 120) : 0;
    final color = worstTotal <= _budgetMs
        ? const Color(0xFF45D29A)
        : worstTotal <= _budgetMs * 2
            ? const Color(0xFFF0B90B)
            : const Color(0xFFF26B78);

    return _chip(
      '${fps.round()} fps · worst ${worstTotal.toStringAsFixed(1)} ms\n'
      'build ${(sumBuild / count).toStringAsFixed(1)} · '
      'raster ${(sumRaster / count).toStringAsFixed(1)} ms',
      color,
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xE6080A0F),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(140)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(
          color: color,
          fontSize: 10,
          height: 1.35,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
