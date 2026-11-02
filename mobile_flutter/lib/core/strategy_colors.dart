import 'package:flutter/material.dart';

/// A stable colour per strategy label.
///
/// The same palette and the same hashing as `src/lib/strategy-colors.ts`, so a
/// strategy carries one colour across the phone and the web. Collisions are
/// harmless: the dot is a visual anchor, not an identifier.
const List<Color> strategyPalette = <Color>[
  Color(0xFF22D3EE), // cyan
  Color(0xFFA78BFA), // violet
  Color(0xFFF472B6), // pink
  Color(0xFFFBBF24), // amber
  Color(0xFF34D399), // emerald
  Color(0xFF60A5FA), // blue
  Color(0xFFFB923C), // orange
  Color(0xFFE879F9), // fuchsia
  Color(0xFF4ADE80), // green
  Color(0xFFF87171), // red
];

Color strategyColor(String name) {
  var hash = 0;
  for (final unit in name.codeUnits) {
    hash = (hash * 31 + unit) % 1000003;
  }
  return strategyPalette[hash % strategyPalette.length];
}
