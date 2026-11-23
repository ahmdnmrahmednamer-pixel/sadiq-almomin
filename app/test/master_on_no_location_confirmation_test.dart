import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/features/settings/models/settings_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('no-location master ON Apply cannot confirm failed fixed daily registration', () async {
    var failMorning = false;
    int? failCancel;
    var failShort = false;
    Completer<void>? dailyGate;
    Completer<void>? dailyEntered;
    var shortAttempts = 0;
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dexterous.com/flutter/local_notifications'), (call) async {
      if (call.method == 'getNotificationAppLaunchDetails') return {'notificationLaunchedApp': false};
      if (call.method == 'cancel' && (call.arguments as Map)['id'] == failCancel) {
        throw PlatformException(code: 'owned_cancel_failed');
      }
      if (call.method == 'periodicallyShowWithDuration') {
        shortAttempts++;
        if (failShort) throw PlatformException(code: 'short_registration_failed');
      }
      if (call.method == 'zonedSchedule' && (call.arguments as Map)['id'] == failCancel) {
        throw PlatformException(code: 'friday_registration_failed');
      }
      if (call.method == 'zonedSchedule' && (call.arguments as Map)['id'] == 801) {
        attempts++;
        if (dailyGate != null) {
          if (!dailyEntered!.isCompleted) dailyEntered!.complete();
          await dailyGate!.future;
        }
        if (failMorning) throw PlatformException(code: 'morning_schedule_failed');
      }
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'), (_) async => 'Africa/Cairo');
    SharedPreferences.setMockInitialValues({'adhan_alerts': true, 'notif_master_enabled': true});
    await SettingsService.instance.init(forceReload: true);
    final service = PrayerNotificationService.instance;
    await service.init(forceReload: true);
    expect(PrayerService.instance.currentData, isNull);
    await SettingsService.instance.toggleAdhanAlerts(false);
    final session = SettingsSession();
    session.master.stage((settings: true, notifications: true));
    failMorning = true;
    final result = await session.draft.apply();
    expect(result.success, isFalse,
        reason: 'Persisted ON intent is not completed fixed reminder registration');
    expect(result.failedKey, 'master');
    expect(session.master.dirty, isTrue);
    final beforeRetry = attempts;
    failMorning = false;
    expect((await session.draft.apply()).success, isTrue);
    expect(attempts, greaterThan(beforeRetry));
    expect(session.master.dirty, isFalse);
    final afterSuccess = attempts;
    expect((await session.draft.apply()).success, isTrue);
    expect(attempts, afterSuccess);
    // A no-location cleanup failure is not hidden by successful daily work.
    for (final id in [100, 804]) {
      await SettingsService.instance.toggleAdhanAlerts(false);
      final cleanupSession = SettingsSession();
      cleanupSession.master.stage((settings: true, notifications: true));
      failCancel = id;
      expect((await cleanupSession.draft.apply()).success, isFalse);
      failCancel = null;
      expect((await cleanupSession.draft.apply()).success, isTrue);
      cleanupSession.draft.dispose();
    }
    // Saved short intent alone cannot certify ON after periodic registration fails.
    await SettingsService.instance.toggleAdhanAlerts(false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_short_salawat_frequency', 'hourly');
    await service.init(forceReload: true);
    final shortSession = SettingsSession();
    shortSession.master.stage((settings: true, notifications: true));
    failShort = true;
    expect((await shortSession.draft.apply()).success, isFalse);
    expect(service.shortReminderScheduleConfirmed('salawat'), isFalse);
    final beforeShortRetry = shortAttempts;
    failShort = false;
    expect((await shortSession.draft.apply()).success, isTrue);
    expect(shortAttempts, greaterThan(beforeShortRetry));
    shortSession.draft.dispose();
    // Awaited daily work blocks Apply; a newer admitted OFF supersedes ON proof.
    await SettingsService.instance.toggleAdhanAlerts(false);
    dailyGate = Completer<void>();
    dailyEntered = Completer<void>();
    var completed = false;
    final enabling = service.toggleMaster(true).then((_) => completed = true);
    await dailyEntered!.future;
    expect(completed, isFalse);
    final disabling = service.toggleMaster(false);
    expect(service.masterOnTransitionCompleted, isFalse);
    dailyGate!.complete();
    await Future.wait([enabling, disabling]);
    dailyGate = null;
    expect(service.masterEnabled, isFalse);
    expect(service.masterOnTransitionCompleted, isFalse);
    expect(service.masterOffTransitionCompleted, isTrue);
    await service.toggleMaster(true);
    expect(service.masterOnTransitionCompleted, isTrue);
    await service.init(forceReload: true);
    expect(service.masterOnTransitionCompleted, isFalse);
    session.draft.dispose();
  });
}
