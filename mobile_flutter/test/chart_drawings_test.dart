import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/chart_drawings.dart';

void main() {
  test('round-trips trend lines and rays through JSON', () {
    const drawings = <ChartDrawing>[
      ChartDrawing.trend(
        startMs: 1000,
        startPrice: 1.1,
        endMs: 2000,
        endPrice: 1.2,
      ),
      ChartDrawing.ray(price: 1.15),
    ];

    final decoded = decodeDrawings(encodeDrawings(drawings));
    expect(decoded, hasLength(2));
    expect(decoded.first.kind, DrawingKind.trend);
    expect(decoded.first.startMs, 1000);
    expect(decoded.first.endMs, 2000);
    expect(decoded.first.endPrice, 1.2);
    expect(decoded.last.kind, DrawingKind.ray);
    expect(decoded.last.price, 1.15);
  });

  test('ignores unreadable entries instead of dropping everything', () {
    expect(decodeDrawings(null), isEmpty);
    expect(decodeDrawings(''), isEmpty);
    expect(decodeDrawings('not json'), isEmpty);
    expect(decodeDrawings('{"k":"ray","p":1}'), isEmpty);
    expect(decodeDrawings('[{"k":"trend"},{"k":"ray"},{"k":"other"}]'), isEmpty);
    expect(decodeDrawings('[{"k":"ray","p":2}]'), hasLength(1));
  });

  test('keeps a valid drawing beside a corrupt one', () {
    final decoded = decodeDrawings(
      '[{"k":"ray","p":1.5},{"k":"trend","st":"bad"}]',
    );
    expect(decoded, hasLength(1));
    expect(decoded.single.price, 1.5);
  });
}
