import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/serial_task_queue.dart';

/// Coordinates saved/pending voice choices with destructive download cleanup.
abstract final class DownloadedAdhanAssignments {
  static const protectionKey = 'downloaded_adhan_schedule_protection_v1';
  static final _queue = SerialTaskQueue();
  static final Map<String, int> _pending = {};
  static final _notifications = FlutterLocalNotificationsPlugin();
  static bool isPinnedId(String id) =>
      RegExp(r'^kiwifu_adhan_[0-9a-f]{40}$').hasMatch(id);
  static bool isPending(String id) => (_pending[id] ?? 0) > 0;

  static Future<T> protect<T>(
      Iterable<String> ids, Future<T> Function() action) async {
    final keys = ids.where(isPinnedId).toSet();
    for (final id in keys) {
      _pending[id] = (_pending[id] ?? 0) + 1;
    }
    try {
      return await action();
    } finally {
      for (final id in keys) {
        final count = (_pending[id] ?? 1) - 1;
        if (count == 0) {
          _pending.remove(id);
        } else {
          _pending[id] = count;
        }
      }
    }
  }

  static Future<SharedPreferences> _preferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs;
  }

  static Set<String> _saved(SharedPreferences prefs) {
    const keys = {
      'notif_selected_adhan',
      'notif_selected_fajr_adhan',
      'notif_prayer_voice_الفجر',
      'notif_prayer_voice_الظهر',
      'notif_prayer_voice_العصر',
      'notif_prayer_voice_المغرب',
      'notif_prayer_voice_العشاء',
    };
    final result = <String>{};
    for (final key in keys) {
      final value = prefs.get(key);
      if (value != null && value is! String) {
        throw StateError('Saved voice choice was not verifiable');
      }
      if (value is String && isPinnedId(value)) result.add(value);
    }
    return result;
  }

  static Set<String> _scheduled(SharedPreferences prefs) {
    final values = prefs.getStringList(protectionKey) ?? const <String>[];
    if (values.any((id) => !isPinnedId(id))) {
      throw StateError('Saved native sound protection was not verifiable');
    }
    return values.toSet();
  }

  static Future<void> _write(SharedPreferences prefs, Set<String> ids) async {
    final values = ids.toList()..sort();
    if (!await prefs.setStringList(protectionKey, values)) {
      throw StateError('Alert download protection was not saved');
    }
    await prefs.reload();
    final read = _scheduled(prefs);
    if (read.length != ids.length || !read.containsAll(ids)) {
      throw StateError('Alert download protection readback did not match');
    }
  }

  /// Retain both old and new possibilities before preferences or alarms change.
  static Future<void> retain(Iterable<String> ids) => _queue.run(() async {
        final next = ids.where(isPinnedId).toSet();
        if (next.isEmpty) return;
        final prefs = await _preferences();
        await _write(prefs, {..._scheduled(prefs), ...next});
      });

  /// Call only after the whole native prayer range was canceled and rebuilt.
  static Future<void> confirmedPlan(Iterable<String> ids) =>
      _queue.run(() async {
        final prefs = await _preferences();
        final next = ids.where(isPinnedId).toSet();
        final before = _scheduled(prefs);
        if (next.length == before.length && next.containsAll(before)) return;
        await _write(prefs, next);
      });

  /// A failed plan can leave old alarms alive. Keep their files until a complete
  /// rebuild, or until Android confirms no derived prayer notification remains.
  static Future<Set<String>> protectedIds() => _queue.run(() async {
        final prefs = await _preferences();
        final saved = _saved(prefs);
        var scheduled = _scheduled(prefs);
        if (scheduled.difference(saved).isNotEmpty) {
          try {
            final pending = await _notifications.pendingNotificationRequests();
            final active = await _notifications.getActiveNotifications();
            bool inRange(int? id) => id != null && id >= 100 && id <= 399;
            if (!pending.any((item) => inRange(item.id)) &&
                !active.any((item) => inRange(item.id))) {
              await _write(prefs, {});
              scheduled = {};
            }
          } catch (_) {
            /* An unverified native state must retain possible alerts. */
          }
        }
        return {...saved, ...scheduled, ..._pending.keys};
      });
}
