/// How a drawing anchor treats the candle values under the finger.
///
/// A weak magnet is the one a desk actually uses: if the press looks like it is
/// on the high, it is on the high, but a press out in open space stays exactly
/// where it was released. A strong magnet gives up that freedom and always
/// lands on the nearest open, high, low or close, which is what you want when
/// you are placing a level by feel rather than by eye.
enum MagnetMode {
  off('Off'),
  weak('Weak'),
  strong('Strong');

  const MagnetMode(this.label);

  final String label;

  /// The next mode when the toolbar button is tapped: off → weak → strong → off.
  /// Weak comes first so a trader who never touches it twice gets the sensible
  /// one.
  MagnetMode get next => switch (this) {
        MagnetMode.off => MagnetMode.weak,
        MagnetMode.weak => MagnetMode.strong,
        MagnetMode.strong => MagnetMode.off,
      };
}

/// How near, in logical pixels, a weak magnet will grab an anchor. Fifteen is
/// about a fingertip's slop: close enough that a deliberate press in open space
/// is never captured, wide enough that aiming at a 2 px wick works.
const double weakMagnetRadius = 15;

/// A candidate anchor: the price itself and how far it is from the finger, in
/// pixels (vertical distance is what a price axis magnifies).
typedef MagnetCandidate = ({double price, double dy});

/// The price a point should take.
///
/// [raw] is where the finger actually is. Off returns it untouched, strong
/// returns the nearest candidate whatever the distance, and weak returns the
/// nearest only inside [weakMagnetRadius].
double magnetPrice({
  required double raw,
  required Iterable<MagnetCandidate> candidates,
  required MagnetMode mode,
}) {
  if (mode == MagnetMode.off) return raw;
  MagnetCandidate? best;
  for (final candidate in candidates) {
    if (best == null || candidate.dy.abs() < best.dy.abs()) best = candidate;
  }
  if (best == null) return raw;
  if (mode == MagnetMode.strong) return best.price;
  return best.dy.abs() <= weakMagnetRadius ? best.price : raw;
}

/// The anchor prices a magnet may snap to: the open, high, low and close of
/// the candle under the finger and its two neighbours.
///
/// Neighbours are included because a point dropped between two bars is aiming
/// at the swing, and the swing is often the bar either side of the crosshair.
List<MagnetCandidate> magnetCandidates({
  required Iterable<double> prices,
  required double Function(double price) yFor,
  required double fingerY,
}) {
  final candidates = <MagnetCandidate>[];
  for (final price in prices) {
    if (!price.isFinite) continue;
    candidates.add((price: price, dy: yFor(price) - fingerY));
  }
  return candidates;
}
