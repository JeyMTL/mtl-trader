import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/chart_zone.dart';
import 'package:mtl_trader_mobile/core/session_schedule.dart';

SessionSpec london({String start = '13:09', String end = '15:00'}) => SessionSpec(
      id: 'session-1',
      label: 'London',
      start: start,
      end: end,
    );

void main() {
  setUpAll(ChartZone.ensureReady);

  test('reminds an hour before a weekday session, not a minute before', () {
    // Tuesday 24 November 2026, 10:00 UTC.
    final now = DateTime.utc(2026, 11, 24, 10);

    final schedule = upcomingSessionReminders(
      sessions: [london()],
      days: {1, 2, 3, 4, 5},
      leadMinutes: 60,
      zoneId: 'UTC',
      now: now,
    );

    expect(schedule, isNotEmpty);
    expect(schedule.first.at, DateTime.utc(2026, 11, 24, 12, 9));
    expect(schedule.first.startsAt, DateTime.utc(2026, 11, 24, 13, 9));
    expect(schedule.first.title, 'London starts in 1 h');
  });

  test('skips an occurrence whose reminder window has already passed', () {
    // 12:30 is inside the hour before the session, but the alarm time is gone.
    final now = DateTime.utc(2026, 11, 24, 12, 30);

    final schedule = upcomingSessionReminders(
      sessions: [london()],
      days: {1, 2, 3, 4, 5},
      leadMinutes: 60,
      zoneId: 'UTC',
      now: now,
    );

    expect(schedule.first.at, DateTime.utc(2026, 11, 25, 12, 9));
  });

  test('never schedules a day the trader does not trade', () {
    final schedule = upcomingSessionReminders(
      sessions: [london()],
      days: {1, 2, 3, 4, 5},
      leadMinutes: 60,
      zoneId: 'UTC',
      now: DateTime.utc(2026, 11, 21, 9), // Saturday
      horizonDays: 7,
    );

    expect(schedule, isNotEmpty);
    for (final reminder in schedule) {
      final weekday = reminder.startsAt.weekday;
      expect(weekday, isNot(DateTime.saturday));
      expect(weekday, isNot(DateTime.sunday));
    }
    // Monday 23rd is the first trading day after that Saturday.
    expect(schedule.first.startsAt, DateTime.utc(2026, 11, 23, 13, 9));
  });

  test('keeps an overnight session on the day it starts', () {
    final schedule = upcomingSessionReminders(
      sessions: [london(start: '22:00', end: '02:00')],
      days: {1, 2, 3, 4, 5},
      leadMinutes: 30,
      zoneId: 'UTC',
      now: DateTime.utc(2026, 11, 24, 10),
    );

    expect(schedule.first.startsAt, DateTime.utc(2026, 11, 24, 22));
    expect(schedule.first.at, DateTime.utc(2026, 11, 24, 21, 30));
  });

  test('reads the session clock in the trader\'s zone, not the phone\'s', () {
    // New York is UTC-5 in November, so 09:30 there is 14:30 UTC.
    final schedule = upcomingSessionReminders(
      sessions: [london(start: '09:30', end: '11:00')],
      days: {1, 2, 3, 4, 5},
      leadMinutes: 15,
      zoneId: 'America/New_York',
      now: DateTime.utc(2026, 11, 24, 10),
    );

    expect(schedule.first.startsAt, DateTime.utc(2026, 11, 24, 14, 30));
    expect(schedule.first.at, DateTime.utc(2026, 11, 24, 14, 15));
  });

  test('nothing is scheduled when reminders are off or the checklist is empty', () {
    for (final lead in [0, -5]) {
      expect(
        upcomingSessionReminders(
          sessions: [london()],
          days: {1, 2, 3, 4, 5},
          leadMinutes: lead,
          zoneId: 'UTC',
          now: DateTime.utc(2026, 11, 24, 10),
        ),
        isEmpty,
      );
    }
    expect(
      upcomingSessionReminders(
        sessions: const [],
        days: {1, 2, 3, 4, 5},
        leadMinutes: 60,
        zoneId: 'UTC',
        now: DateTime.utc(2026, 11, 24, 10),
      ),
      isEmpty,
    );
  });

  test('a week of alarms fits the slot range the scheduler clears', () {
    final schedule = upcomingSessionReminders(
      sessions: [for (var i = 0; i < 6; i += 1) london()],
      days: {0, 1, 2, 3, 4, 5, 6},
      leadMinutes: 60,
      zoneId: 'UTC',
      now: DateTime.utc(2026, 11, 24, 10),
      horizonDays: 7,
    );

    // 48 ids are reserved and cleared; the list must never exceed them or the
    // extra alarms would survive a reschedule.
    expect(schedule.length, lessThanOrEqualTo(48));
  });

  test('countdown wording matches the web reminder', () {
    expect(countdown(0), 'now');
    expect(countdown(42), 'in 42 min');
    expect(countdown(60), 'in 1 h');
    expect(countdown(75), 'in 1 h 15 min');
  });
}
