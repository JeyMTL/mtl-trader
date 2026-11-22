import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/chart_drawings.dart';
import 'package:mtl_trader_mobile/core/trade_exit.dart';
import 'package:mtl_trader_mobile/services/chart_drawings_sync.dart'
    show lookSignature;
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
  _lookTests();

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

  test('flipping a long to a short keeps the risk and the reward', () {
    final long = positionAt(
      side: PositionSide.long,
      entry: 100,
      stop: 90,
      target: 120,
    );
    final short = long.withSide(PositionSide.short);

    expect(short.side, PositionSide.short);
    // Entry held, legs mirrored: the stop moves above, the target below.
    expect(short.entry, 100);
    expect(short.stop, 110);
    expect(short.target, 80);
    expect(short.rewardRatio, closeTo(2, 1e-9));
  });

  test('flipping back to the same side changes nothing', () {
    final long = positionAt(
      side: PositionSide.long,
      entry: 100,
      stop: 90,
      target: 120,
    );
    expect(identical(long.withSide(PositionSide.long), long), isTrue);
  });

  test('a position box remembers the candle it ends on', () {
    final drawing = positionAt(
      side: PositionSide.long,
      entry: 1.25,
      stop: 1.248,
      target: 1.254,
    ).withEnd(
      DateTime.utc(2026, 11, 11, 13).millisecondsSinceEpoch,
    );

    final decoded = decodeDrawings(encodeDrawings([drawing])).single;
    expect(decoded.endMs, drawing.endMs);
    expect(decoded.isPosition, isTrue);
  });

  test('the right edge can never move before the left edge', () {
    final drawing = positionAt(
      side: PositionSide.long,
      entry: 1.25,
      stop: 1.248,
      target: 1.254,
    );
    expect(drawing.withEnd(1).endMs, drawing.startMs);
  });

  test('an exit after the box end belongs to a later idea', () {
    final drawing = positionAt(
      side: PositionSide.long,
      entry: 1.25000,
      stop: 1.24800,
      target: 1.25400,
    ).withEnd(
      DateTime.utc(2026, 11, 11, 12, 2).millisecondsSinceEpoch,
    );
    final candles = [
      bar(0, 1.25000, 1.25100, 1.24950, 1.25050),
      bar(5, 1.25100, 1.25420, 1.25080, 1.25400),
    ];

    expect(resolvePositionOutcome(drawing: drawing, candles: candles), isNull);
  });

  test('an anchored object survives a save and reload', () {
    const drawing = ChartDrawing.points(
      kind: DrawingKind.fib,
      points: [
        ChartPoint(ms: 1762900000000, price: 1.25100),
        ChartPoint(ms: 1762900600000, price: 1.24700),
      ],
    );

    final decoded = ChartDrawing.fromJson(drawing.toJson());

    expect(decoded?.kind, DrawingKind.fib);
    expect(decoded!.points.length, 2);
    expect(decoded.points.first.ms, 1762900000000);
    expect(decoded.points.last.price, closeTo(1.24700, 1e-9));
  });

  test('a text label keeps its words', () {
    const drawing = ChartDrawing.points(
      kind: DrawingKind.text,
      text: 'London open',
      points: [ChartPoint(ms: 1762900000000, price: 1.25)],
    );

    expect(ChartDrawing.fromJson(drawing.toJson())?.text, 'London open');
  });

  test('moving an anchored object shifts every point together', () {
    const drawing = ChartDrawing.points(
      kind: DrawingKind.rectangle,
      points: [
        ChartPoint(ms: 1762900000000, price: 1.25100),
        ChartPoint(ms: 1762900600000, price: 1.24700),
      ],
    );

    final moved = drawing.translated(
      shiftTime: (ms) => ms + 60000,
      priceDelta: 0.00050,
    );

    expect(moved.points.first.ms, 1762900060000);
    expect(moved.points.last.ms, 1762900660000);
    expect(moved.points.first.price, closeTo(1.25150, 1e-9));
    expect(moved.points.last.price, closeTo(1.24750, 1e-9));
    expect(drawing.points.first.ms, 1762900000000, reason: 'the original is untouched');
  });

  test('dragging one anchor leaves the other anchors alone', () {
    const drawing = ChartDrawing.points(
      kind: DrawingKind.rectangle,
      points: [
        ChartPoint(ms: 1762900000000, price: 1.25100),
        ChartPoint(ms: 1762900600000, price: 1.24700),
      ],
    );

    final moved = drawing.withPoint(
      1,
      const ChartPoint(ms: 1762901200000, price: 1.24500),
    );

    expect(moved.points.first.ms, 1762900000000);
    expect(moved.points.first.price, closeTo(1.25100, 1e-9));
    expect(moved.points.last.ms, 1762901200000);
    expect(moved.points.last.price, closeTo(1.24500, 1e-9));
  });

  test('a trend line takes a handle drag at the end that was grabbed', () {
    const drawing = ChartDrawing.trend(
      startMs: 1762900000000,
      startPrice: 1.25000,
      endMs: 1762900600000,
      endPrice: 1.25200,
    );

    final head = drawing.withPoint(
      0,
      const ChartPoint(ms: 1762899000000, price: 1.24800),
    );
    expect(head.startPrice, closeTo(1.24800, 1e-9));
    expect(head.endPrice, closeTo(1.25200, 1e-9));

    final tail = drawing.withPoint(
      1,
      const ChartPoint(ms: 1762901200000, price: 1.25600),
    );
    expect(tail.startPrice, closeTo(1.25000, 1e-9));
    expect(tail.endMs, 1762901200000);
    expect(tail.endPrice, closeTo(1.25600, 1e-9));
  });
}

void _lookTests() {
  test('a restyle survives a drag and a round trip through storage', () {
    const look = DrawingLook(
      tint: Color(0xFFFF6B35),
      weight: 2,
      dashed: true,
      locked: true,
    );
    final drawing = ChartDrawing.trend(
      startMs: 1762899000000,
      startPrice: 1.25000,
      endMs: 1762900600000,
      endPrice: 1.25200,
      look: look,
    );

    // A handle drag rebuilds the object: the look must come with it.
    final moved = drawing.withPoint(
      1,
      const ChartPoint(ms: 1762900600000, price: 1.25300),
    );
    expect(moved.ink, const Color(0xFFFF6B35));
    expect(moved.look.weight, 2);
    expect(moved.look.dashed, isTrue);
    expect(moved.look.locked, isTrue);

    // And storage has to keep it, or a restart would silently re-style it.
    final restored = ChartDrawing.fromJson(drawing.toJson());
    expect(restored, isNotNull);
    expect(restored!.ink, const Color(0xFFFF6B35));
    expect(restored.look.weight, 2);
    expect(restored.look.dashed, isTrue);
    expect(restored.look.locked, isTrue);
  });

  test('an untouched object carries no look keys at all', () {
    const drawing = ChartDrawing.ray(price: 1.10);
    expect(drawing.look.isDefault, isTrue);
    expect(drawing.toJson().containsKey('lk'), isFalse);
    expect(drawing.ink, drawingColor);
  });

  test('a fill percent survives storage and marks the object as styled', () {
    const drawing = ChartDrawing.points(
      kind: DrawingKind.rectangle,
      points: [
        ChartPoint(ms: 1762899000000, price: 1.25),
        ChartPoint(ms: 1762900600000, price: 1.26),
      ],
      look: DrawingLook(fill: 35),
    );

    expect(drawing.look.fill, 35);
    expect(drawing.look.isDefault, isFalse);
    expect(drawing.hasFill, isTrue);

    final restored = ChartDrawing.fromJson(drawing.toJson());
    expect(restored!.look.fill, 35);
  });

  test('a fill is clamped to a percentage when read back', () {
    expect(DrawingLook.fromJson({'f': 400}).fill, 100);
    expect(DrawingLook.fromJson({'f': -8}).fill, 0);
    expect(DrawingLook.fromJson({'f': 'wide'}).fill, isNull);
  });

  test('a restyle makes the cloud signature differ', () {
    const plain = ChartDrawing.ray(price: 1.10);
    final tinted = plain.withLook(const DrawingLook(tint: Color(0xFF45D29A)));
    expect(lookSignature(plain.look), isNot(lookSignature(tinted.look)));
    // Geometry alone must not move the signature when nothing was restyled.
    expect(
      lookSignature(const DrawingLook()),
      lookSignature(const DrawingLook()),
    );
  });
}
