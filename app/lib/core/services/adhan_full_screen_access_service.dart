import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Reads Android full-screen notification access, never overlay permission.
/// Null means the current platform could not report access, not a denial.
class AdhanFullScreenAccessService {
  static const _channel = MethodChannel('almomin/adhan_permissions');

  Future<bool?> check() async {
    try {
      return await _channel.invokeMethod<bool>('canUseFullScreenIntent');
    } catch (_) {
      return null;
    }
  }

  /// Called only after a user's explicit settings action. Always read back the
  /// OS state after returning; opening Settings is not proof of permission.
  Future<bool?> request() async {
    try {
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestFullScreenIntentPermission();
    } catch (_) {
      // The readback below remains authoritative, including unavailable state.
    }
    return check();
  }
}
