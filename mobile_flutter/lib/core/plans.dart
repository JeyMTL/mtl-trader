/// Paid plans offered in the app. Prices and limits mirror `src/lib/plans.ts`
/// on the web so checkout, the database trigger and the app agree.
class MobilePlan {
  const MobilePlan({
    required this.id,
    required this.name,
    required this.price,
    required this.maxTrades,
    required this.features,
    this.popular = false,
  });

  final String id;
  final String name;
  final double price;

  /// `-1` means unlimited.
  final int maxTrades;
  final List<String> features;
  final bool popular;

  String get allowance =>
      maxTrades < 0 ? 'Unlimited trades' : '$maxTrades trades / month';
}

const List<MobilePlan> mobilePlans = [
  MobilePlan(
    id: 'basic',
    name: 'Basic',
    price: 2.50,
    maxTrades: 50,
    popular: true,
    features: [
      '50 trades per month',
      'Advanced analytics',
      'Equity curve charts',
      'Strategy tagging',
    ],
  ),
  MobilePlan(
    id: 'pro',
    name: 'Pro',
    price: 5.00,
    maxTrades: -1,
    features: [
      'Unlimited trades',
      'Everything in Basic',
      'Advanced risk management',
      'Priority support',
    ],
  ),
];
