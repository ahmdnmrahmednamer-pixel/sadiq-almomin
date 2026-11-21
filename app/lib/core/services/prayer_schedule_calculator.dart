import 'package:adhan_dart/adhan_dart.dart';
import '../models/prayer_data.dart';

/// Pure prayer calculation. No settings, permissions, GPS, timers or scheduling.
/// Callers supply the clock and calculation parameters explicitly.
/// UTC prayer instants still convert to the device local zone, as before.
abstract final class PrayerScheduleCalculator {
  static PrayerData calculate({
    required double latitude,
    required double longitude,
    required String locationName,
    required DateTime now,
    required CalculationParameters parameters,
  }) {
    final lat = latitude, lng = longitude, locName = locationName;
    final params = parameters;
    final coords = Coordinates(lat, lng);
    final pt = PrayerTimes(
      coordinates: coords,
      date: now,
      calculationParameters: params,
    );

    // CRITICAL: Convert all adhan_dart UTC times to the device's local timezone
    final rawList = [
      {'name': 'الفجر', 'time': pt.fajr.toLocal()},
      {'name': 'الشروق', 'time': pt.sunrise.toLocal()},
      {'name': 'الظهر', 'time': pt.dhuhr.toLocal()},
      {'name': 'العصر', 'time': pt.asr.toLocal()},
      {'name': 'المغرب', 'time': pt.maghrib.toLocal()},
      {'name': 'العشاء', 'time': pt.isha.toLocal()},
    ];

    // Find next prayer based on local time
    PrayerInfo? nextP;
    Duration minDiff = const Duration(days: 1);

    for (final item in rawList) {
      final pTime = item['time'] as DateTime?;
      if (pTime != null && pTime.isAfter(now)) {
        final diff = pTime.difference(now);
        if (diff < minDiff) {
          minDiff = diff;
          nextP = PrayerInfo(
            name: item['name'] as String,
            time: pTime,
            formattedTime: _formatTime(pTime),
            isNext: true,
          );
        }
      }
    }

    // If all prayers today passed, next is tomorrow's Fajr
    if (nextP == null) {
      final tomorrow = now.add(const Duration(days: 1));
      final tomorrowPt = PrayerTimes(
        coordinates: coords,
        date: tomorrow,
        calculationParameters: params,
      );
      final tFajr = tomorrowPt.fajr.toLocal();
      minDiff = tFajr.difference(now);
      nextP = PrayerInfo(
        name: 'الفجر (غداً)',
        time: tFajr,
        formattedTime: _formatTime(tFajr),
        isNext: true,
      );
    }

    final List<PrayerInfo> resultList = [];
    for (final item in rawList) {
      final pTime = item['time'] as DateTime?;
      final name = item['name'] as String;
      if (pTime != null) {
        resultList.add(PrayerInfo(
          name: name,
          time: pTime,
          formattedTime: _formatTime(pTime),
          isNext: nextP.name == name,
        ));
      }
    }

    // Never repeat today's wall-clock times on later days. Calculate each local
    // calendar date separately, including DST/month/year boundaries.
    final notificationPrayers = <PrayerInfo>[...resultList];
    for (var day = 1; day < 7; day++) {
      final date = DateTime(now.year, now.month, now.day + day);
      final future = PrayerTimes(
        coordinates: coords,
        date: date,
        calculationParameters: params,
      );
      final times = [
        future.fajr,
        future.sunrise,
        future.dhuhr,
        future.asr,
        future.maghrib,
        future.isha
      ];
      for (var i = 0; i < times.length; i++) {
        final time = times[i].toLocal();
        notificationPrayers.add(PrayerInfo(
          name: rawList[i]['name'] as String,
          time: time,
          formattedTime: _formatTime(time),
        ));
      }
    }
    final previousDay = PrayerTimes(
      coordinates: coords,
      date: DateTime(now.year, now.month, now.day - 1),
      calculationParameters: params,
    );
    final qiblaDeg = Qibla.qibla(coords);

    return PrayerData(
      latitude: lat,
      longitude: lng,
      locationName: locName,
      prayers: resultList,
      notificationPrayers: List.unmodifiable(notificationPrayers),
      previousMaghribTime: previousDay.maghrib.toLocal(),
      nextPrayer: nextP,
      timeToNextPrayer: minDiff,
      qiblaDegrees: qiblaDeg,
      lastUpdated: now,
    );
  }

  static String _formatTime(DateTime dt) {
    int hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'م' : 'ص';
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;
    final hStr = hour.toString().padLeft(2, '0');
    return '$hStr:$minute $period';
  }
}
