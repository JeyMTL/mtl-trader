import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/market_data.dart' show Candle;
import 'trade_exit.dart';

/// Colour for trader-drawn objects; fixed so it reads on every chart theme.
const Color drawingColor = Color(0xFF4C9AFF);

/// The position tool's zones and levels.
///
/// These mirror a TradingView long/short position: teal for the profit leg,
/// red for the risk, and a neutral grey for the entry line. Kept next to the
/// model so the canvas and any legend agree on one set of colours.
const Color positionProfitColor = Color(0xFF26A69A);
const Color positionLossColor = Color(0xFFF23645);
const Color positionEntryColor = Color(0xFF5D6675);

/// What a tap on the chart currently creates.
enum DrawingTool { none, trend, ray, longPosition, shortPosition }

enum DrawingKind { trend, ray, position }

/// Whether a position tool is marking a long or a short.
enum PositionSide { long, short }

/// One of the three levels of a position tool, in the order they are stacked
/// on a long.
enum PositionLevel { entry, target, stop }

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
        price = null,
        side = null,
        entry = null,
        stop = null,
        target = null;

  const ChartDrawing.ray({required this.price})
      : kind = DrawingKind.ray,
        startMs = 0,
        startPrice = 0,
        endMs = 0,
        endPrice = 0,
        side = null,
        entry = null,
        stop = null,
        target = null;

  /// A long or short position: one entry line, a stop and a target, with the
  /// profit and loss zones filled between them.
  ///
  /// The tool starts at [startMs] and runs to the right edge of the chart, which
  /// is how a trader marks a setup they are still watching: levels stay put
  /// while new candles print under them.
  const ChartDrawing.position({
    required PositionSide this.side,
    required this.startMs,
    required double this.entry,
    required double this.stop,
    required double this.target,
  })  : kind = DrawingKind.position,
        startPrice = 0,
        endMs = 0,
        endPrice = 0,
        price = null;

  final DrawingKind kind;

  /// First point of a trend line, epoch milliseconds of the candle under it.
  final int startMs;
  final double startPrice;

  /// Second point of a trend line.
  final int endMs;
  final double endPrice;

  /// Price for a horizontal ray; null for a trend line.
  final double? price;

  /// Side of a position tool; null for every other drawing.
  final PositionSide? side;

  /// The three prices of a position tool; null for every other drawing.
  final double? entry;
  final double? stop;
  final double? target;

  bool get isPosition => kind == DrawingKind.position;

  /// The level a long loses money towards, and a short profits towards.
  double? levelFor(PositionLevel level) {
    switch (level) {
      case PositionLevel.entry:
        return entry;
      case PositionLevel.target:
        return target;
      case PositionLevel.stop:
        return stop;
    }
  }

  /// Reward-to-risk of the position, or null when either leg is degenerate.
  double? get rewardRatio {
    final e = entry, s = stop, t = target;
    if (e == null || s == null || t == null) return null;
    final risk = (e - s).abs();
    if (risk < 1e-9) return null;
    return (t - e).abs() / risk;
  }

  ChartDrawing copyWithLevel(PositionLevel level, double price) {
    final e = entry ?? 0;
    final s = stop ?? 0;
    final t = target ?? 0;
    return ChartDrawing.position(
      side: side ?? PositionSide.long,
      startMs: startMs,
      entry: level == PositionLevel.entry ? price : e,
      stop: level == PositionLevel.stop ? price : s,
      target: level == PositionLevel.target ? price : t,
    );
  }

  ChartDrawing shifted({required double priceDelta, required int startMs}) {
    final e = entry ?? 0;
    final s = stop ?? 0;
    final t = target ?? 0;
    return ChartDrawing.position(
      side: side ?? PositionSide.long,
      startMs: startMs,
      entry: e + priceDelta,
      stop: s + priceDelta,
      target: t + priceDelta,
    );
  }

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
      case DrawingKind.position:
        return {
          'k': kind.name,
          'side': side?.name,
          'st': startMs,
          'e': entry,
          'sl': stop,
          'tp': target,
        };
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
    if (kind == DrawingKind.position.name) {
      final st = value['st'];
      final e = value['e'];
      final sl = value['sl'];
      final tp = value['tp'];
      final side = value['side'];
      if (st is! num || e is! num || sl is! num || tp is! num) return null;
      return ChartDrawing.position(
        side: side == PositionSide.short.name
            ? PositionSide.short
            : PositionSide.long,
        startMs: st.toInt(),
        entry: e.toDouble(),
        stop: sl.toDouble(),
        target: tp.toDouble(),
      );
    }
    return null;
  }
}

/// Where a position tool was taken out of one of its zones.
///
/// The entry runs through the middle of the box: an exit is the candle that
/// first pushes past the far edge of the profit zone (the target) or the far
/// edge of the loss zone (the stop). Null means neither edge was reached inside
/// the candles we hold — an idea still playing out, not a closed trade.
ResolvedExit? resolvePositionOutcome({
  required ChartDrawing drawing,
  required List<Candle> candles,
}) {
  if (!drawing.isPosition) return null;
  final entry = drawing.entry;
  final stop = drawing.stop;
  final target = drawing.target;
  if (entry == null || stop == null || target == null) return null;

  final outcome = resolveExit(
    type: drawing.side == PositionSide.short ? 'SELL' : 'BUY',
    entry: entry,
    stop: stop,
    take: target,
    entryTime:
        DateTime.fromMillisecondsSinceEpoch(drawing.startMs, isUtc: true),
    candles: candles,
  );
  // `latestPrice` is the resolver's "neither level was reached" fallback; for a
  // position tool that is not an exit, so nothing is marked.
  if (outcome == null || outcome.reason == ExitReason.latestPrice) return null;
  return outcome;
}

/// The result of a position in risk units: `+2` banked twice the risk, `-1`
/// lost the stop. Null when the box has no risk to measure.
double? realisedR({
  required ChartDrawing drawing,
  required ResolvedExit exit,
}) {
  final entry = drawing.entry;
  final stop = drawing.stop;
  if (entry == null || stop == null) return null;
  final risk = (entry - stop).abs();
  if (risk < 1e-9) return null;
  final move = drawing.side == PositionSide.short
      ? entry - exit.price
      : exit.price - entry;
  return move / risk;
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
