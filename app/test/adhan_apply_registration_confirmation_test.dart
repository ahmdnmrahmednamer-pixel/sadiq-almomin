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
      'voice Apply must remain pending when native prayer registration is denied',
      () async {
    var allowed = true;
    var failNative = false;
    var adhanAttempts = 0;
    Map? latestHussary;
    Completer<void>? gate;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      if (call.method == 'initialize') return true;
      if (call.method == 'zonedSchedule' &&
          (call.arguments as Map)['payload']
                  ?.toString()
                  .startsWith('type=adhan') ==
              true) {
        adhanAttempts++;
        if (gate != null) await gate.future;
        if (failNative) throw PlatformException(code: 'schedule_failure');
        final args = call.arguments as Map;
        if ((args['platformSpecifics'] as Map)['sound'] == 'adhan_hussary')
          latestHussary = args;
      }
      if (call.method == 'areNotificationsEnabled' ||
          call.method == 'canScheduleExactNotifications') return allowed;
      if (call.method == 'getNotificationAppLaunchDetails')
        return {'notificationLaunchedApp': false};
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
            (_) async => 'Africa/Cairo');
    SharedPreferences.setMockInitialValues({
      'notif_master_enabled': true,
      'notif_prayer_voice_الظهر': 'adhan_makkah',
      'location_source': 'gps',
      'last_latitude': 30.0,
      'last_longitude': 31.0,
      'last_city': 'test fixture',
      'location_updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
    await SettingsService.instance.init(forceReload: true);
    final prayers = PrayerService.instance;
    prayers.setLocationProviderForTesting(OfflineLocation());
    await prayers.init(forceReload: true);
    final service = PrayerNotificationService.instance;
    await service.init(forceReload: true);
    await service.schedulePrayerNotifications(prayers.currentData!);
    final session = SettingsSession();
    try {
      session.voices['الظهر']!.stage('adhan_hussary');
      allowed = false;
      final result = await session.draft.apply();
      expect(result.success, isFalse,
          reason:
              'Saving a selected name is not proof its Android alarm was registered');
      expect(session.draft.dirty, isTrue);
      allowed = true;
      failNative = true;
      expect((await session.draft.apply()).success, isFalse);
      final attemptsBeforeRetry = adhanAttempts;
      failNative = false;
      gate = Completer<void>();
      var completed = false;
      final retry = session.draft.apply().then((value) {
        completed = true;
        return value;
      });
      while (adhanAttempts == attemptsBeforeRetry) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(completed, isFalse);
      gate.complete();
      expect((await retry).success, isTrue);
      expect(adhanAttempts, greaterThan(attemptsBeforeRetry));
      expect(latestHussary, isNotNull);
      expect(service.prayerVoiceConfirmed('الظهر', 'adhan_hussary'), isTrue);
      expect(session.draft.dirty, isFalse);
      await service.cancelAll();
      expect(service.prayerVoiceConfirmed('الظهر', 'adhan_hussary'), isFalse);
    } finally {
      prayers.stopLiveTicker();
      prayers.setLocationProviderForTesting(null);
      session.draft.dispose();
    }
  });
}
