import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/fajr_qiyam_alarm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PrayerInfo prayer(String name, DateTime time) =>
      PrayerInfo(name: name, time: time, formattedTime: 'test');
  PrayerData data(List<PrayerInfo> today, List<PrayerInfo> horizon) => PrayerData(
      latitude: 30,
      longitude: 31,
      locationName: 'test',
      prayers: today,
      notificationPrayers: horizon,
      qiblaDegrees: 0,
      lastUpdated: DateTime.now());

  test('passed last-third selects the next explicitly calculated night', () {
    final now = DateTime.now();
    final firstFajr = prayer('الفجر', now.add(const Duration(minutes: 30)));
    final firstMaghrib = prayer('المغرب', now.subtract(const Duration(hours: 6)));
    final nextMaghrib = prayer('المغرب', now.add(const Duration(hours: 18, minutes: 10)));
    final nextFajr = prayer('الفجر', now.add(const Duration(hours: 24, minutes: 32)));
    final nextNightMinutes = nextFajr.time.difference(nextMaghrib.time).inMinutes;
    final expected = nextMaghrib.time.add(Duration(minutes: (nextNightMinutes * 2 / 3).round()));
    expect(FajrQiyamAlarmService.instance.getLastThirdOfNightStart(data(
      [firstFajr, firstMaghrib],
      [firstFajr, firstMaghrib, nextMaghrib, nextFajr],
    )), expected);
  });

  test('exhausted last-third horizon does not invent another calendar day', () {
    final now = DateTime.now();
    final fajr = prayer('الفجر', now.add(const Duration(minutes: 30)));
    final maghrib = prayer('المغرب', now.subtract(const Duration(hours: 6)));
    expect(FajrQiyamAlarmService.instance.getLastThirdOfNightStart(
      data([fajr, maghrib], [fajr, maghrib])), isNull);
  });
  test('first night uses independently calculated previous sunset', () {
    final sunset = DateTime.utc(2027, 1, 31, 16, 12);
    final fajr = prayer('الفجر', DateTime.utc(2027, 2, 1, 3, 18));
    final now = DateTime.utc(2027, 1, 31, 18);
    final expected = sunset.add(Duration(minutes: (fajr.time.difference(sunset).inMinutes * 2 / 3).round()));
    expect(FajrQiyamAlarmService.nextLastThirdForHorizon([fajr], now, previousMaghrib: sunset), expected);
    expect(FajrQiyamAlarmService.nextLastThirdForHorizon([fajr], now), isNull);
  });
  test('DST offset change uses elapsed duration between actual instants', () {
    final sunset = DateTime.parse('2027-04-29T18:30:00+02:00');
    final fajr = prayer('الفجر', DateTime.parse('2027-04-30T04:30:00+03:00'));
    final now = sunset.add(const Duration(hours: 1));
    expect(FajrQiyamAlarmService.nextLastThirdForHorizon([fajr], now, previousMaghrib: sunset),
      sunset.add(const Duration(hours: 6)));
  });
  test('unordered horizon selects earliest valid future start across year', () {
    final firstSunset = prayer('المغرب', DateTime.utc(2026, 12, 31, 16));
    final firstFajr = prayer('الفجر', DateTime.utc(2027, 1, 1, 4));
    final nextSunset = prayer('المغرب', DateTime.utc(2027, 1, 1, 16, 1));
    final nextFajr = prayer('الفجر', DateTime.utc(2027, 1, 2, 4, 2));
    expect(FajrQiyamAlarmService.nextLastThirdForHorizon(
      [nextFajr, nextSunset, firstFajr, firstSunset], DateTime.utc(2026, 12, 31, 20)),
      DateTime.utc(2027, 1, 1));
  });
  test('missing, inverted or stale sunset cannot revive an unsupported night', () {
    final now = DateTime.utc(2027, 2, 1);
    final fajr = prayer('الفجر', now.add(const Duration(hours: 5)));
    for (final sunset in [now.add(const Duration(hours: 7)), now.subtract(const Duration(days: 2))]) {
      expect(FajrQiyamAlarmService.nextLastThirdForHorizon([fajr], now, previousMaghrib: sunset), isNull);
    }
    expect(FajrQiyamAlarmService.nextLastThirdForHorizon([], now), isNull);
  });

  test('fixed-clock Qiyam keeps its saved time and ID without a prayer horizon', () async {
    SharedPreferences.setMockInitialValues({
      'wake_pre_fajr_enabled': false,
      'wake_qiyam_enabled': true,
      'wake_qiyam_mode': 'fixed_time',
      'wake_qiyam_fixed_hour': 3,
      'wake_qiyam_fixed_minute': 17,
    });
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'), (call) async {
        calls.add(call); return true;
      });
    await FajrQiyamAlarmService.instance.init(forceReload: true);
    final time = FajrQiyamAlarmService.instance.getNextQiyamWakeTime();
    expect(time, isNotNull);
    expect(time!.hour, 3);
    expect(time.minute, 17);
    final scheduled = calls.where((c) => c.method == 'zonedSchedule').toList();
    expect(scheduled, hasLength(1));
    expect((scheduled.single.arguments as Map)['id'], 881);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('wake_qiyam_mode'), 'fixed_time');
    expect(prefs.getInt('wake_qiyam_fixed_minute'), 17);
  });

}
