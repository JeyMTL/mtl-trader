import 'package:flutter/material.dart';

/// Trading sessions for the price canvas.
///
/// Everything here is UTC, because that is what the candle feed emits and what
/// every broker session clock is quoted in. Converting to the device's zone
/// would move the Asian open to the user's afternoon and quietly mean something
/// different on every phone.
///
/// The windows are the conventional broker ones, including the hours where two
/// sessions trade at once (London and New York overlap from 12:00 to 16:00 UTC).
/// Overlaps are kept rather than merged: the overlap is the most liquid part of
/// the day, and the chart is expected to show both bands there.
enum TradingSession {
  sydney('Sydney', 21, 6, Color(0xFF4C9AFF)),
  asian('Asian', 0, 9, Color(0xFF9C8CFF)),
  london('London', 7, 16, Color(0xFF45D29A)),
  newYork('New York', 12, 21, Color(0xFFF0B90B));

  const TradingSession(this.label, this.startHour, this.endHour, this.tint);

  /// Shown on the band and in the style sheet.
  final String label;

  /// First UTC hour that belongs to the session, inclusive.
  final int startHour;

  /// First UTC hour after the session, exclusive.
  final int endHour;

  /// Band colour before opacity is applied by the painter.
  final Color tint;

  bool get wrapsMidnight => startHour >= endHour;

  /// Hours elapsed since this session opened, for a [time] inside it. Used to
  /// pick an owner when windows overlap: the one that opened most recently wins.
  int hoursInto(DateTime time) => (time.toUtc().hour - startHour) % 24;

  /// Whether [time] falls inside this session. [time] is converted to UTC first,
  /// so a caller holding local dates cannot shift the windows by accident.
  bool contains(DateTime time) {
    final hour = time.toUtc().hour;
    if (startHour == endHour) return true;
    if (!wrapsMidnight) return hour >= startHour && hour < endHour;
    return hour >= startHour || hour < endHour;
  }
}

/// A run of consecutive candles inside one session.
class SessionBand {
  const SessionBand({
    required this.session,
    required this.firstIndex,
    required this.lastIndex,
  });

  final TradingSession session;

  /// Index of the first candle inside the band, inclusive.
  final int firstIndex;

  /// Index of the last candle inside the band, inclusive.
  final int lastIndex;

  int get length => lastIndex - firstIndex + 1;

  @override
  String toString() => '${session.label}[$firstIndex..$lastIndex]';

  @override
  bool operator ==(Object other) =>
      other is SessionBand &&
      other.session == session &&
      other.firstIndex == firstIndex &&
      other.lastIndex == lastIndex;

  @override
  int get hashCode => Object.hash(session, firstIndex, lastIndex);
}

/// Groups [times] into contiguous runs for [session].
///
/// A lazy generator, so the painter can stream over five thousand candles
/// without building an intermediate list on every frame. Candle gaps (a
/// weekend, a halt) are not treated as session ends: only a candle that falls
/// outside the window closes a band, which keeps a Monday open joined to the
/// Friday close it belongs with in the same session colour.
Iterable<SessionBand> sessionBands(
  Iterable<DateTime> times,
  TradingSession session,
) sync* {
  var first = -1;
  var last = -1;
  var index = -1;
  for (final time in times) {
    index++;
    if (session.contains(time)) {
      if (first < 0) first = index;
      last = index;
    } else if (first >= 0) {
      yield SessionBand(session: session, firstIndex: first, lastIndex: last);
      first = -1;
      last = -1;
    }
  }
  if (first >= 0) {
    yield SessionBand(session: session, firstIndex: first, lastIndex: last);
  }
}

/// The session that owns a candle, and the run of candles it spans.
class SessionHit {
  const SessionHit({
    required this.session,
    required this.firstIndex,
    required this.lastIndex,
  });

  final TradingSession session;
  final int firstIndex;
  final int lastIndex;

  int get length => lastIndex - firstIndex + 1;

  @override
  String toString() => '${session.label}[$firstIndex..$lastIndex]';
}

/// Which session a candle belongs to, and where that session started.
///
/// Overlaps resolve to the window that opened most recently, measured in hours
/// since its own open rather than by comparing start hours — a session that
/// wraps midnight starts "late" on the clock but is the older one at 02:00.
/// That is why 13:00 UTC reads as New York rather than London.
SessionHit? sessionHitOf({
  required int index,
  required int length,
  required DateTime Function(int index) timeAt,
}) {
  if (index < 0 || index >= length) return null;
  final time = timeAt(index);

  TradingSession? owner;
  var ownerAge = 24;
  for (final session in TradingSession.values) {
    if (!session.contains(time)) continue;
    final age = session.hoursInto(time);
    if (owner == null || age < ownerAge) {
      owner = session;
      ownerAge = age;
    }
  }
  if (owner == null) return null;

  var first = index;
  while (first > 0 && owner.contains(timeAt(first - 1))) {
    first--;
  }
  var last = index;
  while (last < length - 1 && owner.contains(timeAt(last + 1))) {
    last++;
  }
  return SessionHit(session: owner, firstIndex: first, lastIndex: last);
}

/// What the vertical separators mark.
enum SeparatorGrain {
  day('Day'),
  week('Week'),
  month('Month');

  const SeparatorGrain(this.label);

  final String label;
}

/// True when [current] begins a new [grain] period that [previous] was not in.
///
/// Compared in UTC and by calendar field, not by subtracting a duration: a day
/// is not always 24 hours (DST), and a month is never a fixed number of days.
bool isPeriodBoundary(
  DateTime previous,
  DateTime current,
  SeparatorGrain grain,
) {
  final a = previous.toUtc();
  final b = current.toUtc();
  switch (grain) {
    case SeparatorGrain.day:
      return a.year != b.year || a.month != b.month || a.day != b.day;
    case SeparatorGrain.week:
      return _weekStart(a) != _weekStart(b);
    case SeparatorGrain.month:
      return a.year != b.year || a.month != b.month;
  }
}

/// Indices of the candles that open a new period, so the painter can draw one
/// line per day (or week, or month) instead of recomputing dates per pixel.
///
/// The first candle is never a boundary: a line on the left edge would read as
/// the start of a period the window only happens to begin inside.
Iterable<int> periodSeparatorIndices(
  Iterable<DateTime> times,
  SeparatorGrain grain,
) sync* {
  DateTime? previous;
  var index = -1;
  for (final time in times) {
    index++;
    if (previous != null && isPeriodBoundary(previous, time, grain)) {
      yield index;
    }
    previous = time;
  }
}

/// UTC midnight of the Monday that starts [time]'s week.
DateTime _weekStart(DateTime time) {
  final day = DateTime.utc(time.year, time.month, time.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}
