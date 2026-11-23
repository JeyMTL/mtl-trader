import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/services/alerts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Proves the two alert triggers actually post through the Android plugin.
///
/// The notifications are produced by the plugin's Android implementation, so the
/// test stands that implementation up with a mocked method channel. It also pins
/// the initialization icon to a drawable name: `@mipmap/ic_launcher` is not found
/// by the plugin's drawable lookup, and the `invalid_icon` failure that follows
/// is what left every Android alert undelivered.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
        case 'areNotificationsEnabled':
        case 'requestNotificationsPermission':
          return true;
        case 'getNotificationAppLaunchDetails':
          return <String, Object?>{'notificationLaunchedApp': false};
        default:
          return null;
      }
    });
    // The reminder needs a wall clock; UTC keeps the test deterministic.
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (call) async => 'UTC',
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      null,
    );
  });

  List<MethodCall> shows() =>
      calls.where((call) => call.method == 'show').toList();

  test('a level touch posts on the levels channel', () async {
    await Alerts.instance.levelTouched(
      symbol: 'EURUSD',
      label: 'entry',
      price: 1.2050,
      crossedFrom: 1.2040,
      crossedTo: 1.2060,
      decimals: 4,
    );

    final init = calls.firstWhere((call) => call.method == 'initialize');
    expect((init.arguments as Map)['defaultIcon'], 'ic_stat_ledger');

    final posted = shows();
    expect(posted, hasLength(1));
    expect(posted.single.arguments['title'], contains('EURUSD entry'));
    final details =
        (posted.single.arguments as Map)['platformSpecifics'] as Map;
    expect(details['channelId'], 'levels');
  });

  test('the daily stop posts once on the daily-stop channel', () async {
    await Alerts.instance.dailyStopHit(
      lossUsed: 250,
      lossLimit: 200,
      dayKey: '2026-11-23',
    );

    final posted = shows();
    expect(posted, hasLength(1));
    expect(posted.single.arguments['title'], contains('Daily stop reached'));
    final details =
        (posted.single.arguments as Map)['platformSpecifics'] as Map;
    expect(details['channelId'], 'daily-stop');
  });
}
