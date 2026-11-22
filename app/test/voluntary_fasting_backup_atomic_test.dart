import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/backup_restore_service.dart';
import 'package:almomin/core/services/voluntary_fasting_service.dart';
import 'voluntary_fasting_persistence_failure_test.dart'
    show RejectingFastStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backup = BackupRestoreService.instance;
  final service = VoluntaryFastingService.instance;
  const type = 'monday_thursday';
  const key = 'flutter.voluntary_fast_progress_v1';
  late RejectingFastStore store;
  late Directory temp;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Map<String, dynamic> envelope(Map<String, dynamic> progress) => {
        'app': 'AlMomin',
        'schema_version': 1,
        'data': {
          'extended_features': {'voluntary_fasting': progress}
        }
      };
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = RejectingFastStore();
    SharedPreferencesStorePlatform.instance = store;
    temp = Directory.systemTemp.createTempSync('fasting-backup-');
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => temp.path);
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_timezone'), (_) async => 'Africa/Cairo');
    messenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async {
      if (call.method == 'initialize' ||
          call.method == 'areNotificationsEnabled' ||
          call.method == 'canScheduleExactNotifications') return true;
      if (call.method == 'getNotificationAppLaunchDetails')
        return {'notificationLaunchedApp': false};
      return null;
    });
    await service.init(forceReload: true);
  });
  tearDown(() {
    for (final name in [
      'plugins.flutter.io/path_provider',
      'flutter_timezone',
      'dexterous.com/flutter/local_notifications'
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
    temp.deleteSync(recursive: true);
  });
  test('legacy-shaped merge and export use authoritative independent counts',
      () async {
    store.values.addAll({
      'flutter.vfast_count_$type': 9,
      'flutter.vfast_date_logs': ['2026-11-20|$type']
    });
    await service.init(forceReload: true);
    expect(
        await service.logFastedDay(type, date: DateTime(2026, 11, 21)), isTrue);
    expect(store.values['flutter.vfast_count_$type'], 9);
    expect(
        await backup.restoreBackup(
            envelope({
              'counts': {type: 3, 'white_days': 2},
              'date_logs': ['2026-11-22|white_days']
            }),
            replaceMode: false),
        isTrue);
    expect(service.getCountForType(type), 10);
    expect(service.getCountForType('white_days'), 2);
    final exported = await backup.exportBackupData();
    expect(backup.validateBackup(jsonEncode(exported)).isValid, isTrue);
    final progress = exported['data']['extended_features']['voluntary_fasting'];
    expect(progress['counts'][type], 10);
    expect(progress['counts']['white_days'], 2);
    expect(progress['date_logs'],
        ['2026-11-21|$type', '2026-11-20|$type', '2026-11-22|white_days']);
    expect(progress['suhoor_reminder'], isTrue);
    expect(progress.containsKey('version'), isFalse);
    expect(
        await backup.restoreBackup(
            envelope({
              'counts': {type: 1},
              'date_logs': []
            }),
            replaceMode: true),
        isTrue);
    expect(service.getCountForType(type), 1);
    expect(service.getCountForType('white_days'), 2);
    expect(service.fastedDateLogs, isEmpty);
  });
  for (final throwing in [false, true]) {
    test(
        'backup cannot report rejected atomic progress as restored throw=$throwing',
        () async {
      expect(await service.logFastedDay(type, date: DateTime(2026, 11, 20)),
          isTrue);
      final before = store.values[key];
      if (throwing) {
        store.throwKey = key;
      } else {
        store.rejectKey = key;
      }
      final data = envelope({
        'counts': {type: 50},
        'date_logs': []
      });
      expect(await backup.restoreBackup(data, replaceMode: true), isFalse);
      expect(store.values[key], before);
      expect(service.getCountForType(type), 1);
      expect(service.fastedDateLogs, ['2026-11-20|$type']);
      store.throwKey = store.rejectKey = null;
      expect(await backup.restoreBackup(data, replaceMode: true), isTrue);
      await service.init(forceReload: true);
      expect(service.getCountForType(type), 50);
      expect(service.fastedDateLogs, isEmpty);
    });
  }
  for (final replaceMode in [false, true]) {
    for (final damaged in <String, Object>{
      'corrupt JSON': '{bad',
      'unreadable preference type': 41,
    }.entries) {
      test(
          'suhoor-only restore ignores damaged progress without changing it mode=$replaceMode ${damaged.key}',
          () async {
        store.values.addAll({
          'flutter.vfast_count_$type': 9,
          'flutter.vfast_date_logs': ['2026-11-20|$type']
        });
        await service.init(forceReload: true);
        expect(await service.logFastedDay(type, date: DateTime(2026, 11, 21)),
            isTrue);
        final counts = service.completedCounts;
        final logs = service.fastedDateLogs;
        store.values[key] = damaged.value;
        await service.init(forceReload: true);
        expect(service.progressLoadFailed, isTrue);
        store.writes.clear();
        expect(
            await backup.restoreBackup(envelope({'suhoor_reminder': false}),
                replaceMode: replaceMode),
            isTrue);
        expect(store.values['flutter.voluntary_fast_suhoor_reminder'], isFalse);
        expect(service.suhoorReminderEnabled, isFalse);
        expect(service.progressLoadFailed, isTrue);
        expect(service.completedCounts, counts);
        expect(service.fastedDateLogs, logs);
        expect(store.values[key], damaged.value);
        expect(store.values['flutter.vfast_count_$type'], 9);
        expect(store.values['flutter.vfast_date_logs'], ['2026-11-20|$type']);
        for (final progress in <Map<String, dynamic>>[
          {
            'counts': {type: 0}
          },
          {'date_logs': <String>[]},
        ]) {
          expect(
              await backup.restoreBackup(envelope(progress),
                  replaceMode: replaceMode),
              isFalse);
          expect(store.values[key], damaged.value);
          expect(service.completedCounts, counts);
          expect(service.fastedDateLogs, logs);
        }
        expect(store.writes, isNot(contains(key)));
      });
    }
  }
  test('old backup progress round trip preserves count not derivable from logs',
      () async {
    final old = envelope({
      'counts': {type: 9},
      'date_logs': ['2026-11-20|$type']
    });
    expect(await backup.restoreBackup(old, replaceMode: true), isTrue);
    final exported = await backup.exportBackupData();
    final progress = exported['data']['extended_features']['voluntary_fasting'];
    expect(progress['counts'][type], 9);
    expect(progress['date_logs'], ['2026-11-20|$type']);
    expect(jsonDecode(store.values[key] as String)['counts'][type], 9);
  });
}
