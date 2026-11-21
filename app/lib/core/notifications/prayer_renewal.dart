import 'dart:async';
import 'package:adhan_dart/adhan_dart.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/prayer_schedule_calculator.dart';
import '../services/prayer_service.dart';
import '../services/settings_service.dart';
import '../services/fajr_qiyam_alarm_service.dart';
import 'prayer_notification_service.dart';

/// The native coordinator uses the existing UI engine, or a single bounded
/// headless engine when no UI engine exists. No GPS requests or permissions.
abstract final class PrayerRenewal {
  static const channel = MethodChannel('almomin/prayer_renewal');
  static Future<bool>? _active;

  static void bindForeground() {
    channel.setMethodCallHandler((call) async {
      if (call.method != 'renew') throw MissingPluginException();
      return run(headless: false);
    });
    // A failed native registration must not prevent normal application startup.
    unawaited(channel.invokeMethod<bool>('register').catchError((_) => false));
  }

  static Future<bool> run({required bool headless, DateTime? now}) {
    final active = _active;
    if (active != null) return active;
    final future = _run(headless: headless, now: now);
    _active = future;
    return future.whenComplete(() {
      if (identical(_active, future)) _active = null;
    });
  }

  static CalculationParameters parameters(String method) => switch (method) {
        'makkah' => CalculationMethodParameters.ummAlQura(),
        'mwl' => CalculationMethodParameters.muslimWorldLeague(),
        'isna' => CalculationMethodParameters.northAmerica(),
        'karachi' => CalculationMethodParameters.karachi(),
        _ => CalculationMethodParameters.egyptian(),
      };

  /// Matches the app's existing persisted-GPS validity rules. Old GPS remains
  /// saved GPS, never a claim of a fresh/live location acquisition.
  static PrayerData? savedData(Map<String, Object?> values, DateTime now) {
    final lat = values['last_latitude'], lng = values['last_longitude'];
    final city = values['last_city'], stamp = values['location_updated_at_ms'];
    if (values['location_source'] != 'gps' ||
        values['is_manual_location'] == true ||
        lat is! double ||
        lng is! double ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180 ||
        city is! String ||
        city.trim().isEmpty ||
        stamp is! int ||
        !PrayerService.isValidFixTimestampMs(stamp, now: now)) return null;
    return PrayerScheduleCalculator.calculate(
        latitude: lat,
        longitude: lng,
        locationName: city,
        now: now,
        parameters: parameters(values['calculation_method'] is String
            ? values['calculation_method'] as String
            : 'egyptian'));
  }

  static PrayerData? _currentCalculatedData() {
    final current = PrayerService.instance.currentData;
    if (current == null) return null;
    return PrayerScheduleCalculator.calculate(
        latitude: current.latitude,
        longitude: current.longitude,
        locationName: current.locationName,
        now: DateTime.now(),
        parameters: parameters(SettingsService.instance.calculationMethod));
  }

  /// A renewal is maintenance, never a reason to cancel an alert around its
  /// due instant. Three minutes covers this job's ninety-second native bound.
  /// Returning false asks Android for a later backoff attempt, without writes.
  static bool isTransitionNear(PrayerData? data, DateTime now) {
    final n = PrayerNotificationService.instance;
    final f = FajrQiyamAlarmService.instance;
    const margin = Duration(minutes: 3);
    bool near(DateTime time) => time.difference(now).abs() <= margin;
    final prayers =
        data?.notificationPrayers ?? data?.prayers ?? <PrayerInfo>[];
    if (n.masterEnabled) {
      for (final p in prayers) {
        final time = p.time;
        if (n.isPrayerEnabled(p.name)) {
          if (near(time)) return true;
          if (!p.name.contains('الشروق')) {
            if (n.preReminderEnabled &&
                n.isPreReminderPrayerEnabled(p.name) &&
                near(time.subtract(Duration(minutes: n.preReminderMinutes))))
              return true;
            if (n.iqamahReminderEnabled &&
                near(time.add(Duration(minutes: n.iqamahOffsetMinutes))))
              return true;
            if (n.postPrayerAdhkarReminderEnabled &&
                near(time.add(Duration(
                    minutes: n.iqamahOffsetMinutes +
                        n.postPrayerAdhkarMinutes)))) return true;
          }
        }
        if (p.name.contains('الشروق') &&
            n.duhaReminderEnabled &&
            near(
                time.add(Duration(minutes: n.duhaReminderMinutesAfterSunrise))))
          return true;
        if (p.name.contains('الفجر') &&
            n.qiyamReminderEnabled &&
            near(time.subtract(Duration(minutes: n.qiyamOffsetMinutes))))
          return true;
      }
      for (var day = -1; day <= 1; day++) {
        DateTime at(int h, int m) =>
            DateTime(now.year, now.month, now.day + day, h, m);
        if (n.morningAdhkarEnabled &&
            near(at(n.morningAdhkarHour, n.morningAdhkarMinute))) return true;
        if (n.eveningAdhkarEnabled &&
            near(at(n.eveningAdhkarHour, n.eveningAdhkarMinute))) return true;
        if (n.sleepAdhkarEnabled &&
            near(at(n.sleepAdhkarHour, n.sleepAdhkarMinute))) return true;
        final friday = at(n.fridayReminderHour, 0);
        if (n.fridayReminderEnabled &&
            friday.weekday == DateTime.friday &&
            near(friday)) return true;
      }
    }
    for (final p in prayers.where((p) => p.name.contains('الفجر'))) {
      if (f.preFajrEnabled &&
          near(p.time.subtract(Duration(minutes: f.preFajrMinutesBefore))))
        return true;
      if (f.qiyamEnabled &&
          f.qiyamMode == 'before_fajr' &&
          near(p.time.subtract(Duration(minutes: f.qiyamMinutesBeforeFajr))))
        return true;
    }
    if (f.qiyamEnabled) {
      if (f.isQiyamFixedClock) {
        for (var day = -1; day <= 1; day++) {
          if (near(DateTime(now.year, now.month, now.day + day,
              f.qiyamFixedHour, f.qiyamFixedMinute))) return true;
        }
      } else if (f.qiyamMode == 'last_third') {
        final third = FajrQiyamAlarmService.nextLastThirdForHorizon(prayers,
            now.subtract(margin).subtract(const Duration(microseconds: 1)),
            previousMaghrib: data?.previousMaghribTime);
        if (third != null && near(third)) return true;
      }
    }
    return false;
  }

  static Future<bool> _run({required bool headless, DateTime? now}) async {
    try {
      final notifications = PrayerNotificationService.instance;
      final fajr = FajrQiyamAlarmService.instance;
      PrayerData? data;
      if (headless) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final values = {for (final key in prefs.getKeys()) key: prefs.get(key)};
        data = savedData(values, now ?? DateTime.now());
        await notifications.initializeForScheduling();
        await fajr.prepareForScheduling();
      } else {
        await fajr.prepareForScheduling();
        // Read live state after the await. Never resurrect a cleared location
        // from an older preference snapshot in a running foreground engine.
        data = _currentCalculatedData();
      }
      if (isTransitionNear(data, now ?? DateTime.now())) return false;
      var prayerApplied = true;
      if (data != null) {
        final outcome = await notifications.schedulePrayerNotifications(data);
        prayerApplied = outcome == PrayerScheduleOutcome.applied ||
            outcome == PrayerScheduleOutcome.skipped;
      }
      // Unknown location does not manufacture astronomical times. Fixed-clock
      // Qiyam is still renewed, including with the master Adhan toggle off.
      final wake = await fajr.syncWithLocationAvailability(
          headless ? data : _currentCalculatedData());
      return prayerApplied && wake == AlarmScheduleOutcome.applied;
    } catch (_) {
      return false;
    }
  }
}

@pragma('vm:entry-point')
Future<void> prayerRenewalMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final applied = await PrayerRenewal.run(headless: true);
  await PrayerRenewal.channel.invokeMethod<void>('finish', applied);
}
