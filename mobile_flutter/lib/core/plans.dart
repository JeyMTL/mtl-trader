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
/// workflow — backtester, replay and the large review allowance.
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
      'Unlimited trades and unlimited history',
      'Journal with photos, voice notes, tags, setups and mistakes',
      'Dashboard: equity curve, P&L calendar, daily and monthly results',
      'Session, symbol, tag and setup analytics, plus your time edge',
      'Chart desk on phone and web, from seconds to daily candles',
      'VWAP, session high/low levels and drawing tools',
      'Pin entry, stop and target levels straight off the live chart',
      'Price alert lines on the chart, with push alerts in the Android app',
      'The Android app in 30+ languages, on the same account as the web',
      'Drawings, layouts and templates that sync across phone and web',
      'The same journal on phone and web for one email',
      'Compare a second instrument on the web chart',
      'MT5 auto sync, from the hosted agent or your own terminal with a sync token',
      'XML, CSV and XLSX import',
      'Playbook, prop-firm rules and the daily-stop lock',
      'CSV and full account export',
      '15 AI journal summaries a month, written from your own logged trades',
    ],
  ),
  MobilePlan(
    id: 'pro',
    name: 'Pro',
    price: 29.00,
    annualPrice: 290.00,
    maxTrades: -1,
    features: [
      'Everything in Basic',
      'Backtester with saved runs, simulating past sessions only',
      'Write your own entry and exit rules, then test them on past sessions',
      'Market replay that steps candle by candle through a session',
      '40 AI journal summaries a month, written from your own logged trades',
      'Priority support',
    ],
  ),
];
