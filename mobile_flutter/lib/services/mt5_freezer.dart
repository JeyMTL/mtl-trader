import 'package:flutter/services.dart';

/// The soft lock's phone-side enforcement: freeze the MetaTrader 5 app.
///
/// The decision is still the server's. This bridge only carries the answer to
/// the Android accessibility service, which covers MT5 until the day is
/// unfrozen. A platform without the service simply ignores the calls, so the
/// journal keeps working on iOS and on an Android build without the permission.
class Mt5Freezer {
  static const MethodChannel _channel = MethodChannel('mtl/freezer');

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

  /// Whether the trader has enabled the accessibility service.
  static Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system accessibility list so the freezer can be switched on.
  static Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } catch (_) {}
  }
}
