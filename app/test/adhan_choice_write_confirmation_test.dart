import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';

class RefusingAdhanStore extends InMemorySharedPreferencesStore {
  RefusingAdhanStore()
      : super.withData({
          'flutter.notif_prayer_voice_الظهر': 'adhan_makkah',
          'flutter.notif_selected_adhan': 'adhan_makkah',
        });
  bool reject = false;
  int writes = 0;
  int? rejectAt;
  int? throwAfterAt;
  bool lie = false;
  Completer<void>? hold;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes++;
    if (hold != null) await hold!.future;
    if (writes == rejectAt || (reject && key.startsWith('flutter.notif_')))
      return false;
    if (lie) return true;
    final ok = await super.setValue(type, key, value);
    if (writes == throwAfterAt) throw StateError('written then failed');
    return ok;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = PrayerNotificationService.instance;
  late RefusingAdhanStore store;
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      if (call.method == 'initialize' ||
          call.method == 'areNotificationsEnabled' ||
          call.method == 'canScheduleExactNotifications') return true;
      if (call.method == 'getNotificationAppLaunchDetails')
        return {'notificationLaunchedApp': false};
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
            (_) async => 'Africa/Cairo');
    SharedPreferences.setMockInitialValues({});
    store = RefusingAdhanStore();
    SharedPreferencesStorePlatform.instance = store;
    await (await SharedPreferences.getInstance()).reload();
    await service.init(forceReload: true);
    store.reject = true;
  });
  test(
      'failed prayer-voice preference write must not expose an unsaved new choice',
      () async {
    try {
      await service.setPrayerVoice('الظهر', 'adhan_hussary');
    } catch (_) {}
    expect(service.getPrayerVoice('الظهر'), 'adhan_makkah');
    await (await SharedPreferences.getInstance()).reload();
    expect(
        (await SharedPreferences.getInstance())
            .getString('notif_prayer_voice_الظهر'),
        'adhan_makkah');
  });
  test(
      'failed global voice preference write must not expose an unsaved new choice',
      () async {
    try {
      await service.setSelectedAdhanVoice('adhan_hussary');
    } catch (_) {}
    expect(service.selectedAdhanVoice, 'adhan_makkah');
    await (await SharedPreferences.getInstance()).reload();
    expect(
        (await SharedPreferences.getInstance())
            .getString('notif_selected_adhan'),
        'adhan_makkah');
  });
  for (final bulk in [false, true]) {
    test(
        'partial ${bulk ? 'all-prayer' : 'per-prayer'} save restores prior values then retries',
        () async {
      store.reject = false;
      store.rejectAt = bulk ? 3 : 2;
      final before = Map.of(service.prayerAdhanVoices);
      final prefs = await SharedPreferences.getInstance();
      final durable = {for (final key in prefs.getKeys()) key: prefs.get(key)};
      await expectLater(
          bulk
              ? service.setAllPrayersVoice('adhan_hussary')
              : service.setPrayerVoice('الظهر', 'adhan_hussary'),
          throwsStateError);
      await prefs.reload();
      expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, durable);
      expect(service.prayerAdhanVoices, before);
      store.rejectAt = null;
      await (bulk
          ? service.setAllPrayersVoice('adhan_hussary')
          : service.setPrayerVoice('الظهر', 'adhan_hussary'));
      expect(service.getPrayerVoice('الظهر'), 'adhan_hussary');
      if (bulk)
        expect(service.prayerAdhanVoices.values, everyElement('adhan_hussary'));
    });
  }
  test('provider exception after writing rolls back without publishing',
      () async {
    store.reject = false;
    store.throwAfterAt = 1;
    await expectLater(
        service.setPrayerVoice('الظهر', 'adhan_hussary'), throwsStateError);
    expect(service.getPrayerVoice('الظهر'), 'adhan_makkah');
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('notif_prayer_voice_الظهر'), 'adhan_makkah');
  });
  test('queued voice choices cannot publish out of admission order', () async {
    store.reject = false;
    store.hold = Completer<void>();
    final first = service.setPrayerVoice('الظهر', 'adhan_hussary');
    final second = service.setPrayerVoice('الظهر', 'adhan_madinah');
    await Future<void>.delayed(Duration.zero);
    expect(service.getPrayerVoice('الظهر'), 'adhan_makkah');
    store.hold!.complete();
    await Future.wait([first, second]);
    expect(service.getPrayerVoice('الظهر'), 'adhan_madinah');
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('notif_prayer_voice_الظهر'), 'adhan_madinah');
    expect(prefs.getString('notif_selected_adhan'), 'adhan_madinah');
  });
  test('Fajr default failed save stays unchanged and queue accepts retry',
      () async {
    final before = service.selectedFajrVoice;
    await expectLater(
        service.setSelectedFajrVoice('adhan_hussary'), throwsStateError);
    expect(service.selectedFajrVoice, before);
    store.reject = false;
    await service.setSelectedFajrVoice('adhan_hussary');
    expect(service.selectedFajrVoice, 'adhan_hussary');
  });
  test('unknown prayer names do not mutate preferences or schedule', () async {
    store.reject = false;
    await expectLater(service.setPrayerVoice('not-a-prayer', 'adhan_hussary'),
        throwsArgumentError);
    expect(store.writes, 0);
  });
  test('successful provider return without durable write is rejected', () async {
    store.reject = false; store.lie = true;
    await expectLater(service.setPrayerVoice('الظهر','adhan_hussary'), throwsStateError);
    expect(service.getPrayerVoice('الظهر'),'adhan_makkah');
    final prefs = await SharedPreferences.getInstance(); await prefs.reload();
    expect(prefs.getString('notif_prayer_voice_الظهر'),'adhan_makkah');
  });
  test('saved voice is deferred with no known location rather than inventing an alarm', () async {
    store.reject = false;
    await service.setPrayerVoice('الظهر','adhan_hussary');
    expect(service.prayerVoiceConfirmed('الظهر','adhan_hussary'),isTrue);
    expect(service.getPrayerVoice('الظهر'),'adhan_hussary');
  });

}
