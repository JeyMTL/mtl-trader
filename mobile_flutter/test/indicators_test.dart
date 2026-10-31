import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/indicators.dart';

void main() {
  group('simple moving average', () {
    test('averages the trailing window and stays null before it fills', () {
      final values = [1.0, 2.0, 3.0, 4.0, 5.0];
      expect(sma(values, 3), [null, null, 2.0, 3.0, 4.0]);
    });

    test('returns nothing when the series is shorter than the period', () {
      expect(sma([1.0, 2.0], 5), [null, null]);
    });

    test('handles a period of one as the values themselves', () {
      expect(sma([3.0, 1.5, 7.0], 1), [3.0, 1.5, 7.0]);
    });

    test('ignores a non-positive period instead of dividing by zero', () {
      expect(sma([1.0, 2.0], 0), [null, null]);
    });
  });

  group('exponential moving average', () {
    test('seeds with the SMA then applies the smoothing factor', () {
      // period 3 over 1..6: seed = (1+2+3)/3 = 2 at index 2;
      // k = 0.5, so 2 + 0.5*(4-2) = 3, then 4, then 5.
      final values = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0];
      expect(ema(values, 3), [null, null, 2.0, 3.0, 4.0, 5.0]);
    });

    test('returns nothing when the series is shorter than the period', () {
      expect(ema([1.0, 2.0], 3), [null, null]);
    });
  });

  group('study series', () {
    test('routes each study to its own maths', () {
      final closes = List<double>.generate(60, (i) => i + 1);
      final sma20 = studySeries(OverlayStudy.sma20, closes);
      expect(sma20[18], isNull);
      expect(sma20[19], 10.5); // average of 1..20
      final ema21 = studySeries(OverlayStudy.ema21, closes);
      expect(ema21[19], isNull);
      expect(ema21[20], 11.0); // SMA seed of 1..21
    });

    test('leaves long periods empty rather than throwing', () {
      final closes = List<double>.filled(10, 2);
      expect(studySeries(OverlayStudy.sma200, closes).every((v) => v == null), isTrue);
    });
  });

  group('rsi', () {
    test('pegs a rising series at 100 once warmed up', () {
      final closes = List<double>.generate(20, (i) => i + 1);
      final values = rsi(closes);
      expect(values[13], isNull);
      expect(values[14], 100);
      expect(values.last, 100);
    });

    test('pegs a falling series at 0', () {
      final closes = List<double>.generate(20, (i) => 100 - i.toDouble());
      expect(rsi(closes).last, 0);
    });
  });

  group('macd', () {
    test('flattens on a constant series', () {
      final closes = List<double>.filled(80, 10);
      final last = macd(closes).last;
      expect(last, isNotNull);
      expect(last!.macd, closeTo(0, 1e-9));
      expect(last.histogram, closeTo(0, 1e-9));
    });

    test('stays null until both averages exist', () {
      expect(macd(List<double>.filled(20, 1)).every((v) => v == null), isTrue);
    });
  });

  group('custom lengths', () {
    test('honours a custom RSI period', () {
      final closes = List<double>.generate(20, (i) => i + 1);
      final values = rsi(closes, period: 7);
      expect(values[6], isNull);
      expect(values[7], 100);
    });

    test('honours custom MACD lengths', () {
      final closes = List<double>.generate(100, (i) => 1 + i * 0.1);
      final points = macd(closes, fast: 5, slow: 35, signal: 5);
      expect(points, hasLength(closes.length));
      expect(points.last, isNotNull);
    });
  });
}
