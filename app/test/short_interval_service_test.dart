import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/settings/models/settings_session.dart';

class RejectIntervalStore extends InMemorySharedPreferencesStore {
  RejectIntervalStore()
      : super.withData({
          'flutter.notif_master_enabled': true,
          'flutter.notif_short_salawat_frequency': 'hourly'
        });
  bool reject = true;
  @override
  Future<bool> setValue(String type, String key, Object value) async =>
      reject ? false : await super.setValue(type, key, value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = PrayerNotificationService.instance;
  final pending = <int, Map>{};
  final canceled = <int>[];
  bool permission = true, fail = false;
  Completer<void>? hold;
  setUp(() async {
    permission = true;
    fail = false;
    hold = null;
    pending.clear();
    canceled.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      if (call.method == 'initialize' ||
          call.method == 'canScheduleExactNotifications') return true;
      if (call.method == 'areNotificationsEnabled') return permission;
      if (call.method == 'getNotificationAppLaunchDetails')
        return {'notificationLaunchedApp': false};
      if (call.method == 'cancel') {
        final id = (call.arguments as Map)['id'] as int;
        canceled.add(id);
        pending.remove(id);
      }
      if (call.method == 'periodicallyShowWithDuration') {
        if (hold != null) await hold!.future;
        if (fail) throw PlatformException(code: 'schedule_failed');
        final args = Map.of(call.arguments as Map);
        pending[args['id'] as int] = args;
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
            (_) async => 'Africa/Cairo');
    SharedPreferences.setMockInitialValues({'notif_master_enabled': true});
    await SettingsService.instance.init(forceReload: true);
    await service.init(forceReload: true);
    canceled.clear();
  });
  for (final minutes in [1, 7, 29, 30, 59, 60, 61, 120, 1440]) {
    test(
        'actual $minutes minute duration survives persistence and initialization',
        () async {
      await service.setShortReminderInterval(
          'salawat', (enabled: true, minutes: minutes));
      expect(pending[805]?['repeatIntervalMilliseconds'], minutes * 60000);
      expect(
          service.shortInterval('salawat'), (enabled: true, minutes: minutes));
      await service.init(forceReload: true);
      expect(pending[805]?['repeatIntervalMilliseconds'], minutes * 60000);
      expect(
          service.shortInterval('salawat'), (enabled: true, minutes: minutes));
      expect((pending[805]?['platformSpecifics'] as Map)['sound'],
          'reminder_salawat');
      expect((pending[805]?['platformSpecifics'] as Map)['scheduleMode'],
          'inexactAllowWhileIdle');
    });
  }
  test(
      'legacy serialized presets retain exact frequencies and disabled defaults',
      () async {
    for (final pair in {
      'off': (enabled: false, minutes: 30),
      'halfHourly': (enabled: true, minutes: 30),
      'hourly': (enabled: true, minutes: 60),
      'twoHourly': (enabled: true, minutes: 120),
      'daily': (enabled: true, minutes: 1440)
    }.entries) {
      expect(PrayerNotificationService.decodeShortReminderInterval(pair.key),
          pair.value);
      expect(PrayerNotificationService.encodeShortReminderInterval(pair.value),
          pair.key);
    }
  });
  test('off remembers a custom minute choice without registering sound',
      () async {
    await service
        .setShortReminderInterval('salawat', (enabled: false, minutes: 7));
    await service.init(forceReload: true);
    expect(service.shortInterval('salawat'), (enabled: false, minutes: 7));
    expect(pending[805], isNull);
    expect(service.shortFrequency('salawat'), ShortReminderFrequency.off);
  });
  test(
      'salawat and istighfar remain independent and only stable IDs are changed',
      () async {
    await service
        .setShortReminderInterval('salawat', (enabled: true, minutes: 1));
    await service
        .setShortReminderInterval('istighfar', (enabled: true, minutes: 17));
    expect(pending[805]?['repeatIntervalMilliseconds'], 60000);
    expect(pending[806]?['repeatIntervalMilliseconds'], 1020000);
    expect(canceled.where((id) => id < 805 || id > 806), isEmpty);
  });
  test(
      'malformed or out-of-range persisted custom values are safely off, not rewritten',
      () async {
    for (final raw in [
      'minutes:0',
      'minutes:1441',
      'minutes:x',
      'minutes:-1',
      'off:0',
      'everySecond'
    ]) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notif_short_salawat_frequency', raw);
      await service.init(forceReload: true);
      expect(service.shortInterval('salawat'), (enabled: false, minutes: 30));
      expect(pending[805], isNull);
      expect(prefs.getString('notif_short_salawat_frequency'), raw);
    }
  });
  test(
      'invalid caller interval is rejected before persistence or native changes',
      () async {
    for (final n in [0, -1, 1441]) {
      await expectLater(
          service
              .setShortReminderInterval('salawat', (enabled: true, minutes: n)),
          throwsRangeError);
    }
    expect(pending, isEmpty);
    expect(canceled, isEmpty);
  });
  test(
      'denied permission and failed replacement preserve existing schedule, Apply stays pending',
      () async {
    await service
        .setShortReminderInterval('salawat', (enabled: true, minutes: 60));
    final session = SettingsSession();
    session.shortIntervals['salawat']!.stage((enabled: true, minutes: 1));
    permission = false;
    expect((await session.draft.apply()).success, isFalse);
    expect(pending[805]?['repeatIntervalMilliseconds'], 3600000);
    expect(canceled, isNot(contains(805)));
    permission = true;
    fail = true;
    expect((await session.draft.apply()).success, isFalse);
    expect(pending[805]?['repeatIntervalMilliseconds'], 3600000);
    fail = false;
    expect((await session.draft.apply()).success, isTrue);
    expect(pending[805]?['repeatIntervalMilliseconds'], 60000);
    session.draft.dispose();
  });
  test(
      'a rejected single-key custom write keeps live and durable choice then retries',
      () async {
    final store = RejectIntervalStore();
    SharedPreferencesStorePlatform.instance = store;
    await (await SharedPreferences.getInstance()).reload();
    await service.init(forceReload: true);
    await expectLater(
        service
            .setShortReminderInterval('salawat', (enabled: true, minutes: 1)),
        throwsStateError);
    expect(service.shortInterval('salawat'), (enabled: true, minutes: 60));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('notif_short_salawat_frequency'), 'hourly');
    store.reject = false;
    await service
        .setShortReminderInterval('salawat', (enabled: true, minutes: 1));
    expect(service.shortInterval('salawat'), (enabled: true, minutes: 1));
  });
  test(
      'queued minute change followed by off cannot reinstall the enabled interval',
      () async {
    hold = Completer<void>();
    final first = service
        .setShortReminderInterval('salawat', (enabled: true, minutes: 1));
    await Future<void>.delayed(Duration.zero);
    final second = service
        .setShortReminderInterval('salawat', (enabled: false, minutes: 1));
    hold!.complete();
    await Future.wait([first, second]);
    expect(service.shortInterval('salawat'), (enabled: false, minutes: 1));
    expect(pending[805], isNull);
  });
}
