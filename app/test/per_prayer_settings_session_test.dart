import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Test-only preference backend fault injection.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/features/settings/models/settings_session.dart';

class PrayerRejectingStore extends InMemorySharedPreferencesStore {
  PrayerRejectingStore()
      : super.withData({'flutter.notif_prayer_الفجر': false});
  bool reject = true;
  @override
  Future<bool> setValue(String type, String key, Object value) async =>
      reject ? false : await super.setValue(type, key, value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'notif_master_enabled': false,
      'notif_prayer_الفجر': false,
      'notif_prayer_الظهر': true,
      'notif_prayer_العصر': false,
      'notif_pre_reminder_prayer_الفجر': false,
      'notif_pre_reminder_prayer_الظهر': true,
      'notif_prayer_voice_الفجر': 'adhan_fajr',
      'notif_prayer_voice_العصر': 'adhan_cairo_refaat',
      'bookmarks': <String>['2:255'],
    });
    await SettingsService.instance.init(forceReload: true);
    await PrayerNotificationService.instance.init(forceReload: true);
  });

  test('five prayer groups load saved choices without enabling or writing',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    final s = SettingsSession();
    expect(s.prayerEnabled.keys, SettingsSession.prayers);
    expect(s.prayerEnabled['الفجر']!.value, isFalse);
    expect(s.prayerEnabled['العصر']!.value, isFalse);
    expect(s.prePrayerEnabled['الفجر']!.value, isFalse);
    expect(s.voices['العصر']!.value, 'adhan_cairo_refaat');
    expect(s.draft.dirty, isFalse);
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
    s.draft.dispose();
  });

  test('staging and discard do not save prayer choices', () async {
    final prefs = await SharedPreferences.getInstance();
    final s = SettingsSession();
    s.prayerEnabled['الفجر']!.stage(true);
    s.prePrayerEnabled['الظهر']!.stage(false);
    expect(prefs.getBool('notif_prayer_الفجر'), isFalse);
    expect(prefs.getBool('notif_pre_reminder_prayer_الظهر'), isTrue);
    s.draft.discard();
    expect(s.prayerEnabled['الفجر']!.value, isFalse);
    expect(s.prePrayerEnabled['الظهر']!.value, isTrue);
    s.draft.dispose();
  });

  test(
      'Apply changes only selected prayer flags, leaving voices and master intact',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final s = SettingsSession();
    s.prayerEnabled['الفجر']!.stage(true);
    s.prePrayerEnabled['الظهر']!.stage(false);
    expect((await s.draft.apply()).success, isTrue);
    expect(prefs.getBool('notif_prayer_الفجر'), isTrue);
    expect(prefs.getBool('notif_prayer_العصر'), isFalse);
    expect(prefs.getBool('notif_pre_reminder_prayer_الظهر'), isFalse);
    expect(prefs.getString('notif_prayer_voice_العصر'), 'adhan_cairo_refaat');
    expect(prefs.getBool('notif_master_enabled'), isFalse);
    expect(prefs.getStringList('bookmarks'), ['2:255']);
    s.draft.dispose();
  });
  test('rejected prayer persistence stays pending and retries honestly',
      () async {
    final store = PrayerRejectingStore();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    await PrayerNotificationService.instance.init(forceReload: true);
    final s = SettingsSession();
    s.prayerEnabled['الفجر']!.stage(true);
    final failed = await s.draft.apply();
    expect(failed.success, isFalse);
    expect(failed.failedKey, 'prayer_الفجر');
    expect(s.draft.dirty, isTrue);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getBool('notif_prayer_الفجر'), isFalse);
    store.reject = false;
    expect((await s.draft.apply()).success, isTrue);
    expect(prefs.getBool('notif_prayer_الفجر'), isTrue);
    s.draft.dispose();
  });
}
