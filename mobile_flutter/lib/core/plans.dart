/// Paid plans offered in the app. Prices and limits mirror `src/lib/plans.ts`
/// on the web so checkout, the database trigger and the app agree.
///
/// Enforced differences: the monthly trade allowance (`enforce_trade_quota` in
/// Postgres), the AI review allowance, and the backtester/replay gate. Autosync
/// is included from Basic. Keep these lines in step by hand with the web lists in
/// `src/lib/plans.ts`.
class MobilePlan {
  const MobilePlan({
    required this.id,
    required this.name,
    required this.price,
    this.annualPrice,
    required this.maxTrades,
    required this.features,
    this.popular = false,
  });

  final String id;
  final String name;
  final double price;

  /// A year bought up front: ten months' worth, so two months free. Not
  /// `price * 12` on purpose — the discount is the point of paying a year early.
  final double? annualPrice;

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
    price: 12.00,
    annualPrice: 120.00,
    maxTrades: 50,
    popular: true,
    features: [
      '50 trades per month',
      'Equity curve, daily and monthly P&L',
      'Time edge: best hours and sessions',
      'OANDA chart with studies',
      'Journal photos and voice notes',
      'MT5 broker sync',
      '30 AI reviews a month',
    ],
  ),
  MobilePlan(
    id: 'pro',
    name: 'Pro',
    price: 29.00,
    annualPrice: 290.00,
    maxTrades: -1,
    features: [
      'Unlimited trades',
      'Everything in Basic',
      'AI journal review (200 a month)',
      'Backtester with saved runs',
      'Market replay with saved drawings',
      'API access and sync token',
    ],
  ),
];
