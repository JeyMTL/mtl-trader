import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Colour for trader-drawn objects; fixed so it reads on every chart theme.
const Color drawingColor = Color(0xFF4C9AFF);

/// What a tap on the chart currently creates.
enum DrawingTool { none, trend, ray }

enum DrawingKind { trend, ray }

/// A line the trader drew, anchored to candle **times** rather than indices, so
/// it survives a different window, a different candle size or a new session.
@immutable
class ChartDrawing {
  const ChartDrawing.trend({
    required this.startMs,
    required this.startPrice,
    required this.endMs,
    required this.endPrice,
  })  : kind = DrawingKind.trend,
        price = null;

  const ChartDrawing.ray({required this.price})
      : kind = DrawingKind.ray,
        startMs = 0,
        startPrice = 0,
        endMs = 0,
        endPrice = 0;

  final DrawingKind kind;

  /// First point of a trend line, epoch milliseconds of the candle under it.
  final int startMs;
  final double startPrice;

  /// Second point of a trend line.
  final int endMs;
  final double endPrice;

  /// Price for a horizontal ray; null for a trend line.
  final double? price;

  Map<String, Object?> toJson() {
    switch (kind) {
      case DrawingKind.trend:
        return {
          'k': kind.name,
          'st': startMs,
          'sp': startPrice,
          'et': endMs,
          'ep': endPrice,
        };
      case DrawingKind.ray:
        return {'k': kind.name, 'p': price};
    }
  }

  /// Null for anything unreadable, so one corrupt entry cannot drop the rest.
  static ChartDrawing? fromJson(Object? value) {
    if (value is! Map) return null;
    final kind = value['k'];
    if (kind == DrawingKind.trend.name) {
      final st = value['st'];
      final sp = value['sp'];
      final et = value['et'];
      final ep = value['ep'];
      if (st is! num || sp is! num || et is! num || ep is! num) return null;
      return ChartDrawing.trend(
        startMs: st.toInt(),
        startPrice: sp.toDouble(),
        endMs: et.toInt(),
        endPrice: ep.toDouble(),
      );
    }
    if (kind == DrawingKind.ray.name) {
      final price = value['p'];
      if (price is! num) return null;
      return ChartDrawing.ray(price: price.toDouble());
    }
    return null;
  }
}

/// The first point of a trend line that is still being drawn.
@immutable
class DrawingDraft {
  const DrawingDraft({required this.timeMs, required this.price});

  final int timeMs;
  final double price;
}

String encodeDrawings(List<ChartDrawing> drawings) =>
    jsonEncode([for (final drawing in drawings) drawing.toJson()]);

List<ChartDrawing> decodeDrawings(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final value in decoded)
        if (ChartDrawing.fromJson(value) case final drawing?) drawing,
    ];
  } catch (_) {
    return const [];
  }
}

/// Per-instrument storage. A missing or corrupt value means "no drawings",
/// because annotations must never block the chart.
class ChartDrawingStore {
  static const String prefix = 'chart.drawings.v1.';

  static Future<List<ChartDrawing>> load(String symbol) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decodeDrawings(prefs.getString('$prefix$symbol'));
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(String symbol, List<ChartDrawing> drawings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (drawings.isEmpty) {
        await prefs.remove('$prefix$symbol');
      } else {
        await prefs.setString('$prefix$symbol', encodeDrawings(drawings));
      }
    } catch (_) {
      // Fire-and-forget: the chart keeps the in-memory drawings either way.
    }
  }
}
