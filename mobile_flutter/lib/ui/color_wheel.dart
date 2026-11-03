import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A hue/saturation wheel with a brightness slider.
///
/// The chart's candle colours used to be a fixed ten-swatch palette, which is a
/// shortlist somebody else chose: a trader whose platform draws green at
/// `0xFF00B050` and red at `0xFFE2363A` could get close, never exact. A wheel
/// removes the shortlist — any colour the screen can show is one gesture away —
/// while the quick picks stay underneath for the common case.
///
/// The maths is top-level and pure so the wheel can be tested without pumping a
/// dialog: [hsvFromWheel] maps a point in the wheel to hue/saturation and
/// [colorToHex] renders the value the trader copies into their notes.

/// Hue and saturation for a point inside the wheel, at [value] brightness.
///
/// Hue is the angle (0° at 3 o'clock, growing clockwise), saturation the
/// distance from the centre as a fraction of the radius, so the middle of the
/// wheel is white at full brightness and black at zero.
HSVColor hsvFromWheel({
  required Offset point,
  required Size size,
  required double value,
}) {
  final radius = size.shortestSide / 2;
  if (radius <= 0) {
    return HSVColor.fromAHSV(1, 0, 0, value.clamp(0.0, 1.0));
  }
  final center = Offset(size.width / 2, size.height / 2);
  final offset = point - center;
  final distance = offset.distance.clamp(0.0, radius);
  // atan2 is 0 at the centre too, which is fine: saturation is 0 there, so the
  // hue cannot show.
  final hue = (math.atan2(offset.dy, offset.dx) * 180 / math.pi + 360) % 360;
  return HSVColor.fromAHSV(
    1,
    hue,
    distance / radius,
    value.clamp(0.0, 1.0),
  );
}

/// `0xFF45D29A` → `#45D29A`.
String colorToHex(Color color) {
  final argb = color.toARGB32();
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return '#${rgb.toUpperCase()}';
}

/// Opens the wheel and returns the chosen colour, or null when cancelled.
Future<Color?> showColorWheelPicker(
  BuildContext context, {
  required Color initial,
  required String title,
  List<Color> quickPicks = const <Color>[],
}) {
  return showDialog<Color>(
    context: context,
    builder: (dialogContext) => _ColorWheelDialog(
      initial: initial,
      title: title,
      quickPicks: quickPicks,
    ),
  );
}

class _ColorWheelDialog extends StatefulWidget {
  const _ColorWheelDialog({
    required this.initial,
    required this.title,
    required this.quickPicks,
  });

  final Color initial;
  final String title;
  final List<Color> quickPicks;

  @override
  State<_ColorWheelDialog> createState() => _ColorWheelDialogState();
}

class _ColorWheelDialogState extends State<_ColorWheelDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  Size _wheelSize = Size.zero;

  void _pick(Offset local) {
    if (_wheelSize.width <= 0) return;
    final next = hsvFromWheel(
      point: local,
      size: _wheelSize,
      value: _hsv.value,
    );
    setState(() => _hsv = next);
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return AlertDialog(
      backgroundColor: const Color(0xFF12151C),
      title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _wheelSize = Size(constraints.maxWidth, constraints.maxHeight);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanDown: (details) => _pick(details.localPosition),
                    onPanUpdate: (details) => _pick(details.localPosition),
                    child: CustomPaint(painter: _WheelPainter(_hsv)),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF333B4B)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    colorToHex(color),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      fontFamily: 'JetBrainsMono',
                      color: Color(0xFFEDF0F5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.brightness_6_outlined,
                  size: 16,
                  color: Color(0xFF6B7280),
                ),
                Expanded(
                  child: Slider(
                    value: _hsv.value,
                    onChanged: (value) =>
                        setState(() => _hsv = _hsv.withValue(value)),
                  ),
                ),
              ],
            ),
            if (widget.quickPicks.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final quick in widget.quickPicks)
                    GestureDetector(
                      onTap: () => setState(() => _hsv = HSVColor.fromColor(quick)),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: quick,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: quick.toARGB32() == color.toARGB32()
                                ? Colors.white
                                : const Color(0xFF333B4B),
                            width: quick.toARGB32() == color.toARGB32() ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, color),
          child: const Text('Use colour'),
        ),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Hue around the circle, desaturated towards the middle: the sweep gives the
    // ring its colours and the white radial gradient does the rest. Painting it
    // this way keeps it a two-shader wheel instead of thousands of per-pixel
    // samples on a screen that repaints while a finger is moving.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = SweepGradient(
          colors: [
            for (var step = 0; step <= 6; step++)
              HSVColor.fromAHSV(1, (step * 60) % 360, 1, 1).toColor(),
          ],
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white, Colors.white.withAlpha(0)],
        ).createShader(rect),
    );

    // Brightness dims the whole wheel so the picked colour is what the trader
    // sees, not a preview they have to imagine.
    if (hsv.value < 1) {
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = Colors.black.withAlpha(((1 - hsv.value) * 255).round()),
      );
    }

    final angle = hsv.hue * math.pi / 180;
    final marker = center +
        Offset(math.cos(angle), math.sin(angle)) * (hsv.saturation * radius);
    canvas.drawCircle(marker, 9, Paint()..color = Colors.white);
    canvas.drawCircle(
      marker,
      6,
      Paint()..color = hsv.toColor(),
    );
    canvas.drawCircle(
      marker,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black.withAlpha(120),
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) =>
      oldDelegate.hsv != hsv;
}
