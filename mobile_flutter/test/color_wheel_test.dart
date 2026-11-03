import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/ui/color_wheel.dart';

/// The wheel's maths is pure, so it is tested without pumping a dialog: a tap
/// has to land on the colour under the finger, and a hex string has to be what
/// the trader reads.
void main() {
  const size = Size(200, 200);

  test('the right edge of the wheel is hue 0 at full saturation', () {
    final hsv = hsvFromWheel(
      point: const Offset(200, 100),
      size: size,
      value: 1,
    );
    expect(hsv.hue, closeTo(0, 0.001));
    expect(hsv.saturation, closeTo(1, 0.001));
  });

  test('the bottom edge is hue 90', () {
    final hsv = hsvFromWheel(
      point: const Offset(100, 200),
      size: size,
      value: 1,
    );
    expect(hsv.hue, closeTo(90, 0.001));
    expect(hsv.saturation, closeTo(1, 0.001));
  });

  test('the centre of the wheel is unsaturated', () {
    final hsv = hsvFromWheel(
      point: const Offset(100, 100),
      size: size,
      value: 1,
    );
    expect(hsv.saturation, closeTo(0, 0.001));
  });

  test('a point past the rim clamps to full saturation', () {
    final hsv = hsvFromWheel(
      point: const Offset(400, 100),
      size: size,
      value: 0.5,
    );
    expect(hsv.saturation, closeTo(1, 0.001));
    expect(hsv.value, closeTo(0.5, 0.001));
  });

  test('hue wraps rather than going negative above the centre', () {
    final hsv = hsvFromWheel(
      point: const Offset(100, 0),
      size: size,
      value: 1,
    );
    expect(hsv.hue, closeTo(270, 0.001));
  });

  test('hex is the six RGB digits in upper case', () {
    expect(colorToHex(const Color(0xFF45D29A)), '#45D29A');
    expect(colorToHex(const Color(0xFF0A0B0C)), '#0A0B0C');
  });
}
