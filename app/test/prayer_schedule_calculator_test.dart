import 'package:adhan_dart/adhan_dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/models/prayer_data.dart';
import 'package:almomin/core/services/prayer_schedule_calculator.dart';

void main() {
  final methods = <String, CalculationParameters Function()>{
    'egyptian': CalculationMethodParameters.egyptian,
    'makkah': CalculationMethodParameters.ummAlQura,
    'mwl': CalculationMethodParameters.muslimWorldLeague,
    'isna': CalculationMethodParameters.northAmerica,
    'karachi': CalculationMethodParameters.karachi,
  };
  for (final method in methods.entries) {
    test(
        '${method.key}: explicit inputs preserve six displayed/42 independently calculated times',
        () {
      for (final now in [
        DateTime(2026, 1, 31, 12),
        DateTime(2026, 12, 31, 23, 59),
        DateTime(2026, 4, 24, 0, 1)
      ]) {
        final coordinates = Coordinates(30, 31);
        final result = PrayerScheduleCalculator.calculate(
            latitude: 30,
            longitude: 31,
            locationName: 'fixture',
            now: now,
            parameters: method.value());
        expect(result.prayers, hasLength(6));
        expect(result.notificationPrayers, hasLength(42));
        expect(result.latitude, 30);
        expect(result.longitude, 31);
        expect(result.locationName, 'fixture');
        expect(result.lastUpdated, now);
        for (var day = 0; day < 7; day++) {
          final expected = PrayerTimes(
              coordinates: coordinates,
              date: DateTime(now.year, now.month, now.day + day),
              calculationParameters: method.value());
          final times = [
            expected.fajr,
            expected.sunrise,
            expected.dhuhr,
            expected.asr,
            expected.maghrib,
            expected.isha
          ].map((t) => t.toLocal()).toList();
          expect(
              result.notificationPrayers!
                  .skip(day * 6)
                  .take(6)
                  .map((p) => p.time)
                  .toList(),
              times);
        }
        expect(result.prayers.map((p) => p.time),
            result.notificationPrayers!.take(6).map((p) => p.time));
        final yesterday = PrayerTimes(
            coordinates: coordinates,
            date: DateTime(now.year, now.month, now.day - 1),
            calculationParameters: method.value());
        expect(result.previousMaghribTime, yesterday.maghrib.toLocal());
        expect(result.qiblaDegrees, Qibla.qibla(coordinates));
        expect(() => result.notificationPrayers!.add(result.prayers.first),
            throwsUnsupportedError);
      }
    });
  }
  test(
      'passed day selects tomorrow Fajr and preserves existing labels/countdown',
      () {
    final now = DateTime(2026, 11, 21, 23, 59);
    final result = PrayerScheduleCalculator.calculate(
        latitude: 30,
        longitude: 31,
        locationName: 'Cairo',
        now: now,
        parameters: CalculationMethodParameters.egyptian());
    final expected = PrayerTimes(
            coordinates: Coordinates(30, 31),
            date: now.add(const Duration(days: 1)),
            calculationParameters: CalculationMethodParameters.egyptian())
        .fajr
        .toLocal();
    expect(result.nextPrayer!.name, 'الفجر (غداً)');
    expect(result.nextPrayer!.time, expected);
    expect(result.timeToNextPrayer, expected.difference(now));
    expect(result.prayers.every((p) => !p.isNext), isTrue);
  });
  test('clock and calculation method are caller owned, no singleton state', () {
    final now = DateTime(2026, 6, 1, 1);
    PrayerData calculate(CalculationParameters parameters) =>
        PrayerScheduleCalculator.calculate(
            latitude: 24.7,
            longitude: 46.7,
            locationName: 'Riyadh',
            now: now,
            parameters: parameters);
    final first = calculate(CalculationMethodParameters.egyptian());
    final other = calculate(CalculationMethodParameters.ummAlQura());
    final again = calculate(CalculationMethodParameters.egyptian());
    expect(first.prayers.first.time, again.prayers.first.time);
    expect(first.prayers.last.time, isNot(other.prayers.last.time));
    expect(first.lastUpdated, now);
    expect(other.lastUpdated, now);
  });
}
