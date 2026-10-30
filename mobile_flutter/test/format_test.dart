import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/format.dart';

void main() {
  test('formats known clock durations', () {
    expect(clockText(0), '0:00');
    expect(clockText(83), '1:23');
    expect(clockText(600), '10:00');
  });

  test('keeps an unknown audio duration distinct from zero', () {
    expect(clockText(null), '—');
  });

  test('formats hold time in minutes and hours', () {
    expect(durationText(null), '—');
    expect(durationText(45), '45m');
    expect(durationText(95), '1h 35m');
    expect(durationText(120), '2h');
  });
}
