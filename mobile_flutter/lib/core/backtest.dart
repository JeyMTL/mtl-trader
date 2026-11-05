/// Backtest data model and the strategy catalogue.
///
/// Mirrors `src/lib/backtest/types.ts` and `src/lib/backtest/strategies.ts`. The
/// simulation itself runs on the server (`POST /api/backtest`), so the app never
/// computes a result it could also forge — it describes the rules and renders the
/// report that comes back. A saved run can be reopened from its stored row.
library;

/// One tunable rule parameter, exactly as the web workbench declares it.
class BacktestParamSpec {
  const BacktestParamSpec({
    required this.key,
    required this.label,
    required this.min,
    required this.max,
    required this.step,
    required this.defaultValue,
    this.integer = false,
  });

  final String key;
  final String label;
  final double min;
  final double max;
  final double step;
  final double defaultValue;
  final bool integer;

  /// `20` rather than `20.0`, so a default fills the field the way a trader
  /// would type it.
  String get defaultText =>
      defaultValue == defaultValue.roundToDouble()
          ? defaultValue.toInt().toString()
          : defaultValue.toString();
}

class BacktestStrategy {
  const BacktestStrategy({
    required this.id,
    required this.name,
    required this.description,
    required this.params,
  });

  final String id;
  final String name;
  final String description;
  final List<BacktestParamSpec> params;

  Map<String, double> get defaults => {
        for (final spec in params) spec.key: spec.defaultValue,
      };
}

const List<BacktestParamSpec> _atrStopParams = [
  BacktestParamSpec(
    key: 'atrPeriod',
    label: 'ATR period',
    min: 2,
    max: 100,
    step: 1,
    defaultValue: 14,
    integer: true,
  ),
  BacktestParamSpec(
    key: 'stopAtr',
    label: 'Stop (× ATR)',
    min: 0.2,
    max: 10,
    step: 0.1,
    defaultValue: 2,
  ),
  BacktestParamSpec(
    key: 'targetAtr',
    label: 'Target (× ATR)',
    min: 0.2,
    max: 20,
    step: 0.1,
    defaultValue: 4,
  ),
];

/// Same three rules, ids, names, descriptions and defaults as the web desk.
const List<BacktestStrategy> backtestStrategies = [
  BacktestStrategy(
    id: 'sma_cross',
    name: 'SMA cross',
    description:
        'Long when the fast average crosses above the slow one, short on the '
        'opposite cross. Stop and target are ATR multiples of the signal bar '
        'close.',
    params: [
      BacktestParamSpec(
        key: 'fast',
        label: 'Fast SMA',
        min: 2,
        max: 100,
        step: 1,
        defaultValue: 20,
        integer: true,
      ),
      BacktestParamSpec(
        key: 'slow',
        label: 'Slow SMA',
        min: 3,
        max: 300,
        step: 1,
        defaultValue: 50,
        integer: true,
      ),
      ..._atrStopParams,
    ],
  ),
  BacktestStrategy(
    id: 'donchian_breakout',
    name: 'Donchian breakout',
    description:
        'Long on a close above the highest high of the lookback window, short '
        'on a close below the lowest low. ATR stop and target.',
    params: [
      BacktestParamSpec(
        key: 'lookback',
        label: 'Lookback bars',
        min: 5,
        max: 500,
        step: 1,
        defaultValue: 55,
        integer: true,
      ),
      ..._atrStopParams,
    ],
  ),
  BacktestStrategy(
    id: 'rsi_reversion',
    name: 'RSI reversion',
    description:
        'Long when RSI recovers back above the oversold line, short when it '
        'falls back below the overbought line — a mean-reversion entry, not a '
        'trend one.',
    params: [
      BacktestParamSpec(
        key: 'period',
        label: 'RSI period',
        min: 2,
        max: 100,
        step: 1,
        defaultValue: 14,
        integer: true,
      ),
      BacktestParamSpec(
        key: 'oversold',
        label: 'Oversold',
        min: 1,
        max: 49,
        step: 1,
        defaultValue: 30,
        integer: true,
      ),
      BacktestParamSpec(
        key: 'overbought',
        label: 'Overbought',
        min: 51,
        max: 99,
        step: 1,
        defaultValue: 70,
        integer: true,
      ),
      ..._atrStopParams,
    ],
  ),
];

BacktestStrategy? backtestStrategyById(String id) {
  for (final strategy in backtestStrategies) {
    if (strategy.id == id) return strategy;
  }
  return null;
}

/// Report metrics, keyed exactly as `src/lib/backtest/metrics.ts` writes them.
class BacktestMetrics {
  const BacktestMetrics({
    required this.netPnl,
    required this.returnPct,
    required this.profitFactor,
    required this.winRate,
    required this.trades,
    required this.expectancy,
    required this.maxDrawdownPct,
    required this.sharpe,
    required this.exposurePct,
    required this.avgRMultiple,
  });

  final double netPnl;
  final double returnPct;

  /// Null when there are no losing trades (the web prints ∞).
  final double? profitFactor;
  final double winRate;
  final int trades;
  final double expectancy;
  final double maxDrawdownPct;

  /// Null when the sample is too short to annualise.
  final double? sharpe;
  final double exposurePct;

  /// Null when no trade carried a stop.
  final double? avgRMultiple;

  static const BacktestMetrics empty = BacktestMetrics(
    netPnl: 0,
    returnPct: 0,
    profitFactor: null,
    winRate: 0,
    trades: 0,
    expectancy: 0,
    maxDrawdownPct: 0,
    sharpe: null,
    exposurePct: 0,
    avgRMultiple: null,
  );

  factory BacktestMetrics.fromMap(Map<String, dynamic> map) {
    return BacktestMetrics(
      netPnl: _double(map['netPnl']),
      returnPct: _double(map['returnPct']),
      profitFactor: _nullableDouble(map['profitFactor']),
      winRate: _double(map['winRate']),
      trades: _int(map['trades']),
      expectancy: _double(map['expectancy']),
      maxDrawdownPct: _double(map['maxDrawdownPct']),
      sharpe: _nullableDouble(map['sharpe']),
      exposurePct: _double(map['exposurePct']),
      avgRMultiple: _nullableDouble(map['avgRMultiple']),
    );
  }
}

class BacktestTrade {
  const BacktestTrade({
    required this.side,
    required this.entryTime,
    required this.exitTime,
    required this.entryPrice,
    required this.exitPrice,
    required this.stopPrice,
    required this.takeProfitPrice,
    required this.lots,
    required this.grossPnl,
    required this.costs,
    required this.pnl,
    required this.riskAmount,
    required this.rMultiple,
    required this.barsHeld,
    required this.exitReason,
  });

  /// `long` or `short`.
  final String side;
  final DateTime? entryTime;
  final DateTime? exitTime;
  final double entryPrice;
  final double exitPrice;
  final double stopPrice;
  final double takeProfitPrice;
  final double lots;
  final double grossPnl;
  final double costs;
  final double pnl;
  final double riskAmount;
  final double rMultiple;
  final int barsHeld;

  /// `stop`, `target`, `signal` or `end`.
  final String exitReason;

  bool get isLong => side == 'long';

  factory BacktestTrade.fromMap(Map<String, dynamic> map) {
    return BacktestTrade(
      side: _text(map['side']).toLowerCase(),
      entryTime: _time(map['entryTime']),
      exitTime: _time(map['exitTime']),
      entryPrice: _double(map['entryPrice']),
      exitPrice: _double(map['exitPrice']),
      stopPrice: _double(map['stopPrice']),
      takeProfitPrice: _double(map['takeProfitPrice']),
      lots: _double(map['lots']),
      grossPnl: _double(map['grossPnl']),
      costs: _double(map['costs']),
      pnl: _double(map['pnl']),
      riskAmount: _double(map['riskAmount']),
      rMultiple: _double(map['rMultiple']),
      barsHeld: _int(map['barsHeld']),
      exitReason: _text(map['exitReason']),
    );
  }
}

class BacktestEquityPoint {
  const BacktestEquityPoint({
    required this.time,
    required this.equity,
    required this.balance,
  });

  final DateTime? time;
  final double equity;
  final double balance;

  factory BacktestEquityPoint.fromMap(Map<String, dynamic> map) {
    return BacktestEquityPoint(
      time: _time(map['time']),
      equity: _double(map['equity']),
      balance: _double(map['balance']),
    );
  }
}

/// The in-sample / out-of-sample pair, or null when the range is too short.
class BacktestSplit {
  const BacktestSplit({
    required this.ratio,
    required this.inSample,
    required this.outOfSample,
  });

  final double ratio;
  final BacktestMetrics inSample;
  final BacktestMetrics outOfSample;

  factory BacktestSplit.fromMap(Map<String, dynamic> map) {
    return BacktestSplit(
      ratio: _double(map['ratio']),
      inSample: BacktestMetrics.fromMap(_map(map['inSample'])),
      outOfSample: BacktestMetrics.fromMap(_map(map['outOfSample'])),
    );
  }
}

/// A complete run, from a fresh `POST` or a saved row.
class BacktestReport {
  const BacktestReport({
    required this.symbol,
    required this.timeframe,
    required this.strategyId,
    required this.strategyName,
    required this.params,
    required this.barCount,
    required this.from,
    required this.to,
    required this.metrics,
    required this.split,
    required this.trades,
    required this.equity,
    required this.assumptions,
    required this.warnings,
  });

  final String symbol;
  final String timeframe;
  final String strategyId;
  final String strategyName;
  final Map<String, double> params;
  final int barCount;
  final DateTime? from;
  final DateTime? to;
  final BacktestMetrics metrics;
  final BacktestSplit? split;
  final List<BacktestTrade> trades;
  final List<BacktestEquityPoint> equity;
  final List<String> assumptions;
  final List<String> warnings;

  /// The `report` object a `POST /api/backtest` returns.
  factory BacktestReport.fromJson(Map<String, dynamic> map) {
    final strategy = _map(map['strategy']);
    return BacktestReport(
      symbol: _text(map['symbol']),
      timeframe: _text(map['timeframe']),
      strategyId: _text(strategy['id']),
      strategyName: _text(strategy['name']),
      params: _params(strategy['params']),
      barCount: _int(map['barCount']),
      from: _time(map['from']),
      to: _time(map['to']),
      metrics: BacktestMetrics.fromMap(_map(map['metrics'])),
      split: map['split'] == null ? null : BacktestSplit.fromMap(_map(map['split'])),
      trades: _list(map['trades'])
          .map((row) => BacktestTrade.fromMap(_map(row)))
          .toList(),
      equity: _list(map['equityCurve'])
          .map((row) => BacktestEquityPoint.fromMap(_map(row)))
          .toList(),
      assumptions: _strings(map['assumptions']),
      warnings: _strings(map['warnings']),
    );
  }

  /// A stored `backtests` row from `GET /api/backtest?id=`.
  ///
  /// The row carries the strategy id, not its display name, so the id stands in
  /// for the name — the same thing the web report view does.
  factory BacktestReport.fromSaved(Map<String, dynamic> row) {
    return BacktestReport(
      symbol: _text(row['symbol']),
      timeframe: _text(row['timeframe']),
      strategyId: _text(row['strategy_id']),
      strategyName: _text(row['strategy_id']),
      params: _params(row['strategy_params']),
      barCount: _int(row['bar_count']),
      from: _time(row['period_start']),
      to: _time(row['period_end']),
      metrics: BacktestMetrics.fromMap(_map(row['metrics'])),
      split: row['split_metrics'] == null
          ? null
          : BacktestSplit.fromMap(_map(row['split_metrics'])),
      trades: _list(row['trades'])
          .map((entry) => BacktestTrade.fromMap(_map(entry)))
          .toList(),
      equity: _list(row['equity_curve'])
          .map((point) => BacktestEquityPoint.fromMap(_map(point)))
          .toList(),
      assumptions: _strings(row['assumptions']),
      warnings: _strings(row['warnings']),
    );
  }
}

/// One entry in the saved-runs list (`GET /api/backtest`).
class SavedBacktestRun {
  const SavedBacktestRun({
    required this.id,
    required this.name,
    required this.symbol,
    required this.timeframe,
    required this.strategyId,
    required this.metrics,
    required this.barCount,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String symbol;
  final String timeframe;
  final String strategyId;
  final BacktestMetrics metrics;
  final int barCount;
  final DateTime? createdAt;

  factory SavedBacktestRun.fromMap(Map<String, dynamic> map) {
    return SavedBacktestRun(
      id: _text(map['id']),
      name: _text(map['name']),
      symbol: _text(map['symbol']),
      timeframe: _text(map['timeframe']),
      strategyId: _text(map['strategy_id']),
      metrics: BacktestMetrics.fromMap(_map(map['metrics'])),
      barCount: _int(map['bar_count']),
      createdAt: _time(map['created_at']),
    );
  }
}

/// A finished run: the report, plus whether the server managed to archive it.
class BacktestRunResult {
  const BacktestRunResult({
    required this.report,
    required this.saved,
    this.id,
  });

  final BacktestReport report;
  final bool saved;
  final String? id;
}

// --------------------------------------------------------------------- parse

Map<String, dynamic> _map(dynamic value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};

List<dynamic> _list(dynamic value) => value is List ? value : const [];

String _text(dynamic value) => value?.toString().trim() ?? '';

double _double(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double? _nullableDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int _int(dynamic value) {
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

/// Epoch milliseconds in a live report, an ISO string in a saved row.
DateTime? _time(dynamic value) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.round(), isUtc: true);
  }
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toUtc();
}

Map<String, double> _params(dynamic value) {
  final result = <String, double>{};
  if (value is Map) {
    for (final entry in value.entries) {
      final parsed = _nullableDouble(entry.value);
      if (parsed != null) result[entry.key.toString()] = parsed;
    }
  }
  return result;
}

List<String> _strings(dynamic value) => _list(value)
    .map((entry) => entry?.toString() ?? '')
    .where((entry) => entry.trim().isNotEmpty)
    .toList();
