import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/chart_scale.dart';

void main() {
  group('linear scale', () {
    test('puts max at the top and min at the bottom', () {
      expect(ratioForPrice(price: 200, min: 100, max: 200, logScale: false), 0);
      expect(ratioForPrice(price: 100, min: 100, max: 200, logScale: false), 1);
      expect(
        priceForRatio(ratio: 0.5, min: 100, max: 200, logScale: false),
        150,
      );
    });

    test('round-trips a price', () {
      final ratio = ratioForPrice(price: 137, min: 100, max: 200, logScale: false);
      expect(
        priceForRatio(ratio: ratio, min: 100, max: 200, logScale: false),
        closeTo(137, 1e-9),
      );
    });
  });

  group('log scale', () {
    test('places the geometric mean in the middle', () {
      expect(
        priceForRatio(ratio: 0.5, min: 100, max: 10000, logScale: true),
        closeTo(1000, 1e-6),
      );
    });

    test('round-trips a price', () {
      final ratio = ratioForPrice(price: 1000, min: 100, max: 10000, logScale: true);
      expect(
        priceForRatio(ratio: ratio, min: 100, max: 10000, logScale: true),
        closeTo(1000, 1e-6),
      );
    });

    test('falls back to linear when a bound is not positive', () {
      expect(
        priceForRatio(ratio: 0.5, min: 0, max: 10, logScale: true),
        5,
      );
      expect(
        ratioForPrice(price: 5, min: -10, max: 10, logScale: true),
        closeTo(0.25, 1e-9),
      );
    });
  });
}
