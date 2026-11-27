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

  group('prices', () {
    test('a synced gold price loses its float noise', () {
      expect(price(3595.7380000000003), '3595.738');
      expect(price(3587.8869999999997), '3587.887');
      expect(price(3625.1949999999997), '3625.195');
    });

    test('a synced forex price reads as it was quoted', () {
      expect(price(1.0984600000000002), '1.09846');
    });

    test('trailing zeros are trimmed, so a whole price has no decimal point', () {
      expect(price(3595), '3595');
      expect(price(1.0), '1');
      expect(price(2400.50000), '2400.5');
    });

    test('lots lose their own noise at two decimals', () {
      expect(price(0.1 + 0.2, decimals: 2), '0.3');
      expect(price(0.5, decimals: 2), '0.5');
    });

    test('an unknown or non-finite value is a dash, not NaN', () {
      expect(price(null), '—');
      expect(price(double.nan), '—');
      expect(price(double.infinity), '—');
    });

    test('a value that underflows to nothing reads zero, without a sign', () {
      expect(price(-0.0000001), '0');
    });
  });

  test('a count takes the right noun, singular and plural', () {
    expect(countNoun(1, 'trade'), '1 trade');
    expect(countNoun(0, 'trade'), '0 trades');
    expect(countNoun(2, 'trade'), '2 trades');
    expect(countNoun(1, 'day'), '1 day');
    // A noun that does not just take an s passes its plural.
    expect(countNoun(1, 'entry', plural: 'entries'), '1 entry');
    expect(countNoun(3, 'entry', plural: 'entries'), '3 entries');
  });
}
