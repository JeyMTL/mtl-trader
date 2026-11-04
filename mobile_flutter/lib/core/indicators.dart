import 'package:flutter/material.dart';

/// The maths behind an overlay.
enum StudyKind { sma, ema }

/// Studies the price canvas can draw on top of the candles.
///
/// Kept to plain moving averages on purpose: they are the overlays a trader
/// reads at a glance, they need no second scale, and their maths is easy to
/// verify against any other platform.
enum OverlayStudy {
  sma20('SMA 20', StudyKind.sma, 20, Color(0xFFF0B90B)),
  sma50('SMA 50', StudyKind.sma, 50, Color(0xFF4C9AFF)),
  sma200('SMA 200', StudyKind.sma, 200, Color(0xFFAB7DF6)),
  ema21('EMA 21', StudyKind.ema, 21, Color(0xFFFF8A5C));

  const OverlayStudy(this.label, this.kind, this.period, this.color);

  /// Legend text, e.g. `SMA 20`.
  final String label;

  final StudyKind kind;

  /// Candles in the average.
  final int period;

  /// Line colour; distinct enough to read four at once.
  final Color color;
}

/// The series for [study] aligned with [closes]; null until it has enough data.
///
/// [period] overrides the study's default, which is how the style sheet makes
/// the moving averages editable (SMA 9/21/50 and so on).
List<double?> studySeries(
  OverlayStudy study,
  List<double> closes, {
  int? period,
}) {
  final length = (period ?? study.period).clamp(1, 1000);
  switch (study.kind) {
    case StudyKind.sma:
      return sma(closes, length);
    case StudyKind.ema:
      return ema(closes, length);
  }
}

/// Legend text for a study, e.g. `SMA 9` or `EMA 21`.
String studyLabel(OverlayStudy study, {int? period}) {
  final length = period ?? study.period;
  switch (study.kind) {
    case StudyKind.sma:
      return 'SMA $length';
    case StudyKind.ema:
      return 'EMA $length';
  }
}

/// Simple moving average. Entries before the first full window are null.
List<double?> sma(List<double> values, int period) {
  final out = List<double?>.filled(values.length, null);
  if (period <= 0) return out;
  var sum = 0.0;
  for (var i = 0; i < values.length; i++) {
    sum += values[i];
    if (i >= period) sum -= values[i - period];
    if (i >= period - 1) out[i] = sum / period;
  }
  return out;
}

/// Relative Strength Index with Wilder smoothing. Null until `period` changes
/// have been seen, like every other platform's series.
List<double?> rsi(List<double> closes, {int period = 14}) {
  final out = List<double?>.filled(closes.length, null);
  if (period <= 0 || closes.length <= period) return out;
  var gain = 0.0;
  var loss = 0.0;
  for (var i = 1; i <= period; i++) {
    final change = closes[i] - closes[i - 1];
    if (change >= 0) {
      gain += change;
    } else {
      loss -= change;
    }
  }
  var averageGain = gain / period;
  var averageLoss = loss / period;
  out[period] = _rsiValue(averageGain, averageLoss);
  for (var i = period + 1; i < closes.length; i++) {
    final change = closes[i] - closes[i - 1];
    averageGain =
        (averageGain * (period - 1) + (change > 0 ? change : 0)) / period;
    averageLoss =
        (averageLoss * (period - 1) + (change < 0 ? -change : 0)) / period;
    out[i] = _rsiValue(averageGain, averageLoss);
  }
  return out;
}

double _rsiValue(double gain, double loss) {
  if (loss == 0) return 100;
  final rs = gain / loss;
  return 100 - 100 / (1 + rs);
}

/// One MACD point: the line, its signal and the histogram.
class MacdPoint {
  const MacdPoint({
    required this.macd,
    required this.signal,
    required this.histogram,
  });

  final double macd;
  final double signal;
  final double histogram;
}

/// MACD (12/26/9 by default): EMA fast − EMA slow, with an EMA signal line.
List<MacdPoint?> macd(
  List<double> closes, {
  int fast = 12,
  int slow = 26,
  int signal = 9,
}) {
  final out = List<MacdPoint?>.filled(closes.length, null);
  final fastEma = ema(closes, fast);
  final slowEma = ema(closes, slow);
  final line = List<double?>.filled(closes.length, null);
  for (var i = 0; i < closes.length; i++) {
    final f = fastEma[i];
    final s = slowEma[i];
    if (f != null && s != null) line[i] = f - s;
  }
  final start = line.indexWhere((value) => value != null);
  if (start < 0) return out;
  final values = line.sublist(start).cast<double>();
  final signalValues = ema(values, signal);
  for (var i = 0; i < values.length; i++) {
    final sig = signalValues[i];
    if (sig == null) continue;
    out[start + i] = MacdPoint(
      macd: values[i],
      signal: sig,
      histogram: values[i] - sig,
    );
  }
  return out;
}

/// Exponential moving average, seeded with the SMA of the first window — the
/// convention every charting platform uses, so the line matches theirs.
List<double?> ema(List<double> values, int period) {
  final out = List<double?>.filled(values.length, null);
  if (period <= 0 || values.length < period) return out;
  var sum = 0.0;
  for (var i = 0; i < period; i++) {
    sum += values[i];
  }
  var previous = sum / period;
  out[period - 1] = previous;
  final k = 2 / (period + 1);
  for (var i = period; i < values.length; i++) {
    previous = values[i] * k + previous * (1 - k);
    out[i] = previous;
  }
  return out;
}
