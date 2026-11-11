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
