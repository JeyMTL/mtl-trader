/// Paid plans offered in the app. Prices and limits mirror `src/lib/plans.ts`
/// on the web so checkout, the database trigger and the app agree.
///
/// Enforced differences: the hard lock, the AI review, the backtester gate and
/// push notifications. The licensed chart desk is off on both surfaces
/// (`MARKET_CHARTS_ENABLED` on the web, the same switch behind the phone's
/// market view), so no line here sells candles, drawings or replay. Trade volume is
/// unlimited on every plan in force — capping Basic below the unlimited trial
/// made paying worse than not paying. MT5 sync and the soft lock are sold on
/// Basic now that the desktop EA carries them (`kMt5SyncEnabled`), and every
/// line here describes something the plan can actually open: listing a feature a
/// tier cannot reach is the one mistake the web catalogue guard cannot catch.
///
/// The split is value-ordered: Basic is the whole journal (photos, voice notes,
/// time edge, setup matrix, dashboard and the market view), Pro is what goes
/// beyond journalling — the hard lock, the AI review and the analysis workbench.
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
      'MT5 auto sync from your own terminal with a sync token',
      'Daily stop with the soft lock: trading freezes, the journal stays open',
      'Time edge: the sessions and weekdays your results actually come from',
      "Setup matrix: each setup's win rate and expectancy by session and symbol",
      'Dashboard: equity curve, P&L calendar, daily and monthly results',
      'Live market view on every symbol and timeframe',
      'XML, CSV and XLSX import, plus CSV and full account export',
      'The Android app in 30+ languages, on the same account as the web',
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
      'Daily stop with the hard lock: trading freezes and the journal closes until the reset',
      '40 AI journal reviews a month, written from your own logged trades',
      'Backtester with saved runs, simulating past sessions only',
      'Write your own entry and exit rules, then test them on past sessions',
      'Notifications on your phone: prop-firm breaches and session reminders',
      'Priority support',
    ],
  ),
];
