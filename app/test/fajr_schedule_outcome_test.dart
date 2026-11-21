import 'dart:async';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:almomin/core/services/fajr_qiyam_alarm_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final dynamic service = FajrQiyamAlarmService.instance;
  final calls = <MethodCall>[];
  String? failMethod;
  int? failId;
  Completer<void>? gate;
  PrayerData data() {
    final fajr = PrayerInfo(
        name: 'الفجر',
        time: DateTime.now()
            .add(const Duration(hours: 5))
            .copyWith(millisecond: 0, microsecond: 0),
        formattedTime: 'fixture');
    return PrayerData(
        latitude: 30,
        longitude: 31,
        locationName: 'fixture',
        prayers: [fajr],
        notificationPrayers: [fajr],
        qiblaDegrees: 0,
        lastUpdated: DateTime.now());
  }

  Future<void> configure({bool fixed = false, bool enabled = true}) async {
    SharedPreferences.setMockInitialValues({
      'wake_pre_fajr_enabled': enabled,
      'wake_qiyam_enabled': enabled,
      'wake_qiyam_mode': fixed ? 'fixed_time' : 'before_fajr',
      'wake_pre_fajr_minutes': 25,
      'wake_qiyam_minutes_before': 60,
    });
    await service.init(forceReload: true);
    calls.clear();
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Africa/Cairo'));
    calls.clear();
    failMethod = null;
    failId = null;
    gate = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final args = call.arguments as Map?;
      if (call.method == 'cancel' && gate != null) await gate!.future;
      if (call.method == failMethod && args?['id'] == failId)
        throw PlatformException(code: 'fixture-failure');
      return null;
    });
    await configure();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  for (final failure in [
    ('cancel', 880),
    ('cancel', 881),
    ('zonedSchedule', 880),
    ('zonedSchedule', 881)
  ]) {
    test('schedule exposes ${failure.$1} ${failure.$2} failure', () async {
      failMethod = failure.$1;
      failId = failure.$2;
      final dynamic result = await service.scheduleAlarms(data());
      expect(result.toString(), 'AlarmScheduleOutcome.failed');
    });
  }
  test('successful schedule preserves IDs and independently calculated offsets',
      () async {
    final fixture = data();
    final dynamic result = await service.scheduleAlarms(fixture);
    expect(result.toString(), 'AlarmScheduleOutcome.applied');
    final writes = calls.where((c) => c.method == 'zonedSchedule').toList();
    expect(writes.map((c) => c.arguments['id']), [880, 881]);
    expect(writes.map((c) => c.arguments['timeZoneName']), ['UTC', 'UTC']);
    expect(
        DateTime.parse("${writes[0].arguments['scheduledDateTime']}Z"),
        fixture.prayers.single.time
            .subtract(const Duration(minutes: 25))
            .toUtc());
    expect(
        DateTime.parse("${writes[1].arguments['scheduledDateTime']}Z"),
        fixture.prayers.single.time
            .subtract(const Duration(minutes: 60))
            .toUtc());
  });
  test('disabled plan applies cancellation without claiming an alarm exists',
      () async {
    await configure(enabled: false);
    final dynamic result = await service.scheduleAlarms(data());
    expect(result.toString(), 'AlarmScheduleOutcome.applied');
    expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
    expect(calls.map((c) => c.arguments['id']), [880, 881]);
  });
  test('unknown location sync exposes cancellation failure', () async {
    failMethod = 'cancel';
    failId = 880;
    final dynamic result = await service.syncWithLocationAvailability();
    expect(result.toString(), 'AlarmScheduleOutcome.failed');
  });
  test('unknown location retains fixed clock and exposes its schedule failure',
      () async {
    await configure(fixed: true);
    failMethod = 'zonedSchedule';
    failId = 881;
    final dynamic result = await service.syncWithLocationAvailability();
    expect(result.toString(), 'AlarmScheduleOutcome.failed');
    expect(
        calls.where((c) => c.method == 'cancel').map((c) => c.arguments['id']),
        [880]);
  });
  test('atomic fixed time reaches OS payload and survives reload', () async {
    await configure(fixed: true);
    expect(await service.setQiyamFixedTime(4, 35), true);
    final write = calls.lastWhere((c) => c.method == 'zonedSchedule');
    final scheduled =
        DateTime.parse('${write.arguments['scheduledDateTime']}Z').toLocal();
    expect(write.arguments['id'], 881);
    expect(scheduled.hour, 4);
    expect(scheduled.minute, 35);
    calls.clear();
    await service.init(forceReload: true);
    final restored = calls.lastWhere((c) => c.method == 'zonedSchedule');
    expect(restored.arguments['scheduledDateTime'],
        write.arguments['scheduledDateTime']);
    expect(restored.arguments['id'], 881);
  });
  test('superseded operation cannot report applied or enqueue stale alarms',
      () async {
    gate = Completer<void>();
    final first = service.scheduleAlarms(data());
    while (calls.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final second = service.scheduleAlarms(data());
    gate!.complete();
    final dynamic oldResult = await first;
    final dynamic newResult = await second;
    expect(oldResult.toString(), 'AlarmScheduleOutcome.superseded');
    expect(newResult.toString(), 'AlarmScheduleOutcome.applied');
    expect(calls.where((c) => c.method == 'zonedSchedule').length, 2);
  });
}
