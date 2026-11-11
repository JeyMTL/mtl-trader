import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/chart_drawings.dart';
import '../../core/chart_scale.dart';
import '../../core/chart_sessions.dart';
import '../../core/chart_theme.dart';
import '../../core/indicators.dart';
import '../../core/trade_exit.dart' show ResolvedExit;
import '../../services/market_data.dart';
import '../theme.dart';
import 'chart_marker.dart';

class TradingChartPainter extends CustomPainter {
  TradingChartPainter({
    required this.candles,
    required this.start,
    required this.span,
    required this.minPrice,
    required this.maxPrice,
    required this.entry,
    required this.exit,
    required this.stop,
    required this.take,
    required this.entryTime,
    required this.exitTime,
    required this.crosshair,
    required this.dragging,
    required this.decimals,
    required this.interval,
    required this.chartType,
    required this.studies,
    required this.drawings,
    required this.draftStart,
    required this.style,
    required this.symbol,
    required this.selectedDrawing,
    required this.positionOutcomes,
  });

  static const double height = 380;
  static const double axisWidth = 58;
  static const double topPad = 10;
  static const double bottomPad = 20;
  static const double paneGap = 8;

  /// Vertical layout of the price pane plus the optional volume and oscillator
  /// panes. Shares always add up to 1, so the panes fill the canvas exactly.
  static ({
    double priceTop,
    double priceH,
    double volumeTop,
    double volumeH,
    double oscTop,
    double oscH,
  }) paneLayout(double height, ChartStyle style) {
    final hasVolume = style.showVolume;
    final hasOscillator = style.oscillator != Oscillator.none;
    final total = height - topPad - bottomPad;
    final gaps = (hasVolume ? paneGap : 0.0) + (hasOscillator ? paneGap : 0.0);
    final usable = math.max(0.0, total - gaps);
    var priceShare = 1.0;
    if (hasVolume && hasOscillator) {
      priceShare = 0.58;
    } else if (hasVolume || hasOscillator) {
      priceShare = 0.76;
    }
    final priceH = usable * priceShare;
    var volumeTop = 0.0;
    var volumeH = 0.0;
    var oscTop = 0.0;
    var oscH = 0.0;
    var cursor = topPad + priceH;
    if (hasVolume) {
      volumeTop = cursor + paneGap;
      volumeH = usable * (hasOscillator ? 0.16 : 0.24);
      cursor = volumeTop + volumeH;
    }
    if (hasOscillator) {
      oscTop = cursor + paneGap;
      oscH = usable * 0.26;
    }
    return (
      priceTop: topPad,
      priceH: priceH,
      volumeTop: volumeTop,
      volumeH: volumeH,
      oscTop: oscTop,
      oscH: oscH,
    );
  }

  final List<Candle> candles;
  final double start;
  final double span;
  final double minPrice;
  final double maxPrice;
  final double? entry;
  final double? exit;
  final double? stop;
  final double? take;
  final DateTime? entryTime;
  final DateTime? exitTime;
  final Offset? crosshair;
  final Marker? dragging;
  final int decimals;
  final ChartInterval interval;
  final ChartType chartType;
  final Map<OverlayStudy, List<double?>> studies;
  final List<ChartDrawing> drawings;
  final DrawingDraft? draftStart;
  final ChartStyle style;
  final String symbol;
  final int? selectedDrawing;

  /// Where each position tool was taken out of its zones, aligned with
  /// [drawings]; null for every other kind of drawing and for an open idea.
  final List<ResolvedExit?> positionOutcomes;

  /// Nearest candle x for an epoch-millisecond time, or null when the drawing
  /// sits outside the loaded series (then it is simply not drawn).
  double? _xForTime(int ms, double plotW) {
    if (candles.isEmpty) return null;
    final first = candles.first.time.millisecondsSinceEpoch;
    final last = candles.last.time.millisecondsSinceEpoch;
    if (ms < first || ms > last) return null;
    var low = 0;
    var high = candles.length - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (candles[mid].time.millisecondsSinceEpoch < ms) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return ((low + 0.5 - start) / span) * plotW;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = style.background);
    final plotW = size.width - axisWidth;
    final panes = paneLayout(size.height, style);
    final plotH = panes.priceH;
    if (candles.isEmpty || plotW <= 0 || plotH <= 0) return;

    if (style.showWatermark) _watermark(canvas, plotW, plotH);

    double y(double price) =>
        panes.priceTop +
        ratioForPrice(
              price: price,
              min: minPrice,
              max: maxPrice,
              logScale: style.logScale,
            ) *
            plotH;
    double x(double index) => ((index + 0.5 - start) / span) * plotW;

    final grid = Paint()
      ..color = style.grid
      ..strokeWidth = 0.6;
    for (var i = 0; i <= 4; i++) {
      final gy = topPad + plotH * i / 4;
      if (style.showGrid) {
        canvas.drawLine(Offset(0, gy), Offset(plotW, gy), grid);
      }
      final price = priceForRatio(
        ratio: i / 4,
        min: minPrice,
        max: maxPrice,
        logScale: style.logScale,
      );
      _label(
        canvas,
        price.toStringAsFixed(decimals),
        Offset(plotW + 6, gy - 5),
        color: style.muted,
        size: 8.5,
      );
    }
    final step = math.max(1, (span / 5).round());
    final firstGrid = (start / step).floor() * step;
    for (var i = firstGrid; i <= start + span; i += step) {
      if (i < 0 || i >= candles.length) continue;
      final gx = x(i.toDouble());
      if (gx < 0 || gx > plotW) continue;
      if (style.showGrid) {
        canvas.drawLine(Offset(gx, topPad), Offset(gx, topPad + plotH), grid);
      }
    }

    // Everything below is bounded to the candles that can be seen. A pan
    // repaints at pointer rate, and walking the whole 5,000-candle series once
    // per session per frame is what turns a drag into a slideshow. One candle
    // of padding keeps a band that started just off-screen from being redrawn
    // from the window edge (the canvas clips that sliver anyway).
    final from = (start.floor() - 1).clamp(0, candles.length - 1);
    final to = (start + span).ceil().clamp(from, candles.length - 1);
    final visibleTimes = <DateTime>[
      for (var i = from; i <= to; i++) candles[i].time,
    ];

    // Session shading sits behind the candles: a translucent band per enabled
    // session, so price action is never hidden by the context it traded in.
    // Band edges come from UTC hours, which is why London starts at 07:00 no
    // matter what the phone's clock says.
    if (style.showSessions) {
      for (final session in TradingSession.values) {
        if (!style.sessions.contains(session)) continue;
        for (final band in sessionBands(visibleTimes, session)) {
          final left = ((band.firstIndex + from - start) / span) * plotW;
          final right = ((band.lastIndex + 1 + from - start) / span) * plotW;
          if (right < 0 || left > plotW) continue;
          final rect = Rect.fromLTRB(
            math.max(0.0, left),
            topPad,
            math.min(plotW, right),
            topPad + plotH,
          );
          if (rect.width < 0.5) continue;
          canvas.drawRect(
            rect,
            Paint()..color = session.tint.withAlpha(style.isLight ? 18 : 26),
          );
          // Only label a band wide enough to hold the word, or a zoomed-out
          // chart turns into a wall of overlapping text.
          if (rect.width >= 42) {
            _label(
              canvas,
              session.label,
              Offset(rect.left + 3, topPad + 2),
              color: session.tint.withAlpha(style.isLight ? 200 : 165),
              size: 8,
            );
          }
          // The break line is drawn after the band so the tint cannot swallow
          // it: the line is the precise moment the session opened, the band is
          // only the stretch of time around it.
          if (style.showSessionBreaks && band.firstIndex + from > 0) {
            final bx = ((band.firstIndex + from - start) / span) * plotW;
            if (bx > 0 && bx < plotW) {
              _dashed(
                canvas,
                Offset(bx, topPad),
                Offset(bx, topPad + plotH),
                session.tint.withAlpha(style.isLight ? 130 : 160),
              );
            }
          }
        }
      }
    }

    // Period separators: one dashed line where a new day, week or month opens.
    if (style.showSeparators) {
      for (final index in periodSeparatorIndices(
        visibleTimes,
        style.separatorGrain,
      )) {
        final gx = ((index + from - start) / span) * plotW;
        if (gx < 0 || gx > plotW) continue;
        _dashed(
          canvas,
          Offset(gx, topPad),
          Offset(gx, topPad + plotH),
          style.muted.withAlpha(95),
        );
      }
    }

    final slot = plotW / span;
    final bodyWidth = math.max(1.2, slot * 0.66);
    if (chartType == ChartType.candles) {
      for (var i = from; i <= to; i++) {
        final candle = candles[i];
        final cx = x(i.toDouble());
        if (cx < -slot || cx > plotW + slot) continue;
        final color = candle.isUp ? style.bull : style.bear;
        canvas.drawLine(
          Offset(cx, y(candle.high)),
          Offset(cx, y(candle.low)),
          Paint()
            ..color = color
            ..strokeWidth = 1,
        );
        final openY = y(candle.open);
        final closeY = y(candle.close);
        final body = Rect.fromLTRB(
          cx - bodyWidth / 2,
          math.min(openY, closeY),
          cx + bodyWidth / 2,
          math.max(openY, closeY) + 0.8,
        );
        // Opaque, like a TradingView body: the black/green scheme reads as
        // solid black rather than a grey that lets the session tint through.
        canvas.drawRect(body, Paint()..color = color);
      }
    } else {
      final line = Path();
      var started = false;
      for (var i = from; i <= to; i++) {
        final cx = x(i.toDouble());
        if (cx < -slot || cx > plotW + slot) continue;
        final cy = y(candles[i].close);
        if (!started) {
          line.moveTo(cx, cy);
          started = true;
        } else {
          line.lineTo(cx, cy);
        }
      }
      if (started) {
        if (chartType == ChartType.area) {
          final bounds = line.getBounds();
          final fill = Path.from(line)
            ..lineTo(bounds.right, topPad + plotH)
            ..lineTo(bounds.left, topPad + plotH)
            ..close();
          canvas.drawPath(
            fill,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [style.bull.withAlpha(70), style.bull.withAlpha(0)],
              ).createShader(Rect.fromLTWH(0, topPad, plotW, plotH)),
          );
        }
        canvas.drawPath(
          line,
          Paint()
            ..color = style.text.withAlpha(230)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }
    }

    // Moving averages sit on top of whichever series is drawn.
    for (final entry in studies.entries) {
      final paint = Paint()
        ..color = entry.key.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3;
      final series = entry.value;
      Path? run;
      for (var i = from; i <= to && i < series.length; i++) {
        final value = series[i];
        final px = x(i.toDouble());
        if (value == null || px < -slot || px > plotW + slot) {
          if (run != null) {
            canvas.drawPath(run, paint);
            run = null;
          }
          continue;
        }
        final py = y(value);
        if (run == null) {
          run = Path()..moveTo(px, py);
        } else {
          run.lineTo(px, py);
        }
      }
      if (run != null) canvas.drawPath(run, paint);
    }

    // Volume pane: bars scaled to the busiest visible bar.
    if (panes.volumeH > 6) {
      final bottom = panes.volumeTop + panes.volumeH;
      final firstVisible = start.floor().clamp(0, candles.length - 1);
      final lastVisible =
          (start + span).ceil().clamp(firstVisible + 1, candles.length);
      var maxVolume = 0.0;
      for (var i = firstVisible; i < lastVisible; i++) {
        maxVolume = math.max(maxVolume, candles[i].volume);
      }
      canvas.drawLine(
        Offset(0, panes.volumeTop),
        Offset(plotW, panes.volumeTop),
        Paint()
          ..color = style.axis
          ..strokeWidth = 0.6,
      );
      _label(
        canvas,
        'VOL',
        Offset(4, panes.volumeTop + 2),
        color: style.muted,
        size: 8,
      );
      if (maxVolume > 0) {
        for (var i = from; i <= to; i++) {
          final cx = x(i.toDouble());
          if (cx < -slot || cx > plotW + slot) continue;
          final height = candles[i].volume / maxVolume * (panes.volumeH - 12);
          if (height <= 0) continue;
          final color = candles[i].isUp ? style.bull : style.bear;
          canvas.drawRect(
            Rect.fromLTRB(
              cx - bodyWidth / 2,
              bottom - height,
              cx + bodyWidth / 2,
              bottom,
            ),
            Paint()..color = color.withAlpha(110),
          );
        }
      }
    }

    // Oscillator pane: RSI with its 30/70 guides, or MACD with histogram.
    if (panes.oscH > 6) {
      final paneTop = panes.oscTop;
      final paneBottom = paneTop + panes.oscH;
      final closes = _oscillatorCloses();
      canvas.drawLine(
        Offset(0, paneTop),
        Offset(plotW, paneTop),
        Paint()
          ..color = style.axis
          ..strokeWidth = 0.6,
      );
      if (style.oscillator == Oscillator.rsi) {
        final series = _rsiSeries(closes, style.rsiPeriod.clamp(2, 100));
        double oy(double value) =>
            paneBottom - (value.clamp(0, 100) / 100) * (panes.oscH - 10) - 4;
        for (final level in const [30.0, 70.0]) {
          final gy = oy(level);
          _dashed(canvas, Offset(0, gy), Offset(plotW, gy), style.grid);
          _label(
            canvas,
            level.toStringAsFixed(0),
            Offset(plotW + 6, gy - 5),
            color: style.muted,
            size: 8,
          );
        }
        _label(
          canvas,
          'RSI ${style.rsiPeriod}',
          Offset(4, paneTop + 2),
          color: style.muted,
          size: 8,
        );
        final paint = Paint()
          ..color = const Color(0xFF9C8CFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        Path? run;
        for (var i = from; i <= to && i < series.length; i++) {
          final value = series[i];
          final px = x(i.toDouble());
          if (value == null || px < -slot || px > plotW + slot) {
            if (run != null) {
              canvas.drawPath(run, paint);
              run = null;
            }
            continue;
          }
          final py = oy(value);
          if (run == null) {
            run = Path()..moveTo(px, py);
          } else {
            run.lineTo(px, py);
          }
        }
        if (run != null) canvas.drawPath(run, paint);
      } else if (style.oscillator == Oscillator.macd) {
        final macdResult = _macdSeries(
          closes,
          style.macdFast.clamp(2, 100),
          style.macdSlow.clamp(3, 200),
          style.macdSignal.clamp(2, 100),
        );
        final points = macdResult.points;
        final maxAbs = macdResult.maxAbs;
        double oy(double value) =>
            paneBottom -
            (value + maxAbs) / (2 * maxAbs) * (panes.oscH - 10) -
            4;
        _dashed(canvas, Offset(0, oy(0)), Offset(plotW, oy(0)), style.grid);
        _label(
          canvas,
          'MACD ${style.macdFast},${style.macdSlow},${style.macdSignal}',
          Offset(4, paneTop + 2),
          color: style.muted,
          size: 8,
        );
        for (var i = from; i <= to && i < points.length; i++) {
          final point = points[i];
          if (point == null) continue;
          final cx = x(i.toDouble());
          if (cx < -slot || cx > plotW + slot) continue;
          final zero = oy(0);
          final value = oy(point.histogram);
          canvas.drawRect(
            Rect.fromLTRB(
              cx - bodyWidth / 2,
              math.min(zero, value),
              cx + bodyWidth / 2,
              math.max(zero, value),
            ),
            Paint()
              ..color = (point.histogram >= 0 ? style.bull : style.bear)
                  .withAlpha(120),
          );
        }
        void line(Paint paint, double Function(MacdPoint) pick) {
          Path? run;
          for (var i = from; i <= to && i < points.length; i++) {
            final point = points[i];
            final px = x(i.toDouble());
            if (point == null || px < -slot || px > plotW + slot) {
              if (run != null) {
                canvas.drawPath(run, paint);
                run = null;
              }
              continue;
            }
            final py = oy(pick(point));
            if (run == null) {
              run = Path()..moveTo(px, py);
            } else {
              run.lineTo(px, py);
            }
          }
          if (run != null) canvas.drawPath(run, paint);
        }

        line(
          Paint()
            ..color = const Color(0xFF4C9AFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
          (point) => point.macd,
        );
        line(
          Paint()
            ..color = const Color(0xFFFF8A5C)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
          (point) => point.signal,
        );
      }
    }

    // Trader drawings, then the half-finished trend line if one is in progress.
    for (var d = 0; d < drawings.length; d++) {
      final drawing = drawings[d];
      final selected = d == selectedDrawing;
      final paint = Paint()
        ..color = drawingColor
        ..strokeWidth = selected ? 2.4 : 1.3
        ..style = PaintingStyle.stroke;
      if (drawing.kind == DrawingKind.ray) {
        final price = drawing.price;
        if (price == null) continue;
        final ly = y(price);
        if (ly < panes.priceTop || ly > panes.priceTop + plotH) continue;
        canvas.drawLine(Offset(0, ly), Offset(plotW, ly), paint);
        if (selected) {
          canvas.drawCircle(
            Offset(plotW / 2, ly),
            4,
            Paint()..color = drawingColor,
          );
        }
      } else if (drawing.kind == DrawingKind.position) {
        _paintPosition(
          canvas,
          drawing,
          selected: selected,
          outcome: d < positionOutcomes.length ? positionOutcomes[d] : null,
          size: size,
          plotW: plotW,
          priceTop: panes.priceTop,
          plotH: plotH,
          y: y,
        );
      } else {
        final x1 = _xForTime(drawing.startMs, plotW);
        final x2 = _xForTime(drawing.endMs, plotW);
        if (x1 == null || x2 == null) continue;
        final p1 = Offset(x1, y(drawing.startPrice));
        final p2 = Offset(x2, y(drawing.endPrice));
        canvas.drawLine(p1, p2, paint);
        final handle = selected ? 4.0 : 2.5;
        canvas.drawCircle(p1, handle, Paint()..color = drawingColor);
        canvas.drawCircle(p2, handle, Paint()..color = drawingColor);
      }
    }
    final draft = draftStart;
    final draftX = draft == null ? null : _xForTime(draft.timeMs, plotW);
    if (draft != null && draftX != null && crosshair != null) {
      _dashed(
        canvas,
        Offset(draftX, y(draft.price)),
        crosshair!,
        drawingColor,
      );
    }

    final last = candles.last;
    final lastY = y(last.close);
    if (lastY >= topPad && lastY <= topPad + plotH) {
      final color = last.isUp ? style.bull : style.bear;
      _dashed(
        canvas,
        Offset(0, lastY),
        Offset(plotW, lastY),
        color.withAlpha(150),
      );
      _axisTag(
        canvas,
        size,
        plotW,
        lastY,
        last.close.toStringAsFixed(decimals),
        color,
      );
    }

    for (final time in [entryTime, exitTime]) {
      if (time == null) continue;
      final index = _nearestIndex(time);
      if (index == null) continue;
      final tx = x(index.toDouble());
      if (tx < 0 || tx > plotW) continue;
      _dashed(
        canvas,
        Offset(tx, topPad),
        Offset(tx, topPad + plotH),
        style.axis,
      );
    }

    final levels = <(Marker, double?, Color, String)>[
      (Marker.entry, entry, AppColors.primary, 'E'),
      (Marker.stop, stop, AppColors.danger, 'SL'),
      (Marker.take, take, AppColors.success, 'TP'),
      (Marker.exit, exit, AppColors.muted, 'X'),
    ];
    for (final (marker, price, color, label) in levels) {
      if (price == null) continue;
      final ly = y(price);
      if (ly < topPad - 2 || ly > topPad + plotH + 2) continue;
      final active = dragging == marker;
      canvas.drawLine(
        Offset(0, ly),
        Offset(plotW, ly),
        Paint()
          ..color = color.withAlpha(active ? 255 : 220)
          ..strokeWidth = active ? 2 : 1,
      );
      if (active) {
        canvas.drawCircle(
          Offset(plotW - 4, ly),
          4,
          Paint()
            ..color = color
            ..style = PaintingStyle.fill,
        );
      }
      _chip(
        canvas,
        '$label ${price.toStringAsFixed(decimals)}',
        Offset(4, ly - 7),
        color,
      );
      _axisTag(
        canvas,
        size,
        plotW,
        ly,
        price.toStringAsFixed(decimals),
        color,
      );
    }

    canvas.drawLine(
      Offset(plotW, 0),
      Offset(plotW, size.height),
      Paint()
        ..color = style.axis
        ..strokeWidth = 0.8,
    );

    final pointer = crosshair;
    if (style.showCrosshair &&
        pointer != null &&
        pointer.dx >= 0 &&
        pointer.dx <= plotW &&
        pointer.dy >= topPad &&
        pointer.dy <= topPad + plotH) {
      _dashed(
        canvas,
        Offset(pointer.dx, topPad),
        Offset(pointer.dx, size.height - bottomPad),
        style.crosshair,
      );
      _dashed(
        canvas,
        Offset(0, pointer.dy),
        Offset(plotW, pointer.dy),
        style.crosshair,
      );
      final price = priceForRatio(
        ratio: (pointer.dy - topPad) / plotH,
        min: minPrice,
        max: maxPrice,
        logScale: style.logScale,
      );
      _axisTag(
        canvas,
        size,
        plotW,
        pointer.dy,
        price.toStringAsFixed(decimals),
        style.text,
      );

      final ratio = (pointer.dx / plotW).clamp(0.0, 1.0).toDouble();
      final index =
          (start + ratio * span).floor().clamp(0, candles.length - 1).toInt();
      final time = candles[index].time.toLocal();
      final text = interval.size < const Duration(days: 1)
          ? DateFormat('HH:mm').format(time)
          : DateFormat('d MMM').format(time);
      _bottomTag(canvas, size, pointer.dx, text);
    }

    final picks = <double>[start, start + span / 2, start + span - 1];
    for (final raw in picks) {
      final index = raw.floor().clamp(0, candles.length - 1);
      final time = candles[index].time.toLocal();
      final text = interval.size < const Duration(days: 1)
          ? DateFormat('HH:mm').format(time)
          : DateFormat('d MMM').format(time);
      final painter = _painter(text, color: style.muted, size: 8.5);
      final cx = x(index.toDouble())
          .clamp(0.0, math.max(0.0, plotW - painter.width))
          .toDouble();
      painter.paint(canvas, Offset(cx, size.height - bottomPad + 4));
    }
  }

  void _watermark(Canvas canvas, double plotW, double plotH) {
    final painter = _painter(
      symbol,
      color: style.muted.withAlpha(style.isLight ? 22 : 30),
      size: math.min(72, math.max(28, plotW * 0.2)),
      weight: FontWeight.w800,
    );
    painter.paint(
      canvas,
      Offset(
        plotW / 2 - painter.width / 2,
        topPad + plotH / 2 - painter.height / 2,
      ),
    );
  }

  int? _nearestIndex(DateTime time) {
    final utc = time.toUtc().millisecondsSinceEpoch;
    int? best;
    var bestDelta = double.infinity;
    for (var i = 0; i < candles.length; i++) {
      final delta =
          (candles[i].time.millisecondsSinceEpoch - utc).abs().toDouble();
      if (delta < bestDelta) {
        bestDelta = delta;
        best = i;
      }
    }
    return best;
  }

  void _axisTag(
    Canvas canvas,
    Size size,
    double plotW,
    double cy,
    String text,
    Color color, {
    Color? textColor,
  }) {
    final painter = _painter(
      text,
      color: textColor ?? style.background,
      size: 8.5,
      weight: FontWeight.w700,
    );
    final rect = Rect.fromLTWH(plotW + 2, cy - 7, axisWidth - 4, 14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = color,
    );
    painter.paint(
      canvas,
      Offset(
        rect.center.dx - painter.width / 2,
        rect.center.dy - painter.height / 2,
      ),
    );
  }

  /// TradingView's long/short position: a profit zone between entry and target,
  /// the mirrored loss zone between entry and stop, three level lines and one
  /// price badge per level on the axis.
  void _paintPosition(
    Canvas canvas,
    ChartDrawing drawing, {
    required bool selected,
    required ResolvedExit? outcome,
    required Size size,
    required double plotW,
    required double priceTop,
    required double plotH,
    required double Function(double price) y,
  }) {
    final entry = drawing.entry;
    final stop = drawing.stop;
    final target = drawing.target;
    if (entry == null || stop == null || target == null) return;

    final firstMs = candles.first.time.millisecondsSinceEpoch;
    double left;
    final found = _xForTime(drawing.startMs, plotW);
    if (found != null) {
      left = found;
    } else if (drawing.startMs < firstMs) {
      // The anchor scrolled off the left edge: keep drawing from the edge so a
      // position placed yesterday still guards the setup being watched today.
      left = 0;
    } else {
      return;
    }
    final right = plotW;
    if (right - left < 1) return;

    final entryY = y(entry);
    final stopY = y(stop);
    final targetY = y(target);

    // Zones are clipped to the price pane: a level dragged past the top of the
    // chart must not paint its tint across the volume bars.
    Rect? zone(double a, double b) {
      final top = math.max(priceTop, math.min(a, b));
      final bottom = math.min(priceTop + plotH, math.max(a, b));
      if (bottom - top < 0.5) return null;
      return Rect.fromLTRB(left, top, right, bottom);
    }

    final profitZone = zone(entryY, targetY);
    if (profitZone != null) {
      canvas.drawRect(
        profitZone,
        Paint()..color = positionProfitColor.withAlpha(style.isLight ? 34 : 46),
      );
    }
    final lossZone = zone(entryY, stopY);
    if (lossZone != null) {
      canvas.drawRect(
        lossZone,
        Paint()..color = positionLossColor.withAlpha(style.isLight ? 28 : 40),
      );
    }
    final outline = zone(stopY, targetY);
    if (outline != null) {
      canvas.drawRect(
        outline,
        Paint()
          ..color = positionEntryColor.withAlpha(selected ? 190 : 90)
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 1.4 : 0.9,
      );
    }

    void level(double priceY, Color color) {
      if (priceY < priceTop || priceY > priceTop + plotH) return;
      canvas.drawLine(
        Offset(left, priceY),
        Offset(right, priceY),
        Paint()
          ..color = color.withAlpha(selected ? 255 : 215)
          ..strokeWidth = selected ? 1.7 : 1.1,
      );
    }

    level(stopY, positionLossColor);
    level(targetY, positionProfitColor);
    // The entry line follows the chart's text colour, as TradingView's does.
    level(entryY, style.text.withAlpha(200));

    void tag(double priceY, double price, Color color) {
      if (priceY < priceTop - 8 || priceY > priceTop + plotH + 8) return;
      _axisTag(
        canvas,
        size,
        plotW,
        priceY,
        price.toStringAsFixed(decimals),
        color,
        textColor: const Color(0xFFFFFFFF),
      );
    }

    tag(stopY, stop, positionLossColor);
    tag(targetY, target, positionProfitColor);
    tag(entryY, entry, positionEntryColor);

    // The exit: the candle whose range left a zone vertically, marked with the
    // price it crossed and the result in risk units.
    if (outcome != null) {
      final exitX = _xForTime(outcome.time.millisecondsSinceEpoch, plotW);
      final exitY = y(outcome.price);
      if (exitX != null &&
          exitX >= left &&
          exitY >= priceTop &&
          exitY <= priceTop + plotH) {
        final color =
            outcome.isTakeProfit ? positionProfitColor : positionLossColor;
        _dashed(
          canvas,
          Offset(exitX, entryY),
          Offset(exitX, exitY),
          color.withAlpha(180),
        );
        canvas.drawCircle(
          Offset(exitX, exitY),
          6,
          Paint()..color = color.withAlpha(70),
        );
        canvas.drawCircle(Offset(exitX, exitY), 3.5, Paint()..color = color);

        final r = realisedR(drawing: drawing, exit: outcome);
        final label = '${outcome.isTakeProfit ? 'TP' : 'SL'} '
            '${outcome.price.toStringAsFixed(decimals)}'
            '${r == null ? '' : ' · ${r >= 0 ? '+' : ''}${r.toStringAsFixed(1)}R'}';
        final textWidth =
            _painter(label, color: color, size: 8.5, weight: FontWeight.w700)
                .width;
        final chipX = (exitX + 6)
            .clamp(0.0, math.max(0.0, plotW - textWidth - 6))
            .toDouble();
        _chip(canvas, label, Offset(chipX, exitY - 18), color);
      }
    }

    if (!selected) return;
    for (final handle in <(double, Color)>[
      (entryY, positionEntryColor),
      (stopY, positionLossColor),
      (targetY, positionProfitColor),
    ]) {
      if (handle.$1 < priceTop || handle.$1 > priceTop + plotH) continue;
      final center = Offset(right - 5, handle.$1);
      canvas.drawCircle(center, 4.5, Paint()..color = handle.$2);
      canvas.drawCircle(
        center,
        4.5,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  void _bottomTag(Canvas canvas, Size size, double cx, String text) {
    final painter = _painter(
      text,
      color: style.text,
      size: 8.5,
      weight: FontWeight.w600,
    );
    final width = painter.width + 10;
    final left = (cx - width / 2)
        .clamp(0.0, math.max(0.0, size.width - axisWidth - width))
        .toDouble();
    final rect = Rect.fromLTWH(left, size.height - bottomPad + 3, width, 14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = style.axis,
    );
    painter.paint(
      canvas,
      Offset(
        rect.center.dx - painter.width / 2,
        rect.center.dy - painter.height / 2,
      ),
    );
  }

  void _chip(Canvas canvas, String text, Offset offset, Color color) {
    final painter = _painter(
      text,
      color: color,
      size: 8.5,
      weight: FontWeight.w700,
    );
    final rect = Rect.fromLTWH(offset.dx, offset.dy, painter.width + 6, 13);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = style.background.withAlpha(215),
    );
    painter.paint(canvas, Offset(offset.dx + 3, offset.dy + 1.5));
  }

  void _dashed(Canvas canvas, Offset from, Offset to, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0;
    const gap = 3.0;
    if ((from.dx - to.dx).abs() < 0.01) {
      var point = from.dy;
      while (point < to.dy) {
        final end = math.min(point + dash, to.dy);
        canvas.drawLine(Offset(from.dx, point), Offset(from.dx, end), paint);
        point = end + gap;
      }
    } else {
      var point = from.dx;
      while (point < to.dx) {
        final end = math.min(point + dash, to.dx);
        canvas.drawLine(Offset(point, from.dy), Offset(end, from.dy), paint);
        point = end + gap;
      }
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset offset, {
    required Color color,
    required double size,
  }) {
    _painter(text, color: color, size: size).paint(canvas, offset);
  }

  /// Laid-out label painters, kept across frames.
  ///
  /// Shaping text costs more than painting ninety candles: every axis tick was
  /// built and laid out again on every frame of a pan, sixty times a second.
  /// The same handful of strings repeats ("1.08452", "VOL", "RSI 14"), so one
  /// painter per text/colour/size/weight is reused instead. The cache is static
  /// because this painter is rebuilt for each frame — an instance field would be
  /// thrown away with it.
  static final Map<String, TextPainter> _labelCache = <String, TextPainter>{};

  /// Axis labels drift as the viewport moves, so the key space is unbounded.
  /// Clearing is cheaper than evicting one at a time and the next frame repays
  /// it immediately, since labels repeat within a frame.
  static const int _labelCacheLimit = 128;

  /// Last closes array and indicator results, reused while the candle list is
  /// still the same object. Panning changes the window, not the data, so
  /// rebuilding a 5,000-point RSI — and MACD's three passes plus a max-abs scan —
  /// on every frame was the most expensive thing on the canvas: measured at
  /// ~170 us of a ~250 us frame with test/perf/chart_paint_benchmark.dart.
  ///
  /// One entry each, because a chart draws one oscillator at a time.
  /// `identical` is the right test: a refreshed series arrives as a new list and
  /// invalidates the cache without any explicit invalidation call.
  static List<Candle>? _closesSource;
  static List<double>? _closesCache;
  static List<double>? _rsiSource;
  static int _rsiPeriodCache = 0;
  static List<double?>? _rsiCache;
  static List<double>? _macdSource;
  static int _macdFastCache = 0;
  static int _macdSlowCache = 0;
  static int _macdSignalCache = 0;
  static List<MacdPoint?>? _macdCache;
  static double _macdMaxAbsCache = 1e-9;

  List<double> _oscillatorCloses() {
    if (identical(_closesSource, candles) && _closesCache != null) {
      return _closesCache!;
    }
    final list = <double>[for (final candle in candles) candle.close];
    _closesSource = candles;
    _closesCache = list;
    return list;
  }

  List<double?> _rsiSeries(List<double> closes, int period) {
    if (identical(_rsiSource, closes) &&
        _rsiPeriodCache == period &&
        _rsiCache != null) {
      return _rsiCache!;
    }
    final series = rsi(closes, period: period);
    _rsiSource = closes;
    _rsiPeriodCache = period;
    _rsiCache = series;
    return series;
  }

  ({List<MacdPoint?> points, double maxAbs}) _macdSeries(
    List<double> closes,
    int fast,
    int slow,
    int signal,
  ) {
    if (identical(_macdSource, closes) &&
        _macdFastCache == fast &&
        _macdSlowCache == slow &&
        _macdSignalCache == signal &&
        _macdCache != null) {
      return (points: _macdCache!, maxAbs: _macdMaxAbsCache);
    }
    final points = macd(closes, fast: fast, slow: slow, signal: signal);
    var maxAbs = 1e-9;
    for (final point in points) {
      if (point == null) continue;
      maxAbs = math.max(maxAbs, point.macd.abs());
      maxAbs = math.max(maxAbs, point.signal.abs());
      maxAbs = math.max(maxAbs, point.histogram.abs());
    }
    _macdSource = closes;
    _macdFastCache = fast;
    _macdSlowCache = slow;
    _macdSignalCache = signal;
    _macdCache = points;
    _macdMaxAbsCache = maxAbs;
    return (points: points, maxAbs: maxAbs);
  }

  TextPainter _painter(
    String text, {
    required Color color,
    required double size,
    FontWeight weight = FontWeight.w500,
  }) {
    final key = '$text|${color.toARGB32()}|$size|${weight.value}';
    final cached = _labelCache[key];
    if (cached != null) return cached;

    if (_labelCache.length >= _labelCacheLimit) _labelCache.clear();
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _labelCache[key] = painter;
    return painter;
  }

  @override
  bool shouldRepaint(covariant TradingChartPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.start != start ||
        oldDelegate.span != span ||
        oldDelegate.entry != entry ||
        oldDelegate.exit != exit ||
        oldDelegate.stop != stop ||
        oldDelegate.take != take ||
        oldDelegate.entryTime != entryTime ||
        oldDelegate.exitTime != exitTime ||
        oldDelegate.crosshair != crosshair ||
        oldDelegate.dragging != dragging ||
        oldDelegate.minPrice != minPrice ||
        oldDelegate.maxPrice != maxPrice ||
        oldDelegate.interval != interval ||
        oldDelegate.style != style ||
        oldDelegate.symbol != symbol ||
        oldDelegate.drawings != drawings ||
        oldDelegate.draftStart != draftStart ||
        oldDelegate.selectedDrawing != selectedDrawing;
  }
}
