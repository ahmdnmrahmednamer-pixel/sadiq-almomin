import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/fajr_qiyam_alarm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PrayerInfo fajr(DateTime time) =>
      PrayerInfo(name: 'الفجر', time: time, formattedTime: 'test');
  PrayerData data(List<PrayerInfo> today, List<PrayerInfo> horizon) =>
      PrayerData(
        latitude: 30,
        longitude: 31,
        locationName: 'test',
        prayers: today,
        notificationPrayers: horizon,
        qiblaDegrees: 0,
        lastUpdated: DateTime.now(),
      );

  test('next Fajr uses the separately calculated next date, not today plus24h',
      () {
    final now = DateTime.now();
    final previous = fajr(now.subtract(const Duration(hours: 1)));
    final next = fajr(now.add(const Duration(hours: 23, minutes: 2)));
    expect(
        FajrQiyamAlarmService.instance
            .getNextFajrTime(data([previous], [previous, next])),
        next.time);
  });

  test('passed pre-Fajr offset selects the next calculated Fajr offset', () {
    final now = DateTime.now();
    final today = fajr(now.add(const Duration(minutes: 1)));
    final next = fajr(now.add(const Duration(days: 1, minutes: 4)));
    final service = FajrQiyamAlarmService.instance;
    expect(service.getNextPreFajrWakeTime(data([today], [today, next])),
        next.time.subtract(Duration(minutes: service.preFajrMinutesBefore)));
  });

  test('exhausted explicit calendar horizon does not revive an old Fajr', () {
    final previous = fajr(DateTime.now().subtract(const Duration(hours: 1)));
    expect(
        FajrQiyamAlarmService.instance
            .getNextFajrTime(data([previous], [previous])),
        isNull);
  });
  test(
      'before-Fajr Qiyam offset also uses the next independently calculated date',
      () async {
    SharedPreferences.setMockInitialValues({
      'wake_qiyam_mode': 'before_fajr',
      'wake_qiyam_minutes_before': 60,
    });
    final service = FajrQiyamAlarmService.instance;
    await service.init(forceReload: true);
    final now = DateTime.now();
    final today = fajr(now.add(const Duration(minutes: 1)));
    final next = fajr(now.add(const Duration(days: 1, minutes: 4)));
    expect(service.getNextQiyamWakeTime(data([today], [today, next])),
        next.time.subtract(const Duration(minutes: 60)));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('wake_qiyam_minutes_before'), 60);
    expect(prefs.getKeys(), {'wake_qiyam_mode', 'wake_qiyam_minutes_before'});
  });

  test('horizon selection is chronological even if its input order changes',
      () {
    final now = DateTime.now();
    final first = fajr(now.add(const Duration(hours: 2)));
    final later = fajr(now.add(const Duration(days: 1, hours: 2)));
    expect(
        FajrQiyamAlarmService.instance
            .getNextFajrTime(data([first], [later, first])),
        first.time);
  });

  test('an explicitly empty horizon does not fall back to invented dates', () {
    final previous = fajr(DateTime.now().subtract(const Duration(hours: 1)));
    expect(FajrQiyamAlarmService.instance.getNextFajrTime(data([previous], [])),
        isNull);
  });
}
