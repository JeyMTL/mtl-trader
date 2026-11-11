import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/chart_drawings.dart';
import 'package:mtl_trader_mobile/core/trade_exit.dart';
import 'package:mtl_trader_mobile/services/market_data.dart' show Candle;

/// One bar, [minute] minutes after the position's start.
Candle bar(int minute, double open, double high, double low, double close) =>
    Candle(
      time: DateTime.utc(2026, 11, 11, 12).add(Duration(minutes: minute)),
      open: open,
      high: high,
      low: low,
      close: close,
    );

ChartDrawing positionAt({
  required PositionSide side,
  required double entry,
  required double stop,
  required double target,
}) =>
    ChartDrawing.position(
      side: side,
      startMs: DateTime.utc(2026, 11, 11, 12).millisecondsSinceEpoch,
      entry: entry,
      stop: stop,
      target: target,
    );

ChartDrawing _short() => const ChartDrawing.position(
      side: PositionSide.short,
      startMs: 1794372000000,
      entry: 1.34500,
      stop: 1.34625,
      target: 1.34231,
    );

void main() {
  test('a position tool survives a save and reload', () {
    final decoded = decodeDrawings(encodeDrawings([_short()]));
    expect(decoded, hasLength(1));
    final drawing = decoded.single;
    expect(drawing.kind, DrawingKind.position);
    expect(drawing.side, PositionSide.short);
    expect(drawing.startMs, 1794372000000);
    expect(drawing.entry, closeTo(1.34500, 1e-9));
    expect(drawing.stop, closeTo(1.34625, 1e-9));
    expect(drawing.target, closeTo(1.34231, 1e-9));
  });

  test('older trend lines and rays still decode beside a position', () {
    final raw = encodeDrawings([
      const ChartDrawing.trend(
        startMs: 1,
        startPrice: 10,
        endMs: 2,
        endPrice: 12,
      ),
      const ChartDrawing.ray(price: 11),
      _short(),
    ]);
    final decoded = decodeDrawings(raw);
    expect(decoded.map((d) => d.kind), [
      DrawingKind.trend,
      DrawingKind.ray,
      DrawingKind.position,
    ]);
  });

  test('the reward ratio comes from the two legs, not the entry alone', () {
    final drawing = _short();
    expect(drawing.rewardRatio, closeTo(2.16, 0.01));
    // The legs are measured by distance, so a tighter stop raises the ratio.
    final tighter = drawing.copyWithLevel(PositionLevel.stop, 1.34400);
    expect(tighter.rewardRatio, closeTo(2.69, 0.01));
  });

  test('dragging one level leaves the other two where they were', () {
    final moved = _short().copyWithLevel(PositionLevel.entry, 1.34550);
    expect(moved.entry, closeTo(1.34550, 1e-9));
    expect(moved.stop, closeTo(1.34625, 1e-9));
    expect(moved.target, closeTo(1.34231, 1e-9));
    expect(moved.side, PositionSide.short);
  });

  test('dragging the box shifts every level and its anchor together', () {
    final moved =
        _short().shifted(priceDelta: -0.00020, startMs: 1794372600000);
    expect(moved.entry, closeTo(1.34480, 1e-9));
    expect(moved.stop, closeTo(1.34605, 1e-9));
    expect(moved.target, closeTo(1.34211, 1e-9));
    expect(moved.startMs, 1794372600000);
  });

  test('a corrupt position is dropped without losing its neighbours', () {
    const raw = '[{"k":"position","st":1,"e":2},'
        '{"k":"position","side":"long","st":1,"e":1.2,"sl":1.1,"tp":1.4},'
        '{"k":"ray","p":5}]';
    final decoded = decodeDrawings(raw);
    expect(decoded, hasLength(2));
    expect(decoded.first.side, PositionSide.long);
    expect(decoded.last.kind, DrawingKind.ray);
  });

  test('a short exits where the market leaves the profit zone', () {
    final drawing = positionAt(
      side: PositionSide.short,
      entry: 1.34500,
      stop: 1.34625,
      target: 1.34231,
    );
    // Bars trade inside the box, then one pushes below the target.
    final candles = [
      bar(0, 1.34500, 1.34540, 1.34480, 1.34510),
      bar(5, 1.34510, 1.34520, 1.34420, 1.34430),
      bar(10, 1.34430, 1.34440, 1.34200, 1.34210),
      bar(15, 1.34210, 1.34300, 1.34200, 1.34280),
    ];

    final outcome = resolvePositionOutcome(drawing: drawing, candles: candles);
    expect(outcome, isNotNull);
    expect(outcome!.reason, ExitReason.takeProfit);
    expect(outcome.price, closeTo(1.34231, 1e-9));
    expect(outcome.time, candles[2].time);
    expect(realisedR(drawing: drawing, exit: outcome), closeTo(2.15, 0.01));
  });

  test('a short exits at the stop when the market leaves the loss zone first',
      () {
    final drawing = positionAt(
      side: PositionSide.short,
      entry: 1.34500,
      stop: 1.34625,
      target: 1.34231,
    );
    final candles = [
      bar(0, 1.34500, 1.34530, 1.34490, 1.34520),
      bar(5, 1.34520, 1.34640, 1.34510, 1.34620),
      bar(10, 1.34620, 1.34630, 1.34100, 1.34120),
    ];

    final outcome = resolvePositionOutcome(drawing: drawing, candles: candles);
    expect(outcome, isNotNull);
    expect(outcome!.reason, ExitReason.stopLoss);
    expect(outcome.price, closeTo(1.34625, 1e-9));
    expect(outcome.time, candles[1].time);
    expect(realisedR(drawing: drawing, exit: outcome), closeTo(-1.0, 0.001));
  });

  test('a position still inside its zones has no exit yet', () {
    final drawing = positionAt(
      side: PositionSide.long,
      entry: 1.25000,
      stop: 1.24800,
      target: 1.25400,
    );
    final candles = [
      bar(0, 1.25000, 1.25150, 1.24900, 1.25100),
      bar(5, 1.25100, 1.25200, 1.25000, 1.25150),
    ];

    expect(resolvePositionOutcome(drawing: drawing, candles: candles), isNull);
  });

  test('a long banks a positive R at the target', () {
    final drawing = positionAt(
      side: PositionSide.long,
      entry: 1.25000,
      stop: 1.24800,
      target: 1.25400,
    );
    final candles = [
      bar(0, 1.25000, 1.25200, 1.24950, 1.25150),
      bar(5, 1.25150, 1.25420, 1.25100, 1.25400),
    ];

    final outcome = resolvePositionOutcome(drawing: drawing, candles: candles);
    expect(outcome!.reason, ExitReason.takeProfit);
    expect(realisedR(drawing: drawing, exit: outcome), closeTo(2.0, 0.001));
  });

  test('an unknown side reads as a long rather than dropping the level', () {
    const raw = '[{"k":"position","side":"sideways","st":1,'
        '"e":1.2,"sl":1.1,"tp":1.4}]';
    expect(decodeDrawings(raw).single.side, PositionSide.long);
  });
}
