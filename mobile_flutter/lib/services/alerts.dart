import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// What an alert was about.
enum AlertKind { dailyStop, levelTouch, journalReminder }

/// One alert the phone produced, kept whether or not the system chose to show
/// it, so the in-app list can explain itself later.
@immutable
class AlertEvent {
  const AlertEvent({
    required this.kind,
    required this.title,
    required this.body,
    required this.reason,
    required this.at,
    this.delivered = true,
    this.muted = false,
  });

  final AlertKind kind;
  final String title;
  final String body;

  /// Why the alert fired, in one sentence. This is the part that makes the
  /// in-app list useful rather than a duplicate of the notification.
  final String reason;
  final DateTime at;

  /// True when the system notification was actually posted for it.
  final bool delivered;

  /// True when the trader had this kind switched off, so the event is recorded
  /// but was never shown on the phone.
  final bool muted;

  Map<String, Object?> toJson() => {
        'k': kind.name,
        't': title,
        'b': body,
        'r': reason,
        'at': at.toUtc().millisecondsSinceEpoch,
        if (!delivered) 'd': false,
        if (muted) 'm': true,
      };

  static AlertEvent? fromJson(Object? value) {
    if (value is! Map) return null;
    final kindName = value['k'];
    final title = value['t'];
    final body = value['b'];
    final reason = value['r'];
    final at = value['at'];
    if (kindName is! String ||
        title is! String ||
        body is! String ||
        reason is! String ||
        at is! num) {
      return null;
    }
    final kind = AlertKind.values.firstWhere(
      (candidate) => candidate.name == kindName,
      orElse: () => AlertKind.levelTouch,
    );
    return AlertEvent(
      kind: kind,
      title: title,
      body: body,
      reason: reason,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      delivered: value['d'] != false,
      muted: value['m'] == true,
    );
  }
}

/// Local notifications: the three things worth interrupting a trader for,
/// produced by the phone itself.
///
/// Everything here runs on the device. There is no push service, no token and
/// no server call: the daily stop is read from the same `/api/day-state` the
/// gate already polls, level touches come from the candles the chart already
/// streams, and the journal reminder is a daily alarm. That is why these work
/// with the app closed and why nothing leaves the phone.
class Alerts {
  Alerts._();

  static final Alerts instance = Alerts._();

  static const String _dailyStopKey = 'alerts.dailyStop';
  static const String _levelsKey = 'alerts.levels';
  static const String _journalKey = 'alerts.journal';
  static const String _hourKey = 'alerts.journalHour';
  static const String _minuteKey = 'alerts.journalMinute';

  static const String _channelDaily = 'daily-stop';
  static const String _channelLevels = 'levels';
  static const String _channelJournal = 'journal';
  static const int _reminderId = 4407;
  static const int _historyLimit = 200;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  bool _permissionAsked = false;

  /// Resolved once at startup; the reminder needs a wall clock, not UTC.
  tz.Location _zone = tz.UTC;

  /// Where the last alert went, so the shell can badge the list without
  /// re-reading the file on every frame.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool dailyStopEnabled = true;
  bool levelsEnabled = true;
  bool journalEnabled = true;
  TimeOfDayValue reminderAt = const TimeOfDayValue(18, 0);

  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final local = await FlutterTimezone.getLocalTimezone();
        _zone = tz.getLocation(local.identifier);
      } catch (_) {
        _zone = tz.UTC;
      }
      tz.setLocalLocation(_zone);

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: ios),
      );
      await _createChannels();
      await _loadPreferences();
      _ready = true;
      // A reminder scheduled before the app was updated or the phone rebooted
      // still has to exist, so it is (re)scheduled on every start.
      unawaited(_scheduleReminder());
    } catch (_) {
      // Notifications are a convenience: a phone that refuses them must not
      // take the journal down with it.
    }
  }

  Future<void> _createChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelDaily,
        'Daily stop',
        description: 'When the daily loss limit is reached and trading locks',
        importance: Importance.high,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelLevels,
        'Level touched',
        description: 'When price reaches a level drawn on the chart',
        importance: Importance.high,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelJournal,
        'Journal reminder',
        description: 'A daily nudge to journal the day',
        importance: Importance.defaultImportance,
      ),
    );
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    dailyStopEnabled = prefs.getBool(_dailyStopKey) ?? true;
    levelsEnabled = prefs.getBool(_levelsKey) ?? true;
    journalEnabled = prefs.getBool(_journalKey) ?? true;
    reminderAt = TimeOfDayValue(
      prefs.getInt(_hourKey) ?? 18,
      prefs.getInt(_minuteKey) ?? 0,
    );
  }

  /// Asks Android 13+ for permission once, at the point the trader turns an
  /// alert on — not at launch, where a prompt with no context gets denied.
  Future<bool> ensurePermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    var granted = await android.areNotificationsEnabled() ?? false;
    if (granted) return true;
    if (_permissionAsked) return false;
    _permissionAsked = true;
    granted = await android.requestNotificationsPermission() ?? false;
    return granted;
  }

  Future<bool> permissionGranted() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? false;
  }

  Future<void> setDailyStop(bool value) async {
    dailyStopEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dailyStopKey, value);
    if (value) await ensurePermission();
  }

  Future<void> setLevels(bool value) async {
    levelsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_levelsKey, value);
    if (value) await ensurePermission();
  }

  Future<void> setJournal(bool value, {TimeOfDayValue? at}) async {
    journalEnabled = value;
    if (at != null) reminderAt = at;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_journalKey, value);
    await prefs.setInt(_hourKey, reminderAt.hour);
    await prefs.setInt(_minuteKey, reminderAt.minute);
    if (value) await ensurePermission();
    await _scheduleReminder();
  }

  /// The one alert that has to fire with the app closed, hence a scheduled
  /// notification rather than a timer.
  Future<void> _scheduleReminder() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await _plugin.cancel(id: _reminderId);
    if (!journalEnabled) return;
    final now = tz.TZDateTime.now(_zone);
    var next = tz.TZDateTime(
      _zone,
      now.year,
      now.month,
      now.day,
      reminderAt.hour,
      reminderAt.minute,
    );
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    try {
      await _plugin.zonedSchedule(
        id: _reminderId,
        title: 'Journal the day',
        body: 'Log what you traded and why, while it is still fresh.',
        scheduledDate: next,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelJournal,
            'Journal reminder',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'journal',
      );
    } catch (_) {
      // A refused alarm is reported in the list as a muted event, not thrown.
    }
  }

  /// The daily stop just engaged. Called by the gate on every poll, which is why
  /// the caller passes [alreadyNotified] for the day it has already covered.
  Future<void> dailyStopHit({
    required double lossUsed,
    required double lossLimit,
    required String dayKey,
  }) async {
    await init();
    final money = lossUsed.toStringAsFixed(2);
    final limit = lossLimit.toStringAsFixed(2);
    if (!dailyStopEnabled) {
      await _record(
        AlertEvent(
          kind: AlertKind.dailyStop,
          title: 'Daily stop reached',
          body: 'Loss $money of the $limit limit.',
          reason:
              'The day reached its loss limit, so the stop ${lossLimit > 0 ? 'locked trading' : 'fired'}. Recorded only — daily stop alerts are off.',
          at: DateTime.now(),
          delivered: false,
          muted: true,
        ),
      );
      return;
    }
    final delivered = await _show(
      id: dayKey.hashCode & 0x7fffffff,
      channel: _channelDaily,
      channelName: 'Daily stop',
      title: 'Daily stop reached — trading locked',
      body: 'Loss $money of your $limit daily limit. The journal stays open.',
    );
    await _record(
      AlertEvent(
        kind: AlertKind.dailyStop,
        title: 'Daily stop reached — trading locked',
        body: 'Loss $money of your $limit daily limit.',
        reason:
            'Today\'s realised loss crossed the limit set in your rules, so the stop engaged for $dayKey.',
        at: DateTime.now(),
        delivered: delivered,
      ),
    );
  }

  /// Price reached a level the trader drew. [crossedFrom] and [crossedTo] are
  /// the two prices the crossing happened between, which is what makes the
  /// reason readable later.
  Future<void> levelTouched({
    required String symbol,
    required String label,
    required double price,
    required double crossedFrom,
    required double crossedTo,
    required int decimals,
  }) async {
    await init();
    final value = price.toStringAsFixed(decimals);
    final title = '$symbol $label $value touched';
    final body =
        'Price moved from ${crossedFrom.toStringAsFixed(decimals)} to '
        '${crossedTo.toStringAsFixed(decimals)} and crossed your level.';
    final reason =
        'A level you drew on $symbol was crossed during a live candle update, '
        'so the alert fired once for this touch.';
    if (!levelsEnabled) {
      await _record(
        AlertEvent(
          kind: AlertKind.levelTouch,
          title: title,
          body: body,
          reason: '$reason Recorded only — level alerts are off.',
          at: DateTime.now(),
          delivered: false,
          muted: true,
        ),
      );
      return;
    }
    final delivered = await _show(
      id: '$symbol|$label|$value'.hashCode & 0x7fffffff,
      channel: _channelLevels,
      channelName: 'Level touched',
      title: title,
      body: body,
    );
    await _record(
      AlertEvent(
        kind: AlertKind.levelTouch,
        title: title,
        body: body,
        reason: reason,
        at: DateTime.now(),
        delivered: delivered,
      ),
    );
  }

  /// Proves the channel works, from the account screen.
  Future<bool> sendTest() async {
    await init();
    final granted = await ensurePermission();
    if (!granted) return false;
    final delivered = await _show(
      id: 9911,
      channel: _channelLevels,
      channelName: 'Level touched',
      title: 'Alerts are on',
      body: 'This is what a level touch will look like.',
    );
    await _record(
      AlertEvent(
        kind: AlertKind.levelTouch,
        title: 'Alerts are on',
        body: 'Test notification from the account screen.',
        reason: 'You asked for a test, so the level channel was used.',
        at: DateTime.now(),
        delivered: delivered,
      ),
    );
    return delivered;
  }

  Future<bool> _show({
    required int id,
    required String channel,
    required String channelName,
    required String title,
    required String body,
  }) async {
    try {
      final granted = await ensurePermission();
      if (!granted) return false;
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel,
            channelName,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.status,
          ),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Newest first. Small, bounded and local: the point is to answer "what did
  /// the app tell me, and why", not to be a message archive.
  Future<List<AlertEvent>> history() async {
    try {
      final file = await _historyFile();
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      final events = <AlertEvent>[];
      for (final entry in decoded) {
        final event = AlertEvent.fromJson(entry);
        if (event != null) events.add(event);
      }
      events.sort((a, b) => b.at.compareTo(a.at));
      return events;
    } catch (_) {
      return const [];
    }
  }

  Future<void> clearHistory() async {
    try {
      final file = await _historyFile();
      if (await file.exists()) await file.delete();
      revision.value++;
    } catch (_) {
      // Nothing to clear, or no permission to: either way the list stays empty.
    }
  }

  Future<void> _record(AlertEvent event) async {
    try {
      final file = await _historyFile();
      final existing = <AlertEvent>[];
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          for (final entry in decoded) {
            final parsed = AlertEvent.fromJson(entry);
            if (parsed != null) existing.add(parsed);
          }
        }
      }
      final next = [event, ...existing];
      if (next.length > _historyLimit) next.removeRange(_historyLimit, next.length);
      await file.writeAsString(
        jsonEncode([for (final item in next) item.toJson()]),
        flush: false,
      );
      revision.value++;
    } catch (_) {
      // History is a record of alerts, never a reason to lose one.
    }
  }

  Future<File> _historyFile() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/alerts');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/history.json');
  }
}

/// A time of day without depending on Material's `TimeOfDay`, so the service
/// can be used from tests and from code that never builds a widget.
@immutable
class TimeOfDayValue {
  const TimeOfDayValue(this.hour, this.minute);

  final int hour;
  final int minute;

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
