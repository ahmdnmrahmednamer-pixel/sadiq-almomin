import 'dart:async';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/core/services/adhan_sensor_gesture_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  final service = PrayerNotificationService.instance;
  bool? initialized = true;
  bool timezoneFails = false;
  Completer<void>? initializeGate;
  final saved = <String, Object>{
    'notif_master_enabled': false,
    'notif_sound_mode': 'vibrateOnly',
    'notif_selected_adhan': 'saved-voice',
    'notif_pre_reminder': 17,
    'notif_short_salawat_frequency': 'hourly',
    'notif_prayer_الفجر': false,
  };
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    initialized = true;
    timezoneFails = false;
    calls.clear();
    initializeGate = null;
    SharedPreferences.setMockInitialValues(saved);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'initialize') {
        if (initializeGate != null) await initializeGate!.future;
        return initialized;
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
            (_) async {
      if (timezoneFails) throw PlatformException(code: 'timezone');
      return 'Africa/Cairo';
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_timezone'), null);
  });
  test(
      'scheduling init reads choices with no prompt navigation or alarm writes',
      () async {
    expect(AdhanSensorGestureService.instance.isInitialized, isFalse);
    await service.initializeForScheduling();
    expect(calls.map((c) => c.method), ['initialize']);
    expect(AdhanSensorGestureService.instance.isInitialized, isFalse);
    expect(service.masterEnabled, isFalse);
    expect(service.soundMode, AdhanSoundMode.vibrateOnly);
    expect(service.selectedAdhanVoice, 'saved-voice');
    expect(service.preReminderMinutes, 17);
    expect(service.shortFrequency('salawat'), ShortReminderFrequency.hourly);
    expect(service.prayerToggles['الفجر'], isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), saved.keys.toSet());
    for (final e in saved.entries) {
      expect(prefs.get(e.key), e.value);
    }
  });
  for (final result in [false, null]) {
    test('plugin initialization result $result is not success', () async {
      initialized = result;
      await expectLater(service.initializeForScheduling(), throwsA(anything));
      expect(calls.map((c) => c.method), ['initialize']);
    });
  }
  test('timezone failure does not silently schedule in the wrong zone',
      () async {
    timezoneFails = true;
    await expectLater(
        service.initializeForScheduling(), throwsA(isA<PlatformException>()));
    expect(calls, isEmpty);
  });
  test('foreground initialization is not skipped after scheduling preparation',
      () async {
    initializeGate = Completer<void>();
    final background = service.initializeForScheduling();
    while (calls.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final foreground = service.init();
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((c) => c.method), ['initialize']);
    initializeGate!.complete();
    await background;
    await foreground;
    await service.scheduleAdhkarReminders();
    final methods = calls.map((c) => c.method).toList();
    expect(methods, contains('getNotificationAppLaunchDetails'));
    expect(methods, contains('requestNotificationsPermission'));
    expect(methods, contains('requestExactAlarmsPermission'));
    expect(AdhanSensorGestureService.instance.isInitialized, isTrue);
    calls.clear();
    await expectLater(service.initializeForScheduling(), throwsStateError);
    expect(calls, isEmpty);
  });
}
