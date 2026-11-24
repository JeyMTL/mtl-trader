import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../core/config.dart';
import 'journal_api.dart';

/// Server-sent notifications, delivered by Firebase Cloud Messaging.
///
/// The phone cannot be woken by the web app, so anything the server decides —
/// a broker connection that stopped working, a subscription about to lapse, a
/// prop-rule breach found on the server — needs a channel that exists when the
/// app is closed. That is this one.
///
/// Local alerts stay where they are: the journal reminder and the daily stop are
/// scheduled by `flutter_local_notifications` and must never depend on a network
/// round trip or on the server being funded.
///
/// With no Firebase values in the build this class does nothing at all, so an
/// APK built without them is exactly the app it was before.
class PushService {
  PushService._();

  static FirebaseMessaging? _messaging;
  static JournalApi? _api;
  static bool _failed = false;

  /// Whether this build carries a Firebase project.
  static bool get isConfigured => AppConfig.pushConfigured;

  /// Registers this device with Firebase and uploads the token to the backend.
  ///
  /// Safe to call more than once: the SDK setup and the permission request
  /// happen once, while registration is repeated, because the token only has an
  /// owner after someone signs in. That is why the shell calls it both at
  /// startup and on every sign-in.
  static Future<void> start(JournalApi api) async {
    if (_failed || !isConfigured) return;
    _api = api;

    try {
      final messaging = _messaging ??= await _initialise();
      if (messaging == null) return;
      // Registration emits on `onRegistered`, which `_initialise` is already
      // listening to; calling it again after a sign-in re-emits the token.
      await messaging.register();
    } catch (_) {
      // No Play services, a blocked project, a phone with no network: none of
      // that is a reason for the journal to fail to open.
      _failed = true;
    }
  }

  static Future<FirebaseMessaging?> _initialise() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: AppConfig.firebaseAppId,
          messagingSenderId: AppConfig.firebaseSenderId,
          projectId: AppConfig.firebaseProjectId,
          storageBucket: AppConfig.firebaseStorageBucket.isEmpty
              ? null
              : AppConfig.firebaseStorageBucket,
        ),
      );
    }

    final messaging = FirebaseMessaging.instance;
    // Android 13+ and iOS both ask here; a refusal is a normal answer, not an
    // error, and the app continues without notifications.
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return null;
    }

    // FCM rotates tokens (reinstall, restore, a long-idle device) and re-emits
    // on every registration. The server upserts on token, so a repeat is a write
    // to one row, not a duplicate device.
    messaging.onRegistered.listen((token) {
      final api = _api;
      if (api != null) unawaited(_send(api, token));
    });

    return messaging;
  }

  static Future<void> _send(JournalApi api, String token) async {
    if (token.isEmpty) return;
    try {
      await api.registerPushToken(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
    } catch (_) {
      // Retried on the next launch; a token that never lands is one missing
      // notification, not a broken session.
    }
  }
}
