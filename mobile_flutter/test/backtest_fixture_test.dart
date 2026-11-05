import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/backtest.dart';

/// The fixture is shared with `src/lib/__tests__/backtest-fixture.test.ts`, so
/// a report field cannot be added on one platform without the other noticing.
void main() {
  final raw =
      jsonDecode(File('../fixtures/backtest/report.json').readAsStringSync())
          as Map<String, dynamic>;

  test('the phone can read the shared report', () {
    final report = BacktestReport.fromJson(raw);

    expect(report.symbol, raw['symbol']);
    expect(report.timeframe, raw['timeframe']);
    expect(report.strategyId, (raw['strategy'] as Map)['id']);
    expect(report.barCount, raw['barCount']);
    expect(report.metrics.trades, raw['metrics']['trades']);
    expect(report.metrics.netPnl, raw['metrics']['netPnl']);
    expect(report.trades.length, (raw['trades'] as List).length);
    expect(report.trades.first.exitReason, 'target');
    expect(report.equity.length, (raw['equityCurve'] as List).length);
    expect(report.assumptions.length, (raw['assumptions'] as List).length);
    expect(report.warnings.length, (raw['warnings'] as List).length);
    expect(report.split, isNotNull);
    expect(
      report.split!.outOfSample.trades,
      (raw['split'] as Map)['outOfSample']['trades'],
    );
  });

  test('every top-level field is parsed or deliberately ignored', () {
    const parsed = {
      'symbol',
      'timeframe',
      'strategy',
      'barCount',
      'from',
      'to',
      'metrics',
      'split',
      'trades',
      'equityCurve',
      'assumptions',
      'warnings',
    };
    // The phone renders neither of these yet; the schema test owns their shape.
    // A new field lands here only when someone decides what the phone does with
    // it — that decision is the point of this test.
    const ignored = {'config', 'benchmark', 'stress'};

    expect(raw.keys.toSet(), parsed.union(ignored));
  });
}
