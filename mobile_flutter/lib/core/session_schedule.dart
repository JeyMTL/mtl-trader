import 'chart_zone.dart';

/// When to nudge a trader about a session that is about to start.
///
/// The web app has computed this since the playbook shipped (`reminderState` in
/// `src/lib/playbook.ts`). The phone saved `reminder_minutes` and never read it
/// back, so the setting did nothing there. This is the same rule in Dart, kept
/// pure so it can be tested without a clock, a database or a notification
/// plugin: the session happens at a wall-clock time in the trader's zone, and
/// the reminder is `leadMinutes` earlier, expressed as a UTC instant because
/// that is what a scheduled alarm stores.
class SessionSpec {
  const SessionSpec({
    required this.id,
    required this.label,
    required this.start,
    required this.end,
  });

  final String id;
  final String label;
  /// Local `HH:MM`, 24-hour.
  final String start;
  /// Local `HH:MM`. Before [start] means the session runs overnight.
  final String end;
}

/// One alarm, already resolved to instants.
class SessionReminder {
  const SessionReminder({
    required this.session,
    required this.at,
    required this.startsAt,
  });

  final SessionSpec session;
  /// When the phone should notify (UTC).
  final DateTime at;
  /// When the session actually starts (UTC).
  final DateTime startsAt;

  int get minutesUntil => (startsAt.difference(at).inSeconds / 60).round();

  String get title => '${session.label} starts ${countdown(minutesUntil)}';
}

/// Minutes past local midnight, or null for a malformed `HH:MM`.
int? minutesOfDay(String value) {
  final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value.trim());
  if (match == null) return null;
  return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
}

/// "in 42 min" / "in 1 h 15 min", matching the web reminder's wording.
String countdown(int minutes) {
  if (minutes <= 0) return 'now';
  if (minutes < 60) return 'in $minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? 'in $hours h' : 'in $hours h $rest min';
}

/// The alarms for the next [horizonDays] days, soonest first.
///
/// A session on a day the trader does not trade gets nothing — that is the whole
/// point of the day tickboxes. An occurrence whose reminder would already be in
/// the past is dropped rather than fired late: a "starts in 5 min" for a session
/// that began twenty minutes ago would teach the trader to ignore the alert.
///
/// The horizon exists because these are pre-scheduled device alarms, not a
/// server tick. Seven days covers a full weekly cycle, and the list is
/// re-scheduled on every app launch and every save of the playbook.
List<SessionReminder> upcomingSessionReminders({
  required List<SessionSpec> sessions,
  required Set<int> days,
  required int leadMinutes,
  required String zoneId,
  required DateTime now,
  int horizonDays = 7,
  int limit = 42,
}) {
  if (sessions.isEmpty || days.isEmpty || leadMinutes <= 0) {
    return const <SessionReminder>[];
  }
  ChartZone.ensureReady();
  final zone = ChartZone.byId(zoneId);
  final wallToday = zone.wall(now);

  final found = <SessionReminder>[];
  for (var offset = 0; offset <= horizonDays; offset += 1) {
    // Built in UTC so adding days cannot drift across a DST change: only the
    // year/month/day are used.
    final day = DateTime.utc(wallToday.year, wallToday.month, wallToday.day + offset);
    // 0 = Sunday … 6 = Saturday, the order the playbook stores.
    if (!days.contains(day.weekday % 7)) continue;

    for (final session in sessions) {
      final startMinutes = minutesOfDay(session.start);
      if (startMinutes == null) continue;
      final startsAt = zone.instantAt(day, startMinutes ~/ 60, startMinutes % 60);
      final at = startsAt.subtract(Duration(minutes: leadMinutes));
      if (!at.isAfter(now)) continue;
      found.add(SessionReminder(session: session, at: at, startsAt: startsAt));
    }
  }

  found.sort((a, b) => a.at.compareTo(b.at));
  return found.length > limit ? found.sublist(0, limit) : found;
}
