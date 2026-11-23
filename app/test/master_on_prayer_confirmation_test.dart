import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/settings/models/settings_session.dart';

class OfflineLocation extends Fake implements PrayerLocationProvider {
  @override
  Future<bool> isLocationServiceEnabled() async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'master enable awaits prayer registration and reports failure before retry',
      () async {
    var allowed = true;
    Completer<void>? gate;
    var adhanAttempts = 0;
    final pending = <int>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      if (call.method == 'initialize') return true;
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'areNotificationsEnabled' ||
          call.method == 'canScheduleExactNotifications') {
        return allowed;
      }
      if (call.method == 'cancelAll') pending.clear();
      if (call.method == 'cancel') {
        pending.remove((call.arguments as Map)['id']);
      }
      if (call.method == 'zonedSchedule') {
        final args = call.arguments as Map;
        if (args['payload']?.toString().startsWith('type=adhan') == true) {
          adhanAttempts++;
          if (gate != null) await gate.future;
        }
        pending.add(args['id'] as int);
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
            (_) async => 'Africa/Cairo');
    SharedPreferences.setMockInitialValues({
      'notif_master_enabled': true,
      'location_source': 'gps',
      'last_latitude': 30.0,
      'last_longitude': 31.0,
      'last_city': 'test fixture',
      'location_updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
    await SettingsService.instance.init(forceReload: true);
    final prayers = PrayerService.instance;
    prayers.setLocationProviderForTesting(OfflineLocation());
    final service = PrayerNotificationService.instance;
    try {
      await prayers.init(forceReload: true);
      await service.init(forceReload: true);
      expect(await service.schedulePrayerNotifications(prayers.currentData!),
          PrayerScheduleOutcome.applied);
      expect(pending.any((id) => id >= 100 && id <= 399), isTrue);
      await SettingsService.instance.toggleAdhanAlerts(false);
      expect(pending, isEmpty);
      gate = Completer<void>();
      final before = adhanAttempts;
      var complete = false;
      final session = SettingsSession();
      session.master.stage((settings: true, notifications: true));
      final enabling = session.draft.apply().then((result) {
        complete = true;
        return result;
      });
      while (adhanAttempts == before) {
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(Duration.zero);
      expect(complete, isFalse,
          reason:
              'Master completion must not outrun pending prayer registration');
      gate.complete();
      gate = null;
      expect((await enabling).success, isTrue);
      session.draft.dispose();
      expect(pending.any((id) => id >= 100 && id <= 399), isTrue);
      await SettingsService.instance.toggleAdhanAlerts(false);
      allowed = false;
      final retrySession = SettingsSession();
      retrySession.master.stage((settings: true, notifications: true));
      expect((await retrySession.draft.apply()).success, isFalse);
      expect(retrySession.master.dirty, isTrue);
      expect(service.masterEnabled, isTrue,
          reason:
              'Saved intent is not rolled back after native registration failure');
      expect(service.prayerSchedulingError, isNotNull);
      allowed = true;
      expect((await retrySession.draft.apply()).success, isTrue);
      retrySession.draft.dispose();
      expect(service.prayerSchedulingError, isNull);
      expect(pending.any((id) => id >= 100 && id <= 399), isTrue);
    } finally {
      if (gate != null && !gate.isCompleted) gate.complete();
      prayers.stopLiveTicker();
      prayers.setLocationProviderForTesting(null);
    }
  });
}
