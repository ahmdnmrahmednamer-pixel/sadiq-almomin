import 'dart:async';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  Completer<void>? scheduleGate;
  bool failTimezone = false;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    scheduleGate = null;
    failTimezone = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      calls.add(call);
      if (call.method == 'zonedSchedule' && scheduleGate != null)
        await scheduleGate!.future;
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
            (_) async {
      if (failTimezone) throw PlatformException(code: 'fixture');
      return 'Africa/Cairo';
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });
  for (final mode in ['silent', 'vibrateOnly', 'fullAdhan']) {
    test('cold background snooze honors saved $mode without foreground init',
        () async {
      SharedPreferences.setMockInitialValues({'notif_sound_mode': mode});
      // Dynamic invocation remains awaitable against the old void callback,
      // allowing this regression to fail on actual payload rather than compile.
      final dynamic callback = notificationTapBackground;
      await callback(const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: 'snooze_5',
          payload: 'type=adhan&prayer=العصر'));
      await Future<void>.delayed(Duration.zero);
      final args = calls
          .singleWhere((c) => c.method == 'zonedSchedule')
          .arguments as Map;
      final android = args['platformSpecifics'] as Map;
      expect(
          android['channelId'],
          mode == 'silent'
              ? 'prayer_silent_channel'
              : mode == 'vibrateOnly'
                  ? 'prayer_vibrate_channel'
                  : 'prayer_reminder_channel');
      expect(android['playSound'], mode == 'fullAdhan');
      expect(android['enableVibration'], mode != 'silent');
      expect(args['id'], 995);
      expect(args['payload'], 'type=adhan&prayer=العصر');
      expect(calls.map((c) => c.method), ['zonedSchedule']);
      expect(PrayerNotificationService.instance.soundMode,
          AdhanSoundMode.fullAdhan);
      expect(
          (await SharedPreferences.getInstance()).getString('notif_sound_mode'),
          mode);
    });
  }
  test('callback waits for native snooze scheduling, not fire-and-forget',
      () async {
    SharedPreferences.setMockInitialValues({'notif_sound_mode': 'silent'});
    scheduleGate = Completer<void>();
    var done = false;
    final operation = notificationTapBackground(const NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
            actionId: 'snooze_5'))
        .then((_) {
      done = true;
    });
    while (!calls.any((c) => c.method == 'zonedSchedule')) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(done, false);
    scheduleGate!.complete();
    await operation;
    expect(done, true);
  });
  test('unverifiable timezone stops background snooze without wrong-time alarm',
      () async {
    SharedPreferences.setMockInitialValues({'notif_sound_mode': 'silent'});
    failTimezone = true;
    await notificationTapBackground(const NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: 'snooze_5'));
    expect(calls, isEmpty);
  });
  test('unrecognized background action does not schedule', () async {
    await notificationTapBackground(const NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: 'unknown'));
    expect(calls, isEmpty);
  });
}
