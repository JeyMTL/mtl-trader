import 'package:flutter_test/flutter_test.dart';

import 'package:mtl_trader_mobile/core/pnl.dart';

/// The strip under the trade form reads these three numbers on every keystroke,
/// so they are tested without a widget: an Entry 1.1000 / stop 1.0950 / target
/// 1.1150 long is 1:3 whether the lot size is 0.1 or 10.
void main() {
  group('riskRewardPreview', () {
    test('reads risk and reward from the levels, and the ratio between them',
        () {
      final preview = riskRewardPreview(
        type: 'BUY',
        symbol: 'EURUSD',
        entry: 1.1000,
        stop: 1.0950,
        take: 1.1150,
        lots: 0.1,
      );

      // 50 pips on 0.1 lots of EURUSD is $50; 150 pips is $150.
      expect(preview.risk, closeTo(50, 0.01));
      expect(preview.reward, closeTo(150, 0.01));
      expect(preview.r, closeTo(3.0, 0.001));
    });

    test('a sell takes its risk from above the entry', () {
      final preview = riskRewardPreview(
        type: 'SELL',
        symbol: 'EURUSD',
        entry: 1.1000,
        stop: 1.1050,
        take: 1.0900,
        lots: 0.1,
      );

      expect(preview.risk, closeTo(50, 0.01));
      expect(preview.reward, closeTo(100, 0.01));
      expect(preview.r, closeTo(2.0, 0.001));
    });

    test('a level on the wrong side is neither risk nor reward', () {
      // A buy with its stop above the entry: the form refuses this at save, and
      // the preview must not dress the typo up as a profit.
      final preview = riskRewardPreview(
        type: 'BUY',
        symbol: 'EURUSD',
        entry: 1.1000,
        stop: 1.1050,
        take: 1.1200,
        lots: 0.1,
      );

      expect(preview.risk, 0);
      expect(preview.reward, closeTo(200, 0.01));
      expect(preview.r, isNull);
    });

    test('a trade with only a stop has risk and no ratio', () {
      final preview = riskRewardPreview(
        type: 'BUY',
        symbol: 'XAUUSD',
        entry: 3600,
        stop: 3595,
        take: null,
        lots: 1,
      );

      expect(preview.risk, greaterThan(0));
      expect(preview.reward, 0);
      expect(preview.r, isNull);
    });
    test('flags the side each level was entered on, so the form can say why', () {
      final wrongStop = riskRewardPreview(
        type: 'BUY',
        symbol: 'EURUSD',
        entry: 1.1000,
        stop: 1.1050,
        take: 1.1200,
        lots: 0.1,
      );
      expect(wrongStop.stopWrongSide, isTrue);
      expect(wrongStop.takeWrongSide, isFalse);

      final wrongTake = riskRewardPreview(
        type: 'SELL',
        symbol: 'EURUSD',
        entry: 1.1000,
        stop: 1.1050,
        take: 1.1100,
        lots: 0.1,
      );
      expect(wrongTake.stopWrongSide, isFalse);
      expect(wrongTake.takeWrongSide, isTrue);

      final right = riskRewardPreview(
        type: 'BUY',
        symbol: 'EURUSD',
        entry: 1.1000,
        stop: 1.0950,
        take: 1.1150,
        lots: 0.1,
      );
      expect(right.stopWrongSide, isFalse);
      expect(right.takeWrongSide, isFalse);
    });

    test('a level exactly on the entry counts as the wrong side', () {
      final preview = riskRewardPreview(
        type: 'BUY',
        symbol: 'EURUSD',
        entry: 1.1000,
        stop: 1.1000,
        take: 1.1150,
        lots: 0.1,
      );

      expect(preview.risk, 0);
      expect(preview.stopWrongSide, isTrue);
    });
  });
}
