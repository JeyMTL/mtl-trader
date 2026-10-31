import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'indicators.dart';

/// How the price series is drawn.
enum ChartType { candles, line, area }

/// A lower-pane indicator drawn under the price.
enum Oscillator { none, rsi, macd }

extension OscillatorLabel on Oscillator {
  String get label {
    switch (this) {
      case Oscillator.none:
        return 'None';
      case Oscillator.rsi:
        return 'RSI';
      case Oscillator.macd:
        return 'MACD';
    }
  }
}

extension ChartTypeLabel on ChartType {
  String get label {
    switch (this) {
      case ChartType.candles:
        return 'Candles';
      case ChartType.line:
        return 'Line';
      case ChartType.area:
        return 'Area';
    }
  }
}

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
    this.chartType = ChartType.candles,
    this.studies = const <OverlayStudy>{},
    this.studyPeriods = const <String, int>{},
    this.showVolume = true,
    this.oscillator = Oscillator.none,
    this.logScale = false,
    this.rsiPeriod = 14,
    this.macdFast = 12,
    this.macdSlow = 26,
    this.macdSignal = 9,
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

  /// Candles, a close line, or a filled area.
  final ChartType chartType;

  /// Moving averages drawn over the price.
  final Set<OverlayStudy> studies;

  /// Period overrides keyed by study name; missing means the study default.
  final Map<String, int> studyPeriods;

  /// Volume histogram under the price.
  final bool showVolume;

  /// Lower-pane indicator, if any.
  final Oscillator oscillator;

  /// Logarithmic price axis instead of a linear one.
  final bool logScale;

  /// RSI period when the oscillator is RSI.
  final int rsiPeriod;

  /// MACD lengths, in candles.
  final int macdFast;
  final int macdSlow;
  final int macdSignal;

  /// The period this study is drawn with.
  int periodFor(OverlayStudy study) => studyPeriods[study.name] ?? study.period;

  /// Whether the canvas is a light one — used to fade the watermark and pick
  /// the chip palette that sits on top of the chart.
  bool get isLight => background.computeLuminance() > 0.5;

  ChartStyle copyWith({
    Color? bull,
    Color? bear,
    bool? showGrid,
    bool? showCrosshair,
    bool? showWatermark,
    ChartType? chartType,
    Set<OverlayStudy>? studies,
    Map<String, int>? studyPeriods,
    bool? showVolume,
    Oscillator? oscillator,
    bool? logScale,
    int? rsiPeriod,
    int? macdFast,
    int? macdSlow,
    int? macdSignal,
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
      chartType: chartType ?? this.chartType,
      studies: studies ?? this.studies,
      studyPeriods: studyPeriods ?? this.studyPeriods,
      showVolume: showVolume ?? this.showVolume,
      oscillator: oscillator ?? this.oscillator,
      logScale: logScale ?? this.logScale,
      rsiPeriod: rsiPeriod ?? this.rsiPeriod,
      macdFast: macdFast ?? this.macdFast,
      macdSlow: macdSlow ?? this.macdSlow,
      macdSignal: macdSignal ?? this.macdSignal,
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

  /// Storage key for the global style.
  static const String storageKey = 'chart.style.v1';

  /// The style chart screens open with, and what the style sheet edits.
  static ChartStyle current = ink;

  /// JSON for this style; shared by the global theme and per-instrument layouts.
  Map<String, Object?> toJson() => <String, Object?>{
        'preset': id,
        'bull': bull.toARGB32(),
        'bear': bear.toARGB32(),
        'grid': showGrid,
        'crosshair': showCrosshair,
        'watermark': showWatermark,
        'chartType': chartType.name,
        'studies': studies.map((study) => study.name).toList(),
        'studyPeriods': studyPeriods,
        'volume': showVolume,
        'oscillator': oscillator.name,
        'logScale': logScale,
        'rsiPeriod': rsiPeriod,
        'macdFast': macdFast,
        'macdSlow': macdSlow,
        'macdSignal': macdSignal,
      };

  static String encode(ChartStyle style) => jsonEncode(style.toJson());

  static ChartStyle decode(String? raw, {ChartStyle fallback = ink}) {
    if (raw == null || raw.isEmpty) return fallback;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return fallback;
      return fromJson(decoded, fallback: fallback);
    } catch (_) {
      return fallback;
    }
  }

  /// Unknown preset ids (a removed theme, an edited file) fall back to
  /// [fallback] while keeping any custom values that are still readable.
  static ChartStyle fromJson(
    Map<Object?, Object?> decoded, {
    ChartStyle fallback = ink,
  }) {
    final preset = presets.firstWhere(
      (style) => style.id == decoded['preset'],
      orElse: () => fallback,
    );
    return preset.copyWith(
      bull: _readColor(decoded['bull']) ?? preset.bull,
      bear: _readColor(decoded['bear']) ?? preset.bear,
      showGrid: _readFlag(decoded['grid']),
      showCrosshair: _readFlag(decoded['crosshair']),
      showWatermark: _readFlag(decoded['watermark']),
      chartType: _readChartType(decoded['chartType']),
      studies: _readStudies(decoded['studies']),
      studyPeriods: _readPeriods(decoded['studyPeriods']),
      showVolume: _readFlag(decoded['volume']),
      oscillator: _readOscillator(decoded['oscillator']),
      logScale: _readFlag(decoded['logScale']),
      rsiPeriod: _readInt(decoded['rsiPeriod']),
      macdFast: _readInt(decoded['macdFast']),
      macdSlow: _readInt(decoded['macdSlow']),
      macdSignal: _readInt(decoded['macdSignal']),
    );
  }

  /// Rebuilds the saved style. Called once at startup; a fresh install, a
  /// corrupt value or unavailable storage all leave the default in place,
  /// because a theme is decoration and must never block the chart.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null) return;
      current = decode(raw);
    } catch (_) {
      // Keep the default style.
    }
  }

  /// Writes the global choice. Fire-and-forget from the style sheet.
  static Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, encode(current));
    } catch (_) {
      // Ignored for the same reason restore() is defensive.
    }
  }

  /// Storage key for one instrument's chart layout.
  static String layoutKey(String symbol) => 'chart.layout.v1.$symbol';

  /// The layout this instrument had last time, or the global style.
  static Future<ChartStyle> loadLayout(String symbol) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decode(prefs.getString(layoutKey(symbol)), fallback: current);
    } catch (_) {
      return current;
    }
  }

  static Future<void> saveLayout(String symbol, ChartStyle style) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(layoutKey(symbol), encode(style));
    } catch (_) {
      // Ignored: the chart keeps its in-memory layout either way.
    }
  }

  static Color? _readColor(Object? value) => value is int ? Color(value) : null;

  static bool? _readFlag(Object? value) => value is bool ? value : null;

  static int? _readInt(Object? value) => value is int ? value : null;

  static ChartType? _readChartType(Object? value) {
    if (value is! String) return null;
    for (final type in ChartType.values) {
      if (type.name == value) return type;
    }
    return null;
  }

  static Oscillator? _readOscillator(Object? value) {
    if (value is! String) return null;
    for (final oscillator in Oscillator.values) {
      if (oscillator.name == value) return oscillator;
    }
    return null;
  }

  static Set<OverlayStudy>? _readStudies(Object? value) {
    if (value is! List) return null;
    final names = value.whereType<String>().toSet();
    return <OverlayStudy>{
      for (final study in OverlayStudy.values)
        if (names.contains(study.name)) study,
    };
  }

  static Map<String, int>? _readPeriods(Object? value) {
    if (value is! Map) return null;
    final periods = <String, int>{};
    value.forEach((key, raw) {
      if (key is String && raw is int) periods[key] = raw;
    });
    return periods;
  }
}
