import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/settings/models/settings_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in ['morning', 'evening', 'sleep']) {
    test('Apply must not report $kind saved as scheduled when scheduling fails',
        () async {
      final id = switch (kind) { 'morning' => 801, 'evening' => 802, _ => 803 };
      const channel =
          MethodChannel('dexterous.com/flutter/local_notifications');
      var fail = false;
      var eveningAttempts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initialize') return true;
        if (call.method == 'getNotificationAppLaunchDetails')
          return {'notificationLaunchedApp': false};
        if (call.method == 'areNotificationsEnabled' ||
            call.method == 'requestNotificationsPermission' ||
            call.method == 'requestExactAlarmsPermission' ||
            call.method == 'canScheduleExactNotifications') return true;
        if (call.method == 'zonedSchedule' &&
            (call.arguments as Map)['id'] == id) {
          eveningAttempts++;
          if (fail) throw PlatformException(code: 'exact_alarms_not_permitted');
        }
        return null;
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
              (_) async => 'Africa/Cairo');
      SharedPreferences.setMockInitialValues(
          {'notif_master_enabled': true, 'notif_evening_adhkar_enabled': true});
      await SettingsService.instance.init(forceReload: true);
      await PrayerNotificationService.instance.init(forceReload: true);
      final session = SettingsSession();
      fail = true;
      final setting = switch (kind) {
        'morning' => session.morningTime,
        'evening' => session.eveningTime,
        _ => session.sleepTime
      };
      setting.stage((hour: 20, minute: 0));
      final result = await session.draft.apply();
      expect(eveningAttempts, greaterThan(0));
      expect(result.success, false,
          reason:
              'Saved time alone must not hide failed evening audio reminder scheduling');
      expect(session.draft.dirty, isTrue);
      final attemptsBeforeRetry = eveningAttempts;
      fail = false;
      final retry = await session.draft.apply();
      expect(retry.success, isTrue);
      expect(eveningAttempts, greaterThan(attemptsBeforeRetry));
      expect(PrayerNotificationService.instance.adhkarScheduleConfirmed(kind),
          isTrue);
      expect(session.draft.dirty, isFalse);
      session.draft.dispose();
    });
  }
}
