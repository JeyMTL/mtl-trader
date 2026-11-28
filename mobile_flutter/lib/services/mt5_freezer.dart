import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The soft lock's phone-side enforcement: freeze the MetaTrader 5 app.
///
/// The decision is still the server's. This bridge only carries the answer to
/// the Android accessibility service, which covers MT5 until the day is
/// unfrozen. A platform without the service simply ignores the calls, so the
/// journal keeps working on iOS and on an Android build without the permission.
class Mt5Freezer {
  static const MethodChannel _channel = MethodChannel('mtl/freezer');

  /// Whether the trader wants MT5 covered at all.
  ///
  /// On by default: the service only ever acts on a soft lock the server has
  /// already decided, so a trader who granted the permissions keeps the cover
  /// they granted. Turning it off stops the app writing an active lock, which
  /// lifts a cover that is up.
  static const String _prefKey = 'mt5.lockEnabled';

  static Future<bool> lockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? true;
  }

  static Future<void> setLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
    if (!enabled) await sync(active: false);
  }

  /// Writes the current lock. [until] is the local day's end, so the service
  /// stops covering MT5 even if the app is never opened again.
  static Future<void> sync({
    required bool active,
    DateTime? until,
    String message = '',
  }) async {
    try {
      await _channel.invokeMethod<void>('sync', <String, Object?>{
        'active': active,
        'until': until?.millisecondsSinceEpoch ?? 0,
        'message': message,
      });
    } catch (_) {
      // The freezer is best-effort; a missing platform channel must not stop
      // the journal from loading.
    }
  }

  /// Whether the trader has granted everything the cover needs.
  static Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// The first permission still missing: `accessibility`, `overlay`, or
  /// `granted` when there is nothing left to ask for.
  static Future<String> accessStatus() async {
    try {
      return await _channel.invokeMethod<String>('accessStatus') ?? 'granted';
    } catch (_) {
      // No bridge (iOS, or a build without the service): report it as granted
      // so nothing nags about a permission that cannot exist here.
      return 'granted';
    }
  }

  /// Opens the settings screen for the first missing permission, so a single
  /// tap on the toggle starts the whole sequence instead of one step of it.
  /// Returns the step it opened, or `granted` when there was nothing to open.
  static Future<String> requestAccess() async {
    try {
      return await _channel.invokeMethod<String>('openSettings') ?? 'granted';
    } catch (_) {
      return 'granted';
    }
  }
}
