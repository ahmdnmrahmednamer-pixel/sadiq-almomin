import 'package:almomin/core/models/prayer_data.dart';
import 'dart:async';
import 'package:almomin/core/notifications/prayer_renewal.dart';
import 'package:almomin/core/services/fajr_qiyam_alarm_service.dart';
import 'package:almomin/core/services/adhan_sensor_gesture_service.dart';
import 'package:almomin/core/services/prayer_schedule_calculator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 21, 12);
  Map<String, Object> saved() => {
        'location_source': 'gps',
        'last_latitude': 30.0,
        'last_longitude': 31.0,
        'last_city': 'saved fixture',
        'location_updated_at_ms':
            now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        'calculation_method': 'egyptian',
      };
  test(
      'saved GPS stays unchanged and calculation matches pure foreground formula',
      () {
    final values = saved();
    final before = Map.of(values);
    final data = PrayerRenewal.savedData(values, now)!;
    final expected = PrayerScheduleCalculator.calculate(
        latitude: 30,
        longitude: 31,
        locationName: 'saved fixture',
        now: now,
        parameters: PrayerRenewal.parameters('egyptian'));
    expect(data.notificationPrayers!.map((p) => p.time),
        expected.notificationPrayers!.map((p) => p.time));
    expect(data.notificationPrayers, hasLength(42));
    expect(values, before);
  });
  for (final entry in <String, Object>{
    'location_source': 'manual',
    'is_manual_location': true,
    'last_latitude': 91.0,
    'last_longitude': double.nan,
    'last_city': ' ',
    'location_updated_at_ms':
        now.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
  }.entries) {
    test('invalid saved location is not renewed: ${entry.key}', () {
      expect(PrayerRenewal.savedData({...saved(), entry.key: entry.value}, now),
          isNull);
    });
  }
  for (final key in saved().keys.where((k) => k != 'calculation_method')) {
    test('missing provenance field $key never fabricates a location', () {
      final values = saved()..remove(key);
      expect(PrayerRenewal.savedData(values, now), isNull);
    });
  }
  group('bounded headless execution', () {
    final calls = <MethodCall>[];
    const notification =
        MethodChannel('dexterous.com/flutter/local_notifications');
    String? failMethod;
    int? failId;
    Completer<void>? gate;
    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      failMethod = null;
      failId = null;
      gate = null;
      calls.clear();
      SharedPreferences.setMockInitialValues({
        ...saved(),
        'wake_qiyam_mode': 'fixed_time',
        'wake_qiyam_fixed_minutes_v1': 275
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notification, (call) async {
        calls.add(call);
        if (call.method == 'initialize') {
          if (gate != null) await gate!.future;
          return true;
        }
        if (call.method == failMethod &&
            (failId == null || call.arguments['id'] == failId))
          throw PlatformException(code: 'fixture');
        if (call.method == 'areNotificationsEnabled' ||
            call.method == 'canScheduleExactNotifications') return true;
        return null;
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
              (_) async => 'Africa/Cairo');
      // Reset the singleton's saved settings without introducing a new hook.
      await FajrQiyamAlarmService.instance.init(forceReload: true);
      calls.clear();
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notification, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('flutter_timezone'), null);
    });
    test(
        'saved choice reaches 7-day native batch and fixed Qiyam, no prompt or sensor',
        () async {
      final before = (await SharedPreferences.getInstance()).getKeys();
      expect(
          await PrayerRenewal.run(
              headless: true, now: DateTime(2026, 11, 21, 2)),
          true);
      final writes = calls.where((c) => c.method == 'zonedSchedule').toList();
      expect(
          writes
              .where(
                  (c) => c.arguments['id'] >= 100 && c.arguments['id'] <= 399)
              .length,
          greaterThan(100));
      expect(writes.any((c) => c.arguments['id'] == 880), true);
      expect(writes.any((c) => c.arguments['id'] == 881), true);
      expect(calls.map((c) => c.method),
          isNot(contains('requestNotificationsPermission')));
      expect(calls.map((c) => c.method),
          isNot(contains('requestExactAlarmsPermission')));
      expect(calls.map((c) => c.method),
          isNot(contains('getNotificationAppLaunchDetails')));
      expect(AdhanSensorGestureService.instance.isInitialized, false);
      expect((await SharedPreferences.getInstance()).getKeys(), before);
    });
    for (final id in [100, 804, 801, 802, 803, 881]) {
      test('native schedule failure $id cannot be reported as renewed',
          () async {
        failMethod = 'zonedSchedule';
        failId = id;
        expect(
            await PrayerRenewal.run(
                headless: true, now: DateTime(2026, 11, 21, 2)),
            false);
      });
    }
    test('master Adhan off preserves independently enabled Fajr alarm settings',
        () async {
      SharedPreferences.setMockInitialValues({
        ...saved(),
        'notif_master_enabled': false,
        'wake_qiyam_mode': 'fixed_time',
        'wake_qiyam_fixed_minutes_v1': 275
      });
      expect(
          await PrayerRenewal.run(
              headless: true, now: DateTime(2026, 11, 21, 2)),
          true);
      final ids = calls
          .where((c) => c.method == 'zonedSchedule')
          .map((c) => c.arguments['id']);
      expect(ids, [880, 881]);
    });
    test('timezone preparation failure exits before alarm mutation', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
              (_) async => throw PlatformException(code: 'fixture'));
      expect(
          await PrayerRenewal.run(
              headless: true, now: DateTime(2026, 11, 21, 2)),
          false);
      expect(calls, isEmpty);
    });
    test('due fixed-clock renewal defers without cancelling any alarm',
        () async {
      SharedPreferences.setMockInitialValues({
        'wake_qiyam_mode': 'fixed_time',
        'wake_qiyam_fixed_minutes_v1': 275
      });
      expect(
          await PrayerRenewal.run(
              headless: true, now: DateTime(2026, 11, 21, 4, 35)),
          false);
      expect(calls.map((c) => c.method), ['initialize']);
    });
    test('failed range cancellation is not a successful renewed plan',
        () async {
      failMethod = 'cancel';
      failId = 100;
      expect(
          await PrayerRenewal.run(
              headless: true, now: DateTime(2026, 11, 21, 2)),
          false);
    });
    PrayerData fixture(String name, DateTime time) {
      final p = PrayerInfo(name: name, time: time, formattedTime: 'fixture');
      return PrayerData(
          latitude: 30,
          longitude: 31,
          locationName: 'fixture',
          prayers: [p],
          notificationPrayers: [p],
          qiblaDegrees: 0,
          lastUpdated: time);
    }

    for (final minute in [-10, 0, 15, 20]) {
      test('due-transition guard includes prayer offset $minute', () async {
        final noon = DateTime(2026, 11, 21, 12);
        final data = fixture('الظهر', noon);
        expect(
            PrayerRenewal.isTransitionNear(
                data, noon.add(Duration(minutes: minute))),
            true);
      });
    }
    for (final sign in [-1, 1]) {
      test('three-minute guard boundary $sign is inclusive and bounded',
          () async {
        final noon = DateTime(2026, 11, 21, 12);
        final data = fixture('الظهر', noon);
        expect(
            PrayerRenewal.isTransitionNear(
                data, noon.add(Duration(minutes: 3 * sign))),
            true);
        expect(
            PrayerRenewal.isTransitionNear(
                data, noon.add(Duration(seconds: 181 * sign))),
            false);
      });
    }
    test('guard includes sunrise plus Duha and separate pre-Fajr', () async {
      final rise = DateTime(2026, 11, 21, 6);
      expect(
          PrayerRenewal.isTransitionNear(
              fixture('الشروق', rise), rise.add(const Duration(minutes: 25))),
          true);
      final fajr = DateTime(2026, 11, 21, 5);
      expect(
          PrayerRenewal.isTransitionNear(fixture('الفجر', fajr),
              fajr.subtract(const Duration(minutes: 25))),
          true);
    });
    test('same-engine overlapping renewal shares one admitted operation',
        () async {
      gate = Completer<void>();
      final first =
          PrayerRenewal.run(headless: true, now: DateTime(2026, 11, 21, 2));
      while (!calls.any((c) => c.method == 'initialize')) {
        await Future<void>.delayed(Duration.zero);
      }
      final second =
          PrayerRenewal.run(headless: true, now: DateTime(2026, 11, 21, 2));
      gate!.complete();
      expect(await first, true);
      expect(await second, true);
      expect(calls.where((c) => c.method == 'initialize'), hasLength(1));
    });
    test('unverified location renews fixed clock only, not astronomical alarms',
        () async {
      SharedPreferences.setMockInitialValues({
        'wake_qiyam_mode': 'fixed_time',
        'wake_qiyam_fixed_minutes_v1': 275
      });
      expect(
          await PrayerRenewal.run(
              headless: true, now: DateTime(2026, 11, 21, 2)),
          true);
      expect(
          calls
              .where((c) => c.method == 'zonedSchedule')
              .map((c) => c.arguments['id']),
          [881]);
    });
  });
}
