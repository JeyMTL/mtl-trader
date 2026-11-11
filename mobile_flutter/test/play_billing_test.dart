import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/services/play_billing.dart';

void main() {
  test('a plan not owned yet can be bought when Play has the product', () {
    expect(
      canBuyWithPlay(current: false, yearly: false, enabled: true, hasProduct: true),
      isTrue,
    );
  });

  test('re-buying the cadence already owned is refused', () {
    expect(
      canBuyWithPlay(current: true, yearly: false, enabled: true, hasProduct: true),
      isFalse,
    );
  });

  test('a monthly subscriber can switch to the annual base plan', () {
    expect(
      canBuyWithPlay(current: true, yearly: true, enabled: true, hasProduct: true),
      isTrue,
    );
  });

  test('no sellable product leaves the button dead', () {
    expect(
      canBuyWithPlay(current: false, yearly: false, enabled: true, hasProduct: false),
      isFalse,
    );
    expect(
      canBuyWithPlay(current: false, yearly: false, enabled: false, hasProduct: true),
      isFalse,
    );
  });
}
