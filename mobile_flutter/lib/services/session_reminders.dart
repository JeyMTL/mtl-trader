import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/session_schedule.dart';
import 'alerts.dart';

/// Keeps the phone's session alarms in step with the playbook.
///
/// The playbook lives in Supabase and is edited from both the web app and this
/// phone, so the phone cannot own the schedule: it reads the row and re-arms
/// itself. That is why [sync] runs on every launch and straight after a save —
/// a session added on the website should ring here without the trader opening
/// the Rules screen again.
///
/// Best effort throughout. A failed read leaves whatever alarms already exist
/// (better stale than silent), and nothing here can stop the app from opening.
class SessionReminders {
  const SessionReminders._();

  static Future<void> sync({DateTime? now}) async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        await Alerts.instance.scheduleSessionReminders(const []);
        return;
      }

      final results = await Future.wait([
        client
            .from('playbooks')
            .select('rules, days, sessions, reminder_minutes, reminders_enabled')
            .eq('user_id', user.id)
            .maybeSingle(),
        client.from('users').select('timezone').eq('id', user.id).maybeSingle(),
      ]);

      final book = results[0];
      if (book == null) {
        await Alerts.instance.scheduleSessionReminders(const []);
        return;
      }

      // Same rule as the web reminder: with no checklist there is nothing to
      // review, so a session nudge would be noise.
      final remindersEnabled = book['reminders_enabled'] != false;
      final rules = book['rules'];
      final hasRules = rules is List && rules.any((rule) => '$rule'.trim().isNotEmpty);
      final lead = book['reminder_minutes'] is num
          ? (book['reminder_minutes'] as num).toInt()
          : 60;

      final sessions = <SessionSpec>[];
      final rawSessions = book['sessions'];
      if (remindersEnabled && hasRules && rawSessions is List) {
        for (final raw in rawSessions) {
          if (raw is! Map) continue;
          final start = '${raw['start'] ?? ''}';
          final end = '${raw['end'] ?? ''}';
          if (minutesOfDay(start) == null || minutesOfDay(end) == null) continue;
          sessions.add(
            SessionSpec(
              id: '${raw['id'] ?? 'session-${sessions.length}'}',
              label: '${raw['label'] ?? 'Session'}',
              start: start,
              end: end,
            ),
          );
        }
      }

      final days = <int>{};
      final rawDays = book['days'];
      if (rawDays is List) {
        for (final day in rawDays) {
          final value = day is num ? day.toInt() : int.tryParse('$day');
          if (value != null && value >= 0 && value <= 6) days.add(value);
        }
      }

      final timezone = '${results[1]?['timezone'] ?? ''}';
      final schedule = upcomingSessionReminders(
        sessions: sessions,
        days: days,
        leadMinutes: lead,
        zoneId: timezone,
        now: now ?? DateTime.now().toUtc(),
      );
      await Alerts.instance.scheduleSessionReminders(schedule);
    } catch (error) {
      // Logged, not thrown: a missing table or an offline phone must not affect
      // anything else, and a silent failure here is what "the reminder never
      // rang" looks like from the outside.
      debugPrint('SessionReminders.sync failed: $error');
    }
  }
}
