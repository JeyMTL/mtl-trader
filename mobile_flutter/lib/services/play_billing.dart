import 'package:in_app_purchase/in_app_purchase.dart';

/// A subscription sold through Google Play.
///
/// The product id must match the subscription created in the Play Console
/// exactly. Play only returns the products it will actually sell to this device
/// — existing, active and priced for the buyer's country — so a typo shows up as
/// a permanently disabled button rather than as a purchase that fails after the
/// customer has decided to pay.
class PlayCatalogEntry {
  const PlayCatalogEntry(this.planId, this.interval);

  /// Mirrors the plan ids in `plans.dart` and `src/lib/plans.ts`.
  final String planId;

  /// `month` or `year`. Play sells each cadence as its own base plan.
  final String interval;
}

const Map<String, PlayCatalogEntry> playCatalog = {
  'basic_month': PlayCatalogEntry('basic', 'month'),
  'basic_year': PlayCatalogEntry('basic', 'year'),
  'pro_month': PlayCatalogEntry('pro', 'month'),
  'pro_year': PlayCatalogEntry('pro', 'year'),
};

/// The id Play knows a plan and cadence by. Used to look the product up in the
/// catalogue loaded from the store.
String playProductIdFor(String planId, String interval) =>
    '${planId}_$interval';

/// Whether a plan card's Play button may start a purchase.
///
/// A plan already owned cannot be bought again at the same cadence; switching a
/// monthly subscriber to the yearly base plan is allowed and stacks the days.
/// Without a sellable product (Play unavailable, or the plan not on sale in this
/// country) there is nothing to buy, so the button stays disabled.
bool canBuyWithPlay({
  required bool current,
  required bool yearly,
  required bool enabled,
  required bool hasProduct,
}) =>
    hasProduct && enabled && (!current || yearly);

/// A sentence a trader can act on for a Play failure.
///
/// Play hands back the enum name (`BillingResponse.developerError`) in
/// `IAPError.message`, which tells a customer nothing and says nothing about
/// who has to fix it. `developerError` is the one that bites a release: Play
/// will not sell from a build it did not sign and upload, or to a Play account
/// that is not on the licence-testing list — so the advice points at the store
/// install rather than at the customer's card.
String playFailureMessage(String? raw, {String fallback = 'Google Play could not complete the purchase. Nothing was charged.'}) {
  final text = (raw ?? '').toLowerCase();
  if (text.contains('developererror')) {
    return 'Google Play refused this version of the app. Install it from the '
        'Play Store and try again — a build installed from a file cannot buy a '
        'subscription.';
  }
  if (text.contains('itemalreadyowned')) {
    return 'That plan is already on this Google account. Use Restore purchases '
        'to bring it onto this profile.';
  }
  if (text.contains('itemunavailable') || text.contains('itemnotowned')) {
    return 'Google Play could not find that plan for this account. Try again in '
        'a moment, or check the plan is on sale in your country.';
  }
  if (text.contains('service') || text.contains('network') || text.contains('disconnected')) {
    return 'Could not reach Google Play. Check your connection and try again.';
  }
  if (text.contains('usercanceled')) return 'Purchase cancelled. Nothing was charged.';
  return fallback;
}

/// Thin wrapper over Play Billing.
///
/// It deliberately holds no billing state of its own: what the trader owns is
/// decided by the server after it asks Google, and the screen reads that back
/// from the account. This class only moves the user through Play's sheet.
class PlayBilling {
  PlayBilling({InAppPurchase? store})
      : _store = store ?? InAppPurchase.instance;

  final InAppPurchase _store;

  /// Loads the sellable products, keyed by product id. An empty map means Play
  /// is unavailable (an emulator without Play Services, or a sideloaded build
  /// with no Play account), and the plan buttons stay disabled.
  Future<Map<String, ProductDetails>> load() async {
    if (!await _store.isAvailable()) return const {};
    final response = await _store.queryProductDetails(playCatalog.keys.toSet());
    return {
      for (final product in response.productDetails) product.id: product,
    };
  }

  /// Every purchase Play reports, including those started before the app was
  /// last closed. Each one must be finished, or Play keeps re-delivering it.
  Stream<List<PurchaseDetails>> get purchases => _store.purchaseStream;

  /// Opens Play's purchase sheet. A subscription is not consumable: it is owned
  /// until it lapses, so it is bought — not consumed — and restored, not
  /// re-purchased, on a new device.
  Future<bool> buy(ProductDetails product) => _store.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );

  /// Re-delivers subscriptions bought with this Google account, which is how a
  /// reinstall or a new phone recovers a plan without paying twice.
  Future<void> restore() => _store.restorePurchases();

  /// Marks the purchase handled locally. The acknowledgement that stops Google
  /// refunding it after three days is made by the server, not here.
  Future<void> finish(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      await _store.completePurchase(purchase);
    }
  }
}
