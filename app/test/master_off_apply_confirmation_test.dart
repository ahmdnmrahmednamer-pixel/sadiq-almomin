import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/features/settings/models/settings_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('master OFF Apply stays pending after failed global cancellation and retries', () async {
    var failGlobalCancel = false;
    var globalCancelCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dexterous.com/flutter/local_notifications'), (call) async {
      if (call.method == 'getNotificationAppLaunchDetails') return {'notificationLaunchedApp': false};
      if (call.method == 'cancelAll') {
        globalCancelCalls++;
        if (failGlobalCancel) throw PlatformException(code: 'global_cancel_failed');
      }
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'), (_) async => 'Africa/Cairo');
    SharedPreferences.setMockInitialValues({'adhan_alerts': true, 'notif_master_enabled': true});
    await SettingsService.instance.init(forceReload: true);
    await PrayerNotificationService.instance.init(forceReload: true);
    final session = SettingsSession();
    session.master.stage((settings: false, notifications: false));
    final matchingSession = SettingsSession();
    matchingSession.master.stage((settings: false, notifications: false));
    failGlobalCancel = true;
    final result = await session.draft.apply();
    expect(result.success, isFalse, reason: 'Persisted OFF intent is not completed global cancellation');
    expect(result.failedKey, 'master');
    expect(session.master.dirty, isTrue);
    final firstAttempts = globalCancelCalls;
    expect(firstAttempts, 1);
    failGlobalCancel = false;
    expect((await session.draft.apply()).success, isTrue);
    expect(globalCancelCalls, firstAttempts + 1, reason: 'Saved matching booleans must not skip effect retry');
    expect(session.master.dirty, isFalse);
    expect((await session.draft.apply()).success, isTrue);
    expect(globalCancelCalls, firstAttempts + 1,
        reason: 'Confirmed OFF is a transition receipt, not a continuous global ban');
    expect((await matchingSession.draft.apply()).success, isTrue);
    expect(globalCancelCalls, firstAttempts + 1,
        reason: 'Another pending matching OFF reuses confirmed transition, not another global cancel');
    final service = PrayerNotificationService.instance;
    expect(service.masterOffTransitionCompleted, isTrue);
    await service.sendTestIqamahNotification();
    expect(service.masterOffTransitionCompleted, isTrue,
        reason: 'Later native work does not undo historical transition completion');
    await service.init(forceReload: true);
    expect(service.masterOffTransitionCompleted, isFalse,
        reason: 'Loaded preferences alone do not prove a transition completed');
    expect(globalCancelCalls, firstAttempts + 1,
        reason: 'Loading OFF must not automatically cancel separately owned reminders');
    matchingSession.draft.dispose();
    session.draft.dispose();
  });
}
