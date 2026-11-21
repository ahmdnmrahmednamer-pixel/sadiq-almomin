import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/settings/models/settings_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = PrayerNotificationService.instance;
  var notifications = true;
  var exact = true;
  var permissionThrows = false;
  int? failedCancel;
  final scheduled = <int>[];
  final canceled = <int>[];
  Completer<void>? block;
  Completer<void>? entered;
  setUp(() async {
    notifications = exact = true;
    permissionThrows = false;
    failedCancel = null;
    scheduled.clear();
    canceled.clear();
    block = entered = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return {'notificationLaunchedApp': false};
        case 'requestNotificationsPermission':
        case 'requestExactAlarmsPermission':
          return true;
        case 'areNotificationsEnabled':
          if (permissionThrows)
            throw PlatformException(code: 'permission_query_failed');
          return notifications;
        case 'canScheduleExactNotifications':
          return exact;
        case 'zonedSchedule':
          final id = (call.arguments as Map)['id'] as int;
          scheduled.add(id);
          if (id == 801 && block != null) {
            if (!entered!.isCompleted) entered!.complete();
            await block!.future;
          }
          return null;
        case 'cancel':
          final id = (call.arguments as Map)['id'] as int;
          canceled.add(id);
          if (id == failedCancel)
            throw PlatformException(code: 'cancel_failed');
          return null;
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
            (_) async => 'Africa/Cairo');
    SharedPreferences.setMockInitialValues({'notif_master_enabled': true});
    await SettingsService.instance.init(forceReload: true);
    await service.init(forceReload: true);
    await service.scheduleAdhkarReminders();
    scheduled.clear();
    canceled.clear();
  });
  for (final permission in ['notifications', 'exact']) {
    test(
        '$permission denied prevents native registration and keeps Apply pending until retry',
        () async {
      if (permission == 'notifications') {
        notifications = false;
      } else {
        exact = false;
      }
      final session = SettingsSession();
      session.eveningTime.stage((hour: 20, minute: 0));
      expect((await session.draft.apply()).success, isFalse);
      expect(scheduled.where((id) => id >= 801 && id <= 803), isEmpty);
      expect(canceled.where((id) => id >= 801 && id <= 803), isEmpty);
      expect(service.adhkarScheduleConfirmed('evening'), isFalse);
      notifications = exact = true;
      expect((await session.draft.apply()).success, isTrue);
      expect(scheduled, contains(802));
      session.draft.dispose();
    });
  }
  test(
      'disabling cancels even while permission for other enabled reminders is denied',
      () async {
    exact = false;
    final session = SettingsSession();
    session.evening.stage(false);
    expect((await session.draft.apply()).success, isTrue);
    expect(canceled, contains(802));
    expect(scheduled, isEmpty);
    expect(service.adhkarScheduleConfirmed('evening'), isTrue);
    expect(service.adhkarScheduleConfirmed('morning'), isFalse);
    session.draft.dispose();
  });
  test(
      'failed cancellation cannot pass Apply and same-value retry cancels again',
      () async {
    failedCancel = 802;
    final session = SettingsSession();
    session.evening.stage(false);
    expect((await session.draft.apply()).success, isFalse);
    final count = canceled.where((id) => id == 802).length;
    failedCancel = null;
    expect((await session.draft.apply()).success, isTrue);
    expect(canceled.where((id) => id == 802).length, greaterThan(count));
    session.draft.dispose();
  });
  test(
      'a disabled reminder time saves via cancellation without sound registration',
      () async {
    await service.toggleEveningAdhkar(false);
    scheduled.clear();
    canceled.clear();
    final session = SettingsSession();
    session.eveningTime.stage((hour: 20, minute: 0));
    expect((await session.draft.apply()).success, isTrue);
    expect(scheduled, isNot(contains(802)));
    expect(canceled, contains(802));
    session.draft.dispose();
  });
  test('queued replacement cannot confirm stale settings as the new schedule',
      () async {
    block = Completer<void>();
    entered = Completer<void>();
    final first = service.setMorningAdhkarTime(6, 10);
    await entered!.future;
    final second = service.setMorningAdhkarTime(8, 20);
    await Future<void>.delayed(Duration.zero);
    expect(service.adhkarScheduleConfirmed('morning'), isFalse);
    block!.complete();
    await Future.wait([first, second]);
    expect(service.adhkarScheduleConfirmed('morning'), isTrue);
    expect(service.morningAdhkarHour, 8);
    expect(service.morningAdhkarMinute, 20);
    block = null;
  });
  test('cancelAll invalidates registration proof', () async {
    expect(service.adhkarScheduleConfirmed('evening'), isTrue);
    await service.cancelAll();
    expect(service.adhkarScheduleConfirmed('evening'), isFalse);
  });
  test(
      'permission query failure remains unconfirmed and does not remove enabled schedules',
      () async {
    permissionThrows = true;
    expect(await service.scheduleAdhkarReminders(), isFalse);
    expect(service.adhkarScheduleConfirmed('evening'), isFalse);
    expect(scheduled, isEmpty);
    expect(canceled.where((id) => id >= 801 && id <= 803), isEmpty);
    permissionThrows = false;
    expect(await service.scheduleAdhkarReminders(), isTrue);
    expect(service.adhkarScheduleConfirmed('evening'), isTrue);
  });
  test(
      'master-off time edit confirms cancellation, never enables reminders implicitly',
      () async {
    await service.toggleMaster(false);
    scheduled.clear();
    canceled.clear();
    final session = SettingsSession();
    session.eveningTime.stage((hour: 20, minute: 0));
    expect((await session.draft.apply()).success, isTrue);
    expect(service.masterEnabled, isFalse);
    expect(scheduled, isEmpty);
    expect(canceled, containsAll([801, 802, 803]));
    expect(service.adhkarScheduleConfirmed('evening'), isTrue);
    session.draft.dispose();
  });
  for (final kind in ['morning', 'evening', 'sleep']) {
    test(
        'enabling $kind cannot pass Apply after registration permission failure',
        () async {
      switch (kind) {
        case 'morning':
          await service.toggleMorningAdhkar(false);
        case 'evening':
          await service.toggleEveningAdhkar(false);
        case 'sleep':
          await service.toggleSleepAdhkar(false);
      }
      final session = SettingsSession();
      final flag = switch (kind) {
        'morning' => session.morning,
        'evening' => session.evening,
        _ => session.sleep,
      };
      flag.stage(true);
      exact = false;
      expect((await session.draft.apply()).success, isFalse);
      expect(session.draft.dirty, isTrue);
      exact = true;
      expect((await session.draft.apply()).success, isTrue);
      expect(service.adhkarScheduleConfirmed(kind), isTrue);
      session.draft.dispose();
    });
  }
}
