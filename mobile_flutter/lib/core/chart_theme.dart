import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Colours and overlays for the price canvas.
///
/// The chart keeps its own palette instead of borrowing `AppColors`, so a
/// trader can put it on a light background (or a monochrome one) without the
/// journal around it turning white. Presets are `const`, so switching a theme
/// costs a repaint and nothing else.
///
/// The level lines (entry/stop/target/exit) deliberately keep the app palette:
/// they are the same colours as the level rows under the chart, so a light
/// chart theme must not repaint the legend that explains them.
@immutable
class ChartStyle {
  const ChartStyle({
    required this.id,
    required this.name,
    required this.background,
    required this.grid,
    required this.axis,
    required this.text,
    required this.muted,
    required this.crosshair,
    required this.bull,
    required this.bear,
    this.showGrid = true,
    this.showCrosshair = true,
    this.showWatermark = true,
  });

  /// Stable key for the preset, used for selection state.
  final String id;

  /// Shown in the style sheet and on the fullscreen canvas.
  final String name;

  final Color background;
  final Color grid;
  final Color axis;
  final Color text;
  final Color muted;
  final Color crosshair;
  final Color bull;
  final Color bear;

  final bool showGrid;
  final bool showCrosshair;
  final bool showWatermark;

  /// Whether the canvas is a light one — used to fade the watermark and pick
  /// the chip palette that sits on top of the chart.
  bool get isLight => background.computeLuminance() > 0.5;

  ChartStyle copyWith({
    Color? bull,
    Color? bear,
    bool? showGrid,
    bool? showCrosshair,
    bool? showWatermark,
  }) {
    return ChartStyle(
      id: id,
      name: name,
      background: background,
      grid: grid,
      axis: axis,
      text: text,
      muted: muted,
      crosshair: crosshair,
      bull: bull ?? this.bull,
      bear: bear ?? this.bear,
      showGrid: showGrid ?? this.showGrid,
      showCrosshair: showCrosshair ?? this.showCrosshair,
      showWatermark: showWatermark ?? this.showWatermark,
    );
  }

  /// The journal's own dark palette.
  static const ChartStyle ink = ChartStyle(
    id: 'ink',
    name: 'Ink',
    background: Color(0xFF080A0F),
    grid: Color(0xFF242A36),
    axis: Color(0xFF333B4B),
    text: Color(0xFFEDF0F5),
    muted: Color(0xFF6B7280),
    crosshair: Color(0xFF6B7280),
    bull: Color(0xFF45D29A),
    bear: Color(0xFFF26B78),
  );

  /// Trading platform dark: deeper blue-grey with the familiar teal/red pair.
  static const ChartStyle slate = ChartStyle(
    id: 'slate',
    name: 'Slate',
    background: Color(0xFF131722),
    grid: Color(0xFF2A2E39),
    axis: Color(0xFF363A45),
    text: Color(0xFFD1D4DC),
    muted: Color(0xFF787B86),
    crosshair: Color(0xFF9598A1),
    bull: Color(0xFF26A69A),
    bear: Color(0xFFEF5350),
  );

  /// Light canvas for daylight and printing screenshots.
  static const ChartStyle paper = ChartStyle(
    id: 'paper',
    name: 'Paper',
    background: Color(0xFFFFFFFF),
    grid: Color(0xFFE8EBF0),
    axis: Color(0xFFD3D8E0),
    text: Color(0xFF131722),
    muted: Color(0xFF5D6675),
    crosshair: Color(0xFF9AA3B0),
    bull: Color(0xFF089981),
    bear: Color(0xFFF23645),
  );

  /// Black canvas, near-white bars — the monochrome look of a newsprint chart.
  static const ChartStyle mono = ChartStyle(
    id: 'mono',
    name: 'Mono',
    background: Color(0xFF000000),
    grid: Color(0xFF1B1B1B),
    axis: Color(0xFF2C2C2C),
    text: Color(0xFFF0F0F0),
    muted: Color(0xFF8A8A8A),
    crosshair: Color(0xFFA0A0A0),
    bull: Color(0xFFE8E8E8),
    bear: Color(0xFF9A9A9A),
  );

  static const List<ChartStyle> presets = <ChartStyle>[
    ink,
    slate,
    paper,
    mono,
  ];

  /// Candle colours offered in the style sheet. Ordered so the first two rows
  /// read as "green/red first", the way most traders expect.
  static const List<Color> candlePalette = <Color>[
    Color(0xFF45D29A),
    Color(0xFF26A69A),
    Color(0xFF4C9AFF),
    Color(0xFFD5A44E),
    Color(0xFFF0B90B),
    Color(0xFFAB7DF6),
    Color(0xFFF26B78),
    Color(0xFFEF5350),
    Color(0xFF98A1B0),
    Color(0xFFEDF0F5),
  ];

  /// Storage key for the single saved style.
  static const String storageKey = 'chart.style.v1';

  /// The style chart screens open with, and what the style sheet edits.
  static ChartStyle current = ink;

  /// Rebuilds the saved style. Called once at startup; a fresh install, a
  /// corrupt value or unavailable storage all leave the default in place,
  /// because a theme is decoration and must never block the chart.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      // Unknown preset ids (a removed theme, an edited file) fall back to Ink
      // while keeping any custom candle colours that are still readable.
      final preset = presets.firstWhere(
        (style) => style.id == decoded['preset'],
        orElse: () => ink,
      );
      current = preset.copyWith(
        bull: _readColor(decoded['bull']) ?? preset.bull,
        bear: _readColor(decoded['bear']) ?? preset.bear,
        showGrid: _readFlag(decoded['grid']),
        showCrosshair: _readFlag(decoded['crosshair']),
        showWatermark: _readFlag(decoded['watermark']),
      );
    } catch (_) {
      // Keep the default style.
    }
  }

  /// Writes the current choice. Fire-and-forget from the style sheet: the
  /// sheet repaints immediately and the write lands in the background.
  static Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        storageKey,
        jsonEncode(<String, Object>{
          'preset': current.id,
          'bull': current.bull.toARGB32(),
          'bear': current.bear.toARGB32(),
          'grid': current.showGrid,
          'crosshair': current.showCrosshair,
          'watermark': current.showWatermark,
        }),
      );
    } catch (_) {
      // Ignored for the same reason restore() is defensive.
    }
  }

  static Color? _readColor(Object? value) =>
      value is int ? Color(value) : null;

  static bool? _readFlag(Object? value) => value is bool ? value : null;
}
