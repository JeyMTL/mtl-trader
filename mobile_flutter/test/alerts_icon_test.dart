import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/services/alerts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Proves the Android notification icon is a real drawable resource.
///
/// The plugin resolves the initialized icon with
/// `getIdentifier(name, "drawable", packageName)`, so an `@mipmap/...` value or
/// a name with no file behind it returns resource id 0, `initialize()` fails
/// with `invalid_icon`, and every alert is silently dropped. This test fails if
/// the name stops pointing at a drawable, or if it starts pointing at a mipmap.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  MethodCall? initializeCall;

  setUp(() {
    initializeCall = null;
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize') initializeCall = call;
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

  test('the Android default icon is a drawable resource', () async {
    await Alerts.instance.init();

    expect(
      initializeCall,
      isNotNull,
      reason: 'Alerts.init() must reach the plugin, not swallow an error',
    );
    final icon =
        (initializeCall!.arguments as Map)['defaultIcon'] as String? ?? '';

    // A bare resource name: "@mipmap/ic_launcher" is looked up as a drawable and
    // finds nothing.
    expect(icon, isNotEmpty);
    expect(icon, isNot(startsWith('@')));
    expect(icon, isNot(contains('/')));

    final res = _androidResDirectory();
    final drawables = _filesNamed(res, 'drawable', icon);
    expect(
      drawables,
      isNotEmpty,
      reason: 'No res/drawable*/$icon.(xml|png) — Android would reject it',
    );

    // The plugin asks for a drawable, so a mipmap-only resource is just as
    // broken even though the file exists in the project.
    final mipmaps = _filesNamed(res, 'mipmap', icon);
    expect(
      mipmaps,
      isEmpty,
      reason: '$icon must live in res/drawable, not res/mipmap',
    );
  });
}

/// The Android resource directory, whether the test runs from the Flutter
/// package root or from the repository root.
Directory _androidResDirectory() {
  var dir = Directory.current;
  for (var depth = 0; depth < 5; depth++) {
    final candidate = Directory('${dir.path}/android/app/src/main/res');
    if (candidate.existsSync()) return candidate;
    dir = dir.parent;
  }
  fail('Could not find android/app/src/main/res from ${Directory.current.path}');
}

/// Files named `<icon>.<ext>` inside every `<type>*` resource folder.
List<File> _filesNamed(Directory res, String type, String icon) {
  final matches = <File>[];
  for (final dir in res.listSync().whereType<Directory>()) {
    final folder = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (folder != type && !folder.startsWith('$type-')) continue;
    for (final file in dir.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (name.startsWith('$icon.')) matches.add(file);
    }
  }
  return matches;
}
