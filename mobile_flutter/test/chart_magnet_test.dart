import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/chart_magnet.dart';

void main() {
  const high = (price: 1.09720, dy: 6.0);
  const low = (price: 1.09640, dy: 11.0);
  const far = (price: 1.10000, dy: 240.0);

  test('off leaves the finger exactly where it was', () {
    expect(
      magnetPrice(raw: 1.09695, candidates: [high], mode: MagnetMode.off),
      1.09695,
    );
  });

  test('weak grabs an anchor inside the radius and lets the rest go', () {
    // Six pixels from the high is a press that meant the high.
    expect(
      magnetPrice(raw: 1.09695, candidates: [high], mode: MagnetMode.weak),
      high.price,
    );
    // Two hundred and forty pixels away is a press in open space.
    expect(
      magnetPrice(raw: 1.09695, candidates: [far], mode: MagnetMode.weak),
      1.09695,
    );
  });

  test('the weak radius is fifteen pixels, and the boundary is inclusive', () {
    expect(
      magnetPrice(
        raw: 1.0,
        candidates: [(price: 1.2, dy: weakMagnetRadius)],
        mode: MagnetMode.weak,
      ),
      1.2,
    );
    expect(
      magnetPrice(
        raw: 1.0,
        candidates: [(price: 1.2, dy: weakMagnetRadius + 0.5)],
        mode: MagnetMode.weak,
      ),
      1.0,
    );
  });

  test('strong snaps no matter how far away the anchor is', () {
    expect(
      magnetPrice(raw: 1.09695, candidates: [far], mode: MagnetMode.strong),
      far.price,
    );
  });

  test('the nearest anchor wins, not the first one offered', () {
    expect(
      magnetPrice(
        raw: 1.09700,
        candidates: [low, high],
        mode: MagnetMode.weak,
      ),
      high.price,
    );
    expect(
      magnetPrice(
        raw: 1.09700,
        candidates: [high, low],
        mode: MagnetMode.weak,
      ),
      high.price,
    );
  });

  test('no anchors means no snapping, never a null price', () {
    expect(
      magnetPrice(raw: 1.09695, candidates: const [], mode: MagnetMode.strong),
      1.09695,
    );
  });

  test('the button cycles off → weak → strong → off', () {
    expect(MagnetMode.off.next, MagnetMode.weak);
    expect(MagnetMode.weak.next, MagnetMode.strong);
    expect(MagnetMode.strong.next, MagnetMode.off);
  });
}
