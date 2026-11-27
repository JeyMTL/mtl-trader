import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/pnl.dart';

void main() {
  test('computes EURUSD P&L with contract size', () {
    final pnl = calculatePnl(
      type: 'BUY',
      symbol: 'EURUSD',
      entry: 1.1000,
      exit: 1.1050,
      lots: 1,
    );
    expect(pnl, closeTo(500, 0.0001));
  });

  test('computes sell P&L', () {
    final pnl = calculatePnl(
      type: 'SELL',
      symbol: 'EURUSD',
      entry: 1.1050,
      exit: 1.1000,
      lots: 0.5,
    );
    expect(pnl, closeTo(250, 0.0001));
  });

  test('adds signed commission and swap', () {
    final pnl = calculatePnl(
      type: 'BUY',
      symbol: 'EURUSD',
      entry: 1.1000,
      exit: 1.1050,
      lots: 1,
      commission: -2.5,
      swap: -0.75,
    );
    expect(pnl, closeTo(496.75, 0.0001));
  });

  test('uses the gold contract size', () {
    final pnl = calculatePnl(
      type: 'BUY',
      symbol: 'XAUUSD',
      entry: 2400,
      exit: 2410,
      lots: 0.5,
    );
    expect(pnl, closeTo(500, 0.0001));
  });

  test('uses the JPY contract size', () {
    final pnl = calculatePnl(
      type: 'BUY',
      symbol: 'USDJPY',
      entry: 150.00,
      exit: 150.10,
      lots: 1,
    );
    expect(pnl, closeTo(100, 0.0001));
  });

  test('sizes a pip for metal, index and crypto symbols', () {
    expect(pipSize('EURUSD'), 0.0001);
    expect(pipSize('GBPUSD'), 0.0001);
    expect(pipSize('USDJPY'), 0.01);
    expect(pipSize('XAUUSD'), 0.1);
    // Silver trades near 30.000, so a pip is a cent: 0.50 is fifty pips, not
    // five, and grouping it with gold was the bug.
    expect(pipSize('XAGUSD'), 0.01);
    expect(pipSize('US30'), 1);
    expect(pipSize('BTCUSD'), 1);
  });
}
