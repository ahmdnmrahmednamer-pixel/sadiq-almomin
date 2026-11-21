import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Addresses only the posted alert captured on screen entry, never its scheduled
/// alarm. An older screen must not cancel a replacement notification with its ID.
class ActivePrayerAlert {
  static const _channel = MethodChannel('almomin/active_prayer_alert');
  final Map<String, Object>? _identity;
  ActivePrayerAlert._(this._identity);

  static Future<ActivePrayerAlert> capture(int? notificationId) async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        notificationId == null) return ActivePrayerAlert._(null);
    if (!((notificationId >= 100 && notificationId <= 399) ||
        [995, 998, 999].contains(notificationId))) {
      throw const FormatException('Not a prayer alert ID');
    }
    final value = await _channel
        .invokeMapMethod<String, dynamic>('capture', {'id': notificationId});
    if (value == null) return ActivePrayerAlert._(null);
    if (value['id'] != notificationId ||
        value['key'] is! String ||
        value['postTime'] is! int) {
      throw const FormatException('Invalid active notification identity');
    }
    return ActivePrayerAlert._({
      'id': notificationId,
      'key': value['key'] as String,
      'postTime': value['postTime'] as int,
    });
  }

  Future<void> stop() async {
    if (_identity == null) return;
    final result =
        await _channel.invokeMethod<String>('stopCaptured', _identity);
    if (result != 'stopped' && result != 'gone') {
      throw StateError('Active notification stop was not confirmed');
    }
  }
}
