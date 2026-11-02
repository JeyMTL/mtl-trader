/// Prop-firm evaluation rules and the standing against them.
///
/// Mirrors `src/lib/prop-rules.ts` on the web. The numbers are checked again by
/// the server, so this validation exists to fail fast in the form, not to be the
/// gate: a client-side check is a courtesy, not a security boundary.
class PropRules {
  const PropRules({
    required this.accountSize,
    required this.maxDailyLossPct,
    required this.maxDrawdownPct,
    required this.trailingDrawdown,
    required this.profitTargetPct,
    required this.minTradingDays,
    required this.startedOn,
  });

  final double accountSize;
  final double maxDailyLossPct;
  final double maxDrawdownPct;
  final bool trailingDrawdown;
  final double profitTargetPct;
  final int minTradingDays;

  /// `YYYY-MM-DD`.
  final String startedOn;

  static String isoToday() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  static PropRules defaults() => PropRules(
        accountSize: 10000,
        maxDailyLossPct: 5,
        maxDrawdownPct: 10,
        trailingDrawdown: true,
        profitTargetPct: 10,
        minTradingDays: 5,
        startedOn: isoToday(),
      );

  factory PropRules.fromMap(Map<String, dynamic> map) => PropRules(
        accountSize: _double(map['account_size'], 10000),
        maxDailyLossPct: _double(map['max_daily_loss_pct'], 5),
        maxDrawdownPct: _double(map['max_drawdown_pct'], 10),
        trailingDrawdown: map['trailing_drawdown'] != false,
        profitTargetPct: _double(map['profit_target_pct'], 10),
        minTradingDays: _int(map['min_trading_days'], 5),
        startedOn: map['started_on']?.toString() ?? isoToday(),
      );

  Map<String, dynamic> toBody() => <String, dynamic>{
        'account_size': accountSize,
        'max_daily_loss_pct': maxDailyLossPct,
        'max_drawdown_pct': maxDrawdownPct,
        'trailing_drawdown': trailingDrawdown,
        'profit_target_pct': profitTargetPct,
        'min_trading_days': minTradingDays,
        'started_on': startedOn,
      };

  /// The same bounds the server enforces, phrased for the person typing.
  String? validate() {
    if (accountSize < 1) return 'Account size must be at least 1.';
    if (maxDailyLossPct <= 0 || maxDailyLossPct > 50) {
      return 'Daily loss limit must be between 0 and 50%.';
    }
    if (maxDrawdownPct <= 0 || maxDrawdownPct > 100) {
      return 'Drawdown limit must be between 0 and 100%.';
    }
    if (profitTargetPct < 0 || profitTargetPct > 200) {
      return 'Profit target must be between 0 and 200%.';
    }
    if (minTradingDays < 0 || minTradingDays > 60) {
      return 'Minimum trading days must be between 0 and 60.';
    }
    return null;
  }

  PropRules copyWith({
    double? accountSize,
    double? maxDailyLossPct,
    double? maxDrawdownPct,
    bool? trailingDrawdown,
    double? profitTargetPct,
    int? minTradingDays,
    String? startedOn,
  }) =>
      PropRules(
        accountSize: accountSize ?? this.accountSize,
        maxDailyLossPct: maxDailyLossPct ?? this.maxDailyLossPct,
        maxDrawdownPct: maxDrawdownPct ?? this.maxDrawdownPct,
        trailingDrawdown: trailingDrawdown ?? this.trailingDrawdown,
        profitTargetPct: profitTargetPct ?? this.profitTargetPct,
        minTradingDays: minTradingDays ?? this.minTradingDays,
        startedOn: startedOn ?? this.startedOn,
      );
}

enum PropLevel { ok, warning, breach }

class PropStatus {
  const PropStatus({
    required this.accountSize,
    required this.equity,
    required this.peakEquity,
    required this.dailyPnl,
    required this.dailyLossLimit,
    required this.dailyHeadroom,
    required this.drawdown,
    required this.drawdownLimit,
    required this.drawdownHeadroom,
    required this.profitTarget,
    required this.profitProgress,
    required this.tradingDays,
    required this.minTradingDays,
    required this.trailingDrawdown,
    required this.maxDailyLossPct,
    required this.status,
  });

  final double accountSize;
  final double equity;
  final double peakEquity;
  final double dailyPnl;
  final double dailyLossLimit;
  final double dailyHeadroom;
  final double drawdown;
  final double drawdownLimit;
  final double drawdownHeadroom;
  final double profitTarget;
  final double profitProgress;
  final int tradingDays;
  final int minTradingDays;
  final bool trailingDrawdown;
  final double maxDailyLossPct;

  /// `ok`, `warn_daily`, `warn_drawdown`, `breach_daily`, `breach_drawdown`.
  final String status;

  PropLevel get level {
    if (status == 'breach_daily' || status == 'breach_drawdown') {
      return PropLevel.breach;
    }
    if (status == 'warn_daily' || status == 'warn_drawdown') {
      return PropLevel.warning;
    }
    return PropLevel.ok;
  }

  factory PropStatus.fromMap(Map<String, dynamic> map) => PropStatus(
        accountSize: _double(map['account_size']),
        equity: _double(map['equity']),
        peakEquity: _double(map['peak_equity']),
        dailyPnl: _double(map['daily_pnl']),
        dailyLossLimit: _double(map['daily_loss_limit']),
        dailyHeadroom: _double(map['daily_headroom']),
        drawdown: _double(map['drawdown']),
        drawdownLimit: _double(map['drawdown_limit']),
        drawdownHeadroom: _double(map['drawdown_headroom']),
        profitTarget: _double(map['profit_target']),
        profitProgress: _double(map['profit_progress']),
        tradingDays: _int(map['trading_days']),
        minTradingDays: _int(map['min_trading_days']),
        trailingDrawdown: map['trailing_drawdown'] != false,
        maxDailyLossPct: _double(map['max_daily_loss_pct'], 5),
        status: map['status']?.toString() ?? 'ok',
      );
}

double _double(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

int _int(dynamic value, [int fallback = 0]) {
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}
