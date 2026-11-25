import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/services/alerts.dart';

/// The journal reminder is one instant a day, stored as minutes past UTC
/// midnight. The account's timezone only decides how that instant is printed
/// in the picker, so changing the zone moves the shown time and leaves the
/// alarm where it was.
void main() {
  test('02:00 UTC reads as the same instant in every account zone', () {
    final alerts = Alerts.instance;
    alerts.reminderUtcMinute = 2 * 60;

    for (final zone in [
      'UTC',
      'America/New_York',
      'Asia/Tokyo',
      'Europe/Stockholm',
      'Africa/Johannesburg',
      '',
    ]) {
      final shown = alerts.reminderAtIn(zone);
      expect(
        alerts.utcMinuteFor(zone, shown),
        2 * 60,
        reason: '$zone shows ${shown.hour}:${shown.minute}',
      );
    }
  });

  test('New York reads 02:00 UTC as an evening hour', () {
    final alerts = Alerts.instance;
    alerts.reminderUtcMinute = 2 * 60;

    final shown = alerts.reminderAtIn('America/New_York');
    // 21:00 EST or 22:00 EDT, never the early morning the UTC time suggests.
    expect(shown.hour, anyOf(21, 22));
  });

  test('a time picked in New York round-trips back to itself', () {
    final alerts = Alerts.instance;
    const picked = TimeOfDayValue(9, 30);
    final utcMinute = alerts.utcMinuteFor('America/New_York', picked);
    alerts.reminderUtcMinute = utcMinute;

    final shown = alerts.reminderAtIn('America/New_York');
    expect(shown.hour, 9);
    expect(shown.minute, 30);
  });
}
