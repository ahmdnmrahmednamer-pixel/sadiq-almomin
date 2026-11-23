import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('daily registration cannot remain confirmed across an in-flight global cancellation', () async {
    Completer<void>? dailyGate;
    Completer<void>? dailyEntered;
    Completer<void>? cancelGate;
    Completer<void>? cancelEntered;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dexterous.com/flutter/local_notifications'), (call) async {
      if (call.method == 'getNotificationAppLaunchDetails') return {'notificationLaunchedApp': false};
      if (call.method == 'zonedSchedule' && (call.arguments as Map)['id'] == 801 && dailyGate != null) {
        if (!dailyEntered!.isCompleted) dailyEntered!.complete();
        await dailyGate!.future;
      }
      if (call.method == 'cancelAll' && cancelGate != null) {
        if (!cancelEntered!.isCompleted) cancelEntered!.complete();
        await cancelGate!.future;
      }
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'), (_) async => 'Africa/Cairo');
    SharedPreferences.setMockInitialValues({'notif_master_enabled': true});
    await SettingsService.instance.init(forceReload: true);
    final service = PrayerNotificationService.instance;
    await service.init(forceReload: true);
    expect(service.adhkarScheduleConfirmed('morning'), isTrue);
    // Pre-admitted daily work is invalidated as soon as global drain begins.
    dailyGate = Completer<void>();
    dailyEntered = Completer<void>();
    final preDrain = service.scheduleAdhkarReminders();
    await dailyEntered!.future;
    final draining = service.cancelAll();
    expect(service.adhkarScheduleConfirmed('morning'), isFalse);
    dailyGate!.complete();
    await preDrain;
    await draining;
    dailyGate = null;
    expect(service.adhkarScheduleConfirmed('morning'), isFalse);
    cancelGate = Completer<void>();
    cancelEntered = Completer<void>();
    final canceling = service.cancelAll();
    await cancelEntered!.future;
    try {
      await service.scheduleAdhkarReminders();
      expect(service.adhkarScheduleConfirmed('morning'), isFalse,
          reason: 'Daily completion inside an active global cancellation is not safe registration proof');
    } finally {
      cancelGate!.complete();
      await canceling;
    }
    expect(service.adhkarScheduleConfirmed('morning'), isFalse);
    cancelGate = null;
    // Mid-drain work that completes only after the drain stays unconfirmed.
    cancelGate = Completer<void>();
    cancelEntered = Completer<void>();
    final secondDrain = service.cancelAll();
    await cancelEntered!.future;
    dailyGate = Completer<void>();
    dailyEntered = Completer<void>();
    final staleDaily = service.scheduleAdhkarReminders();
    await dailyEntered!.future;
    cancelGate!.complete();
    await secondDrain;
    dailyGate!.complete();
    expect(await staleDaily, isFalse);
    expect(service.adhkarScheduleConfirmed('morning'), isFalse);
    dailyGate = null;
    cancelGate = null;
    expect(await service.scheduleAdhkarReminders(), isTrue);
    expect(service.adhkarScheduleConfirmed('morning'), isTrue);
  });
}
