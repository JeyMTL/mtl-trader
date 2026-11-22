/// Paid plans offered in the app. Prices and limits mirror `src/lib/plans.ts`
/// on the web so checkout, the database trigger and the app agree.
///
/// Enforced differences: the AI review allowance and the backtester/replay gate.
/// Trade volume is unlimited on every plan in force — capping Basic below the
/// unlimited trial made paying worse than not paying. MT5 sync is sold on Basic
/// now that the desktop EA carries it (`kMt5SyncEnabled`), and every line here
/// describes something the plan can actually open: listing a feature a tier
/// cannot reach is the one mistake the web catalogue guard cannot catch.
///
/// The split is value-ordered: Basic is the whole journalling and chart desk
/// (including the levels shared with the web), Pro is the advanced analysis
/// workflow — backtester, replay, the large review allowance and API access.
/// Keep these lines in step by hand with the web lists in `src/lib/plans.ts`.
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
    maxTrades: -1,
    popular: true,
    features: [
      'Unlimited trades',
      'Dashboard, journal and calendar',
      'Equity curve, daily and monthly P&L',
      'Session, symbol, tag and setup analytics',
      'Time edge: best hours and sessions',
      'Chart desk with studies and pinned levels',
      'Levels shared between phone and web',
      'MT5 automatic sync from your terminal',
      'Prop-firm rules and the daily stop',
      'Journal photos and voice notes',
      '30 AI reviews a month',
      'CSV import/export and email summaries',
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
      'Market replay through a session',
      'API access and a sync token',
      'Priority support',
    ],
  ),
];
