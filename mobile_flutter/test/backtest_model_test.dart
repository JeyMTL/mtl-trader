import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/backtest.dart';

void main() {
  test('mirrors the web strategy catalogue', () {
    expect(
      backtestStrategies.map((strategy) => strategy.id).toList(),
      ['sma_cross', 'donchian_breakout', 'rsi_reversion'],
    );

    final sma = backtestStrategyById('sma_cross')!;
    expect(sma.name, 'SMA cross');
    expect(sma.defaults, {
      'fast': 20,
      'slow': 50,
      'atrPeriod': 14,
      'stopAtr': 2,
      'targetAtr': 4,
    });

    final rsi = backtestStrategyById('rsi_reversion')!;
    expect(rsi.params.map((spec) => spec.key), [
      'period',
      'oversold',
      'overbought',
      'atrPeriod',
      'stopAtr',
      'targetAtr',
    ]);
    expect(backtestStrategyById('nope'), isNull);
  });

  test('parses the report a run returns', () {
    final report = BacktestReport.fromJson({
      'symbol': 'EURUSD',
      'timeframe': 'M1',
      'strategy': {
        'id': 'sma_cross',
        'name': 'SMA cross',
        'params': {'fast': 20, 'slow': 50},
      },
      'barCount': 1200,
      'from': 1700000000000,
      'to': 1700100000000,
      'metrics': {
        'netPnl': 1234.5,
        'returnPct': 12.34,
        'profitFactor': null,
        'winRate': 55.5,
        'trades': 42,
        'expectancy': 29.4,
        'maxDrawdownPct': 4.2,
        'sharpe': null,
        'exposurePct': 30.0,
        'avgRMultiple': null,
      },
      'split': null,
      'trades': [
        {
          'side': 'long',
          'entryTime': 1700000000000,
          'exitTime': 1700000600000,
          'lots': 0.12,
          'pnl': 18.4,
          'exitReason': 'target',
        },
      ],
      'equityCurve': [
        {'time': 1700000000000, 'equity': 10000, 'balance': 10000},
        {'time': 1700000600000, 'equity': 10018.4, 'balance': 10018.4},
      ],
      'assumptions': ['Signals fill on the next open.'],
      'warnings': ['Only 1 trade.'],
    });

    expect(report.strategyId, 'sma_cross');
    expect(report.strategyName, 'SMA cross');
    expect(report.params['fast'], 20);
    expect(report.barCount, 1200);
    expect(report.metrics.netPnl, 1234.5);
    expect(report.metrics.trades, 42);
    expect(report.metrics.profitFactor, isNull);
    expect(report.metrics.sharpe, isNull);
    expect(report.split, isNull);
    expect(report.trades.single.isLong, isTrue);
    expect(report.trades.single.pnl, 18.4);
    expect(report.equity.length, 2);
    expect(report.equity.last.equity, 10018.4);
    expect(report.assumptions.single, contains('next open'));
    expect(report.warnings.single, contains('Only 1 trade'));
    expect(report.from?.millisecondsSinceEpoch, 1700000000000);
  });

  test('reopens a saved row, ISO periods and all', () {
    final report = BacktestReport.fromSaved({
      'symbol': 'EURUSD',
      'timeframe': 'M5',
      'strategy_id': 'rsi_reversion',
      'strategy_params': {'period': 14, 'oversold': 30},
      'bar_count': 500,
      'period_start': '2026-10-01T00:00:00+00:00',
      'period_end': '2026-10-02T00:00:00+00:00',
      'metrics': {'netPnl': -50, 'trades': 3},
      'split_metrics': {
        'ratio': 0.7,
        'inSample': {'netPnl': 10, 'trades': 2},
        'outOfSample': {'netPnl': -60, 'trades': 1},
      },
      'trades': null,
      'equity_curve': null,
      'assumptions': null,
      'warnings': null,
    });

    expect(report.strategyId, 'rsi_reversion');
    // The row carries no display name, so the id stands in for it.
    expect(report.strategyName, 'rsi_reversion');
    expect(report.params['oversold'], 30);
    expect(report.trades, isEmpty);
    expect(report.equity, isEmpty);
    expect(report.assumptions, isEmpty);
    expect(report.split?.ratio, 0.7);
    expect(report.split?.outOfSample.netPnl, -60);
    expect(report.from?.year, 2026);
  });

  test('parses a saved-run summary', () {
    final run = SavedBacktestRun.fromMap({
      'id': 'abc',
      'name': 'EURUSD M1 SMA cross',
      'symbol': 'EURUSD',
      'timeframe': 'M1',
      'strategy_id': 'sma_cross',
      'metrics': {'netPnl': 120.5, 'trades': 7},
      'bar_count': 900,
      'created_at': '2026-11-01T09:30:00+00:00',
    });

    expect(run.id, 'abc');
    expect(run.metrics.netPnl, 120.5);
    expect(run.metrics.trades, 7);
    expect(run.barCount, 900);
    expect(run.createdAt?.toUtc().hour, 9);
  });
}
