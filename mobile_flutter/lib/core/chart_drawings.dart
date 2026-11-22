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

/// Every object the chart can hold.
///
/// `trend`, `ray` and `position` keep their own shapes because they are edited
/// level by level. The rest are anchor-based: a list of points in chart space,
/// which is enough for a box, an ellipse, a fib ladder, a brush stroke or a
/// text label without a class per tool.
enum DrawingKind {
  trend,
  ray,
  position,
  rectangle,
  ellipse,
  vline,
  fib,
  fibExtension,
  text,
  arrowUp,
  arrowDown,
  brush,
  measure,
}

/// A point in chart space: a candle time and a price. Times rather than indices,
/// so an object stays where it was drawn when the window or candle size changes.
@immutable
class ChartPoint {
  const ChartPoint({required this.ms, required this.price});

  final int ms;
  final double price;

  ChartPoint shifted({required int ms, required double price}) =>
      ChartPoint(ms: ms, price: price);

  List<num> toJson() => [ms, price];
}

/// Whether a position tool is marking a long or a short.
enum PositionSide { long, short }

/// One of the three levels of a position tool, in the order they are stacked
/// on a long.
enum PositionLevel { entry, target, stop }

/// How one object is drawn, and whether the finger may touch it.
///
/// Kept as a value of its own so it travels through every rebuild: a restyle
/// must not drop the geometry, and a drag must not drop the restyle. Null tint
/// or weight means "the chart style decides", so an object nobody restyled
/// still follows a theme change like every other one.
@immutable
class DrawingLook {
  const DrawingLook({
    this.tint,
    this.weight,
    this.dashed = false,
    this.locked = false,
    this.hidden = false,
    this.fill,
  });

  /// Colour of the stroke and its tags; null follows the chart style.
  final Color? tint;

  /// Stroke width in logical pixels; null follows the chart style.
  final double? weight;

  final bool dashed;

  /// Locked objects stay exactly where they were drawn: no drag, no handle.
  final bool locked;

  /// Hidden objects keep their place in the list and stop being painted, which
  /// is how a trader clears the chart without throwing the idea away.
  final bool hidden;

  /// How solidly a zone, a fib band or a label is filled, 0–100 percent.
  /// Null follows the chart's own restraint, so an untouched object stays quiet.
  final int? fill;

  bool get isDefault =>
      tint == null &&
      weight == null &&
      !dashed &&
      !locked &&
      !hidden &&
      fill == null;

  DrawingLook copyWith({
    Color? tint,
    double? weight,
    bool? dashed,
    bool? locked,
    bool? hidden,
    int? fill,
    bool clearTint = false,
    bool clearWeight = false,
    bool clearFill = false,
  }) {
    return DrawingLook(
      tint: clearTint ? null : (tint ?? this.tint),
      weight: clearWeight ? null : (weight ?? this.weight),
      dashed: dashed ?? this.dashed,
      locked: locked ?? this.locked,
      hidden: hidden ?? this.hidden,
      fill: clearFill ? null : (fill ?? this.fill),
    );
  }

  Map<String, Object?> toJson() => {
    if (tint != null) 'c': tint!.toARGB32(),
    if (weight != null) 'w': weight,
    if (dashed) 'd': true,
    if (locked) 'lk': true,
    if (hidden) 'hd': true,
    if (fill != null) 'f': fill,
  };

  static DrawingLook fromJson(Object? value) {
    if (value is! Map) return const DrawingLook();
    final rawTint = value['c'];
    final rawWeight = value['w'];
    final rawFill = value['f'];
    return DrawingLook(
      tint: rawTint is num ? Color(rawTint.toInt()) : null,
      weight: rawWeight is num ? rawWeight.toDouble() : null,
      dashed: value['d'] == true,
      locked: value['lk'] == true,
      hidden: value['hd'] == true,
      fill: rawFill is num ? rawFill.toInt().clamp(0, 100) : null,
    );
  }
}

/// A line the trader drew, anchored to candle **times** rather than indices, so
/// it survives a different window, a different candle size or a new session.
@immutable
class ChartDrawing {
  const ChartDrawing.trend({
    required this.startMs,
    required this.startPrice,
    required this.endMs,
    required this.endPrice,
    this.id,
    this.editedAtMs,
    this.look = const DrawingLook(),
  })  : kind = DrawingKind.trend,
        price = null,
        side = null,
        entry = null,
        stop = null,
        target = null,
        points = const [],
        text = null;

  const ChartDrawing.ray({
    required this.price,
    this.id,
    this.editedAtMs,
    this.look = const DrawingLook(),
  })  : kind = DrawingKind.ray,
        startMs = 0,
        startPrice = 0,
        endMs = 0,
        endPrice = 0,
        side = null,
        entry = null,
        stop = null,
        target = null,
        points = const [],
        text = null;

  /// One of the anchor-based objects: everything that is drawn from a list of
  /// points rather than from the three position levels.
  const ChartDrawing.points({
    required this.kind,
    required this.points,
    this.text,
    this.id,
    this.editedAtMs,
    this.look = const DrawingLook(),
  })  : startMs = 0,
        startPrice = 0,
        endMs = 0,
        endPrice = 0,
        price = null,
        side = null,
        entry = null,
        stop = null,
        target = null;

  /// A long or short position: one entry line, a stop and a target, with the
  /// profit and loss zones filled between them.
  ///
  /// The box covers [startMs] to [endMs] and stops there. It is deliberately
  /// not projected past its right edge: a calibration drawn over Friday's move
  /// is a record of that move, not a level stretched across next week's
  /// candles. Drag the right handle to widen it; zero means "no end stored yet"
  /// and the painter falls back to the newest candle.
  const ChartDrawing.position({
    required PositionSide this.side,
    required this.startMs,
    required double this.entry,
    required double this.stop,
    required double this.target,
    this.endMs = 0,
    this.id,
    this.editedAtMs,
    this.look = const DrawingLook(),
  })  : kind = DrawingKind.position,
        startPrice = 0,
        endPrice = 0,
        price = null,
        points = const [],
        text = null;

  final DrawingKind kind;

  /// The row in `chart_drawings` this object lives in, once it is shared.
  ///
  /// Objects drawn on the phone start without one; the first sync inserts the
  /// row and writes the id back. Every copy keeps it, which is what lets a drag
  /// update that row instead of deleting it and inserting a replacement.
  final String? id;

  /// When the trader last changed this object, in epoch milliseconds.
  ///
  /// This is the clock conflicts are settled by: if two devices hold different
  /// content for the same row, the later edit stands, even when it reaches the
  /// table second. A null value means the object has never been edited since it
  /// was loaded, so any remote edit is treated as the truth.
  final int? editedAtMs;

  /// First point of a trend line, or the left edge of a position box, as epoch
  /// milliseconds of the candle under it.
  final int startMs;
  final double startPrice;

  /// Second point of a trend line, or the right edge of a position box.
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

  /// Anchors of an anchor-based object, in drawing order.
  final List<ChartPoint> points;

  /// The words on a text label; null for every other drawing.
  final String? text;

  /// How this object is drawn and whether it can be touched.
  final DrawingLook look;

  /// The colour the painter uses: the object's own, else the chart's.
  Color get ink => look.tint ?? drawingColor;

  /// The same object restyled, geometry untouched.
  ChartDrawing withLook(DrawingLook next) {
    switch (kind) {
      case DrawingKind.trend:
        return ChartDrawing.trend(
          id: id,
          editedAtMs: editedAtMs,
          look: next,
          startMs: startMs,
          startPrice: startPrice,
          endMs: endMs,
          endPrice: endPrice,
        );
      case DrawingKind.ray:
        return ChartDrawing.ray(
          id: id,
          editedAtMs: editedAtMs,
          look: next,
          price: price ?? 0,
        );
      case DrawingKind.position:
        return ChartDrawing.position(
          id: id,
          editedAtMs: editedAtMs,
          look: next,
          side: side ?? PositionSide.long,
          startMs: startMs,
          endMs: endMs,
          entry: entry ?? 0,
          stop: stop ?? 0,
          target: target ?? 0,
        );
      default:
        return ChartDrawing.points(
          id: id,
          editedAtMs: editedAtMs,
          look: next,
          kind: kind,
          points: points,
          text: text,
        );
    }
  }

  /// True for the objects drawn from [points] rather than from levels.
  bool get isAnchored => points.isNotEmpty &&
      kind != DrawingKind.trend &&
      kind != DrawingKind.position;

  bool get isPosition => kind == DrawingKind.position;

  /// Kinds that paint a filled body, and so have something to make translucent.
  bool get hasFill =>
      kind == DrawingKind.rectangle ||
      kind == DrawingKind.ellipse ||
      kind == DrawingKind.text ||
      kind == DrawingKind.fib ||
      kind == DrawingKind.fibExtension ||
      kind == DrawingKind.position;

  /// Kinds that show words a trader can retype — the text tool's whole object.
  bool get carriesText => kind == DrawingKind.text;

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
      id: id,
      editedAtMs: editedAtMs,
      look: look,
      side: side ?? PositionSide.long,
      startMs: startMs,
      endMs: endMs,
      entry: level == PositionLevel.entry ? price : e,
      stop: level == PositionLevel.stop ? price : s,
      target: level == PositionLevel.target ? price : t,
    );
  }

  /// Replaces levels from the edit sheet. A missing value keeps the current one.
  ChartDrawing withLevels({
    double? entry,
    double? stop,
    double? target,
  }) {
    return ChartDrawing.position(
      id: id,
      editedAtMs: editedAtMs,
      look: look,
      side: side ?? PositionSide.long,
      startMs: startMs,
      endMs: endMs,
      entry: entry ?? this.entry ?? 0,
      stop: stop ?? this.stop ?? 0,
      target: target ?? this.target ?? 0,
    );
  }

  /// The same idea viewed the other way: entry stays, risk and reward swap
  /// sides but keep their distances. Flipping a long into a short must not
  /// silently turn a 2R setup into a 0.5R one.
  ChartDrawing withSide(PositionSide next) {
    if (!isPosition || (side ?? PositionSide.long) == next) return this;
    final e = entry ?? 0;
    final s = stop ?? 0;
    final t = target ?? 0;
    final risk = (e - s).abs();
    final reward = (t - e).abs();
    return ChartDrawing.position(
      id: id,
      editedAtMs: editedAtMs,
      look: look,
      side: next,
      startMs: startMs,
      endMs: endMs,
      entry: e,
      stop: next == PositionSide.long ? e - risk : e + risk,
      target: next == PositionSide.long ? e + reward : e - reward,
    );
  }

  /// Slides the position box's two time edges, leaving its prices alone.
  ///
  /// This is the position tool's half of the Coordinates tab: the levels are
  /// typed there, and the stretch of candles the box covers is picked there too.
  ChartDrawing withTimes({required int startMs, required int endMs}) {
    if (!isPosition) return this;
    return ChartDrawing.position(
      id: id,
      editedAtMs: editedAtMs,
      look: look,
      side: side ?? PositionSide.long,
      startMs: startMs,
      endMs: endMs < startMs ? startMs : endMs,
      entry: entry ?? 0,
      stop: stop ?? 0,
      target: target ?? 0,
    );
  }

  /// Moves the box's right edge, never before its left one.
  ChartDrawing withEnd(int ms) {
    if (!isPosition) return this;
    return ChartDrawing.position(
      id: id,
      editedAtMs: editedAtMs,
      look: look,
      side: side ?? PositionSide.long,
      startMs: startMs,
      endMs: ms < startMs ? startMs : ms,
      entry: entry ?? 0,
      stop: stop ?? 0,
      target: target ?? 0,
    );
  }

  ChartDrawing shifted({
    required double priceDelta,
    required int startMs,
    int endMs = 0,
  }) {
    final e = entry ?? 0;
    final s = stop ?? 0;
    final t = target ?? 0;
    final nextEnd = endMs == 0 ? this.endMs : endMs;
    return ChartDrawing.position(
      id: id,
      editedAtMs: editedAtMs,
      look: look,
      side: side ?? PositionSide.long,
      startMs: startMs,
      endMs: nextEnd < startMs ? startMs : nextEnd,
      entry: e + priceDelta,
      stop: s + priceDelta,
      target: t + priceDelta,
    );
  }

  /// Replaces one anchor and leaves every other point where it is.
  ///
  /// This is what makes a handle a handle. Grabbing the end of a fib ladder or
  /// one corner of a box adjusts that point alone, the way every desktop chart
  /// behaves; sliding the whole object is the fallback only when the finger
  /// landed on the body rather than on a dot.
  ChartDrawing withPoint(int index, ChartPoint point) {
    if (kind == DrawingKind.trend) {
      return ChartDrawing.trend(
        id: id,
        editedAtMs: editedAtMs,
        look: look,
        startMs: index == 0 ? point.ms : startMs,
        startPrice: index == 0 ? point.price : startPrice,
        endMs: index == 0 ? endMs : point.ms,
        endPrice: index == 0 ? endPrice : point.price,
      );
    }
    if (kind == DrawingKind.position || index < 0 || index >= points.length) {
      return this;
    }
    final next = [...points];
    next[index] = point;
    return ChartDrawing.points(
      id: id,
      editedAtMs: editedAtMs,
      look: look,
      kind: kind,
      points: next,
      text: text,
    );
  }

  /// The same object carrying `next` as its shared row id.
  ///
  /// Used when a row is inserted and its id comes back from the database, and
  /// when a local object matches a row that another device created: adopting the
  /// id is what makes the next drag an update rather than a fresh insert.
  ChartDrawing withId(String? next) {
    switch (kind) {
      case DrawingKind.trend:
        return ChartDrawing.trend(
          id: next,
          editedAtMs: editedAtMs,
          look: look,
          startMs: startMs,
          startPrice: startPrice,
          endMs: endMs,
          endPrice: endPrice,
        );
      case DrawingKind.ray:
        return ChartDrawing.ray(
          id: next,
          editedAtMs: editedAtMs,
          look: look,
          price: price ?? 0,
        );
      case DrawingKind.position:
        return ChartDrawing.position(
          id: next,
          editedAtMs: editedAtMs,
          look: look,
          side: side ?? PositionSide.long,
          startMs: startMs,
          endMs: endMs,
          entry: entry ?? 0,
          stop: stop ?? 0,
          target: target ?? 0,
        );
      default:
        return ChartDrawing.points(
          id: next,
          editedAtMs: editedAtMs,
          look: look,
          kind: kind,
          points: points,
          text: text,
        );
    }
  }

  /// The same object stamped with the moment the trader changed it.
  ///
  /// Stamped once per edit, centrally, so two devices can settle which version
  /// of a level is the later one instead of whichever reached the table last.
  ChartDrawing withEditedAt(int ms) {
    switch (kind) {
      case DrawingKind.trend:
        return ChartDrawing.trend(
          id: id,
          editedAtMs: ms,
          look: look,
          startMs: startMs,
          startPrice: startPrice,
          endMs: endMs,
          endPrice: endPrice,
        );
      case DrawingKind.ray:
        return ChartDrawing.ray(
          id: id,
          editedAtMs: ms,
          look: look,
          price: price ?? 0,
        );
      case DrawingKind.position:
        return ChartDrawing.position(
          id: id,
          editedAtMs: ms,
          look: look,
          side: side ?? PositionSide.long,
          startMs: startMs,
          endMs: endMs,
          entry: entry ?? 0,
          stop: stop ?? 0,
          target: target ?? 0,
        );
      default:
        return ChartDrawing.points(
          id: id,
          editedAtMs: ms,
          look: look,
          kind: kind,
          points: points,
          text: text,
        );
    }
  }

  Map<String, Object?> toJson() {
    switch (kind) {
      case DrawingKind.trend:
        return {
          if (id != null) 'id': id,
          if (editedAtMs != null) 'ea': editedAtMs,
          if (!look.isDefault) 'lk': look.toJson(),
          'k': kind.name,
          'st': startMs,
          'sp': startPrice,
          'et': endMs,
          'ep': endPrice,
        };
      case DrawingKind.ray:
        return {
          if (id != null) 'id': id,
          if (editedAtMs != null) 'ea': editedAtMs,
          if (!look.isDefault) 'lk': look.toJson(),
          'k': kind.name,
          'p': price,
        };
      case DrawingKind.position:
        return {
          if (id != null) 'id': id,
          if (editedAtMs != null) 'ea': editedAtMs,
          if (!look.isDefault) 'lk': look.toJson(),
          'k': kind.name,
          'side': side?.name,
          'st': startMs,
          'et': endMs,
          'e': entry,
          'sl': stop,
          'tp': target,
        };
      default:
        return {
          if (id != null) 'id': id,
          if (editedAtMs != null) 'ea': editedAtMs,
          if (!look.isDefault) 'lk': look.toJson(),
          'k': kind.name,
          'pts': [for (final point in points) point.toJson()],
          if (text != null) 'txt': text,
        };
    }
  }

  /// Moves an anchor-based object: prices follow the finger, times follow the
  /// horizontal drag. `shiftTime` keeps the mapping inside the screen, which is
  /// the only place that knows what index a finger is over.
  ChartDrawing translated({
    required int Function(int ms) shiftTime,
    required double priceDelta,
  }) {
    return ChartDrawing.points(
      id: id,
      editedAtMs: editedAtMs,
      look: look,
      kind: kind,
      text: text,
      points: [
        for (final point in points)
          ChartPoint(
            ms: shiftTime(point.ms),
            price: point.price + priceDelta,
          ),
      ],
    );
  }

  /// Null for anything unreadable, so one corrupt entry cannot drop the rest.
  static ChartDrawing? fromJson(Object? value) {
    if (value is! Map) return null;
    final rawId = value['id'];
    final id = rawId is String && rawId.isNotEmpty ? rawId : null;
    final rawEdit = value['ea'];
    final editedAtMs = rawEdit is num ? rawEdit.toInt() : null;
    final look = DrawingLook.fromJson(value['lk']);
    final kind = value['k'];
    if (kind == DrawingKind.trend.name) {
      final st = value['st'];
      final sp = value['sp'];
      final et = value['et'];
      final ep = value['ep'];
      if (st is! num || sp is! num || et is! num || ep is! num) return null;
      return ChartDrawing.trend(
        id: id,
        editedAtMs: editedAtMs,
        look: look,
        startMs: st.toInt(),
        startPrice: sp.toDouble(),
        endMs: et.toInt(),
        endPrice: ep.toDouble(),
      );
    }
    if (kind == DrawingKind.ray.name) {
      final price = value['p'];
      if (price is! num) return null;
      return ChartDrawing.ray(
        id: id,
        editedAtMs: editedAtMs,
        look: look,
        price: price.toDouble(),
      );
    }
    if (kind == DrawingKind.position.name) {
      final st = value['st'];
      final e = value['e'];
      final sl = value['sl'];
      final tp = value['tp'];
      final side = value['side'];
      final et = value['et'];
      if (st is! num || e is! num || sl is! num || tp is! num) return null;
      return ChartDrawing.position(
        id: id,
        editedAtMs: editedAtMs,
        look: look,
        side: side == PositionSide.short.name
            ? PositionSide.short
            : PositionSide.long,
        startMs: st.toInt(),
        endMs: et is num ? et.toInt() : 0,
        entry: e.toDouble(),
        stop: sl.toDouble(),
        target: tp.toDouble(),
      );
    }

    // Anchor-based objects share one shape on disk: the kind name plus its
    // points. An unknown kind is dropped, so a newer build's tool cannot break
    // an older one.
    DrawingKind? parsed;
    for (final candidate in DrawingKind.values) {
      if (candidate.name == kind) parsed = candidate;
    }
    if (parsed == null ||
        parsed == DrawingKind.trend ||
        parsed == DrawingKind.ray ||
        parsed == DrawingKind.position) {
      return null;
    }
    final raw = value['pts'];
    if (raw is! List) return null;
    final parsedPoints = <ChartPoint>[];
    for (final entry in raw) {
      if (entry is! List || entry.length < 2) continue;
      final ms = entry[0];
      final price = entry[1];
      if (ms is! num || price is! num) continue;
      parsedPoints.add(
        ChartPoint(ms: ms.toInt(), price: price.toDouble()),
      );
    }
    if (parsedPoints.isEmpty) return null;
    final label = value['txt'];
    return ChartDrawing.points(
      id: id,
      editedAtMs: editedAtMs,
      look: look,
      kind: parsed,
      points: parsedPoints,
      text: label is String ? label : null,
    );
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

  // Only the candles the box covers can decide the outcome: an exit after its
  // right edge belongs to a later idea, not to this calibration.
  final window = drawing.endMs <= 0
      ? candles
      : [
          for (final candle in candles)
            if (candle.time.millisecondsSinceEpoch <= drawing.endMs) candle,
        ];

  final outcome = resolveExit(
    type: drawing.side == PositionSide.short ? 'SELL' : 'BUY',
    entry: entry,
    stop: stop,
    take: target,
    entryTime:
        DateTime.fromMillisecondsSinceEpoch(drawing.startMs, isUtc: true),
    candles: window,
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
