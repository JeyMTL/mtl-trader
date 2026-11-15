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

  test('a Play refusal points at the store install, not the card', () {
    final message = playFailureMessage('BillingResponse.developerError');
    expect(message, contains('Install it from the'));
    expect(message, isNot(contains('developerError')));
  });

  test('a cancelled purchase says nothing was charged', () {
    expect(playFailureMessage('BillingResponse.userCanceled'), 'Purchase cancelled. Nothing was charged.');
  });

  test('an unknown Play failure never shows a raw enum', () {
    expect(playFailureMessage('something odd'), isNot(contains('BillingResponse')));
    expect(playFailureMessage(null), isNot(contains('null')));
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
