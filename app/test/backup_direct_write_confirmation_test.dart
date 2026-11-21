import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/backup_restore_service.dart';

class WriteAuditStore extends InMemorySharedPreferencesStore {
  WriteAuditStore()
      : super.withData({
          'flutter.bookmarks': <String>['1:1']
        });
  String? rejectKey;
  bool throwing = false;
  final writes = <String>[];
  @override
  Future<bool> setValue(String type, String key, Object value) {
    writes.add(key);
    if (key == rejectKey) {
      if (throwing) throw PlatformException(code: 'disk');
      return Future<bool>.value(false);
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WriteAuditStore store;
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'bookmarks': <String>['1:1']
    });
    store = WriteAuditStore();
    SharedPreferencesStorePlatform.instance = store;
    calls.clear();
    messenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (c) async {
      calls.add(c);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'), null));
  Map<String, dynamic> envelope(Map<String, dynamic> data) =>
      {'app': 'AlMomin', 'schema_version': 1, 'data': data};
  final cases = <String, Map<String, dynamic>>{
    'bookmarks': {},
    'mushaf_font_size': {
      'settings': {'mushaf_font_size': 30.0}
    },
    'theme_mode': {
      'settings': {'theme_mode': 'dark'}
    },
    'adhan_alerts': {
      'settings': {'adhan_alerts': false}
    },
    'hijri_adjustment_days': {
      'settings': {'hijri_adjustment_days': 1}
    },
    'active_khatma_plan': {
      'khatma': {'currentPage': 30}
    },
    'prayer_tracker_records_v1': {
      'prayer_tracker': {
        '2026-11-21': {'fajr': true}
      }
    },
    'scholars_fav_profiles': {
      'scholars_library': {
        'scholars_fav_profiles': ['one']
      }
    },
    'stories_favorites': {
      'extended_features': {
        'stories_favorites': ['one']
      }
    },
    'hajj_tawaf_lap': {
      'extended_features': {
        'hajj_umrah': {'tawaf_lap': 3}
      }
    },
    'notif_shake_to_stop': {
      'extended_features': {
        'sensor_gestures': {'notif_shake_to_stop': false}
      }
    },
  };
  for (final entry in cases.entries) {
    for (final throwing in [false, true]) {
      test(
          '${entry.key} rejected direct write stops and reloads cache throw=$throwing',
          () async {
        store.rejectKey = 'flutter.${entry.key}';
        store.throwing = throwing;
        final result = await BackupRestoreService.instance.restoreBackup(
            envelope({
              'bookmarks': ['2:255'],
              ...entry.value
            }),
            replaceMode: false);
        expect(result, false);
        expect(store.writes.last, 'flutter.${entry.key}');
        final prefs = await SharedPreferences.getInstance();
        // The rejected value must not survive in the plugin's optimistic cache.
        expect(
            prefs.get(entry.key), entry.key == 'bookmarks' ? ['1:1'] : isNull);
        expect(calls, isEmpty);
      });
    }
  }
  for (final key in ['active_khatma_plan', 'prayer_tracker_records_v1']) {
    test('$key existing merge parsing cannot swallow rejected storage',
        () async {
      await store.setValue('String', 'flutter.$key',
          jsonEncode(key == 'active_khatma_plan' ? {'currentPage': 1} : {}));
      store.writes.clear();
      store.rejectKey = 'flutter.$key';
      final result = await BackupRestoreService.instance.restoreBackup(
          envelope({
            'bookmarks': ['2:255'],
            ...cases[key]!
          }),
          replaceMode: false);
      expect(result, false);
      expect(store.writes.last, 'flutter.$key');
      expect(calls, isEmpty);
    });
  }
  test(
      'failure after earlier writes reports partial failure without claiming rollback',
      () async {
    store.rejectKey = 'flutter.theme_mode';
    final result = await BackupRestoreService.instance.restoreBackup(
        envelope({
          'bookmarks': ['2:255'],
          'settings': {'mushaf_font_size': 30.0, 'theme_mode': 'dark'}
        }),
        replaceMode: false);
    expect(result, false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('bookmarks'), ['1:1', '2:255']);
    expect(prefs.getDouble('mushaf_font_size'), 30);
    expect(prefs.getString('theme_mode'), isNull);
    expect(calls, isEmpty);
  });
  test(
      'retry after a rejected first write completes and persists the requested data',
      () async {
    final backup = envelope({
      'bookmarks': ['2:255'],
      'settings': {'mushaf_font_size': 30.0},
      'extended_features': {
        'sensor_gestures': {'notif_flip_to_mute': false}
      }
    });
    store.rejectKey = 'flutter.bookmarks';
    expect(
        await BackupRestoreService.instance
            .restoreBackup(backup, replaceMode: false),
        false);
    expect(calls, isEmpty);
    store.rejectKey = null;
    expect(
        await BackupRestoreService.instance
            .restoreBackup(backup, replaceMode: false),
        true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getStringList('bookmarks'), ['1:1', '2:255']);
    expect(prefs.getDouble('mushaf_font_size'), 30.0);
    expect(prefs.getBool('notif_flip_to_mute'), false);
  });
}
