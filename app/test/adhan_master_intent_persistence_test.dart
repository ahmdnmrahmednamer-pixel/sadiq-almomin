// Test-only selective preference fault injection.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';

class SelectiveAdhanStore extends InMemorySharedPreferencesStore {
  SelectiveAdhanStore()
      : super.withData({
          'flutter.adhan_alerts': true,
          'flutter.notif_master_enabled': true,
        });
  bool reject = true, afterWrite = false, throwing = false, failReads = false;
  bool failReadAfterWrite = false;
  @override
  Future<Map<String, Object>> getAll() async {
    if (failReads) throw PlatformException(code: 'read_failed');
    return super.getAll();
  }
  Completer<void>? hold, entered;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.adhan_alerts') {
      if (failReadAfterWrite) failReads = true;
      if (hold != null) {
        if (!entered!.isCompleted) entered!.complete();
        await hold!.future;
      }
      if (throwing) throw PlatformException(code: 'intent_write_failed');
      if (reject) {
        if (afterWrite) await super.setValue(type, key, value);
        return false;
      }
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'rejected adhan intent write cannot disable native master or change live state',
      () async {
    final store = SelectiveAdhanStore();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      calls.add(call.method);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
            (_) async => 'Africa/Cairo');
    final settings = SettingsService.instance;
    final notifications = PrayerNotificationService.instance;
    await settings.init(forceReload: true);
    await notifications.init(forceReload: true);
    calls.clear();
    await expectLater(settings.toggleAdhanAlerts(false), throwsStateError);
    expect(settings.adhanAlertsEnabled, isTrue);
    expect(notifications.masterEnabled, isTrue);
    expect(calls, isEmpty,
        reason: 'Rejected intent cannot begin native effects');
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getBool('adhan_alerts'), isTrue);
    expect(prefs.getBool('notif_master_enabled'), isTrue);
    store.reject = false;
    await settings.toggleAdhanAlerts(false);
    expect(settings.adhanAlertsEnabled, isFalse);
    expect(notifications.masterEnabled, isFalse);
    expect(calls, contains('cancelAll'));
    store.reject = true;
    store.afterWrite = true;
    calls.clear();
    await expectLater(settings.toggleAdhanAlerts(true), throwsStateError);
    expect(settings.adhanAlertsEnabled, isTrue,
        reason: 'A false return after persistence reports actual saved intent');
    expect(notifications.masterEnabled, isFalse,
        reason: 'Uncertain intent write cannot begin native registration');
    expect(calls, isEmpty);
    store.reject = false;
    store.afterWrite = false;
    store.throwing = true;
    await expectLater(
        settings.toggleAdhanAlerts(false), throwsA(isA<PlatformException>()));
    expect(calls, isEmpty);
    store.throwing = false;
    store.hold = Completer<void>();
    store.entered = Completer<void>();
    final first = settings.toggleAdhanAlerts(true);
    await store.entered!.future;
    final second = settings.toggleAdhanAlerts(false);
    store.hold!.complete();
    await Future.wait([first, second]);
    expect(settings.adhanAlertsEnabled, isFalse);
    expect(notifications.masterEnabled, isFalse);
    await prefs.reload();
    expect(prefs.getBool('adhan_alerts'), isFalse);
    expect(prefs.getBool('notif_master_enabled'), isFalse);
    calls.clear();
    store.reject = true;
    store.failReadAfterWrite = true;
    await expectLater(settings.toggleAdhanAlerts(true), throwsStateError);
    expect(settings.adhanAlertsEnabled, isFalse,
        reason: 'Failed reload cannot publish optimistic cached write as saved');
    expect(notifications.masterEnabled, isFalse);
    expect(calls, isEmpty);
    store.failReads = false;
    store.failReadAfterWrite = false;

  });
}
