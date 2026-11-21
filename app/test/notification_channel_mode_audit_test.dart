import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/core/services/prayer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'notif_master_enabled': false,
      'notif_sound_mode': 'vibrateOnly',
      'notif_pre_reminder_voice_enabled': true
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') return null;
      return true;
    });
    await PrayerNotificationService.instance.init(forceReload: true);
    calls.clear();
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  test('vibration-only pre-reminder must not use a voiced channel', () async {
    await PrayerNotificationService.instance
        .sendTestPreReminderNotification('العصر');
    final android = ((calls.singleWhere((c) => c.method == 'show').arguments
        as Map)['platformSpecifics'] as Map);
    expect(android['playSound'], isFalse);
    expect(android['channelId'], 'prayer_vibrate_channel');
  });
  test('vibration-only iqamah test must not request audible playback',
      () async {
    await PrayerNotificationService.instance.sendTestIqamahNotification();
    final android = ((calls.singleWhere((c) => c.method == 'show').arguments
        as Map)['platformSpecifics'] as Map);
    expect(android['playSound'], isFalse);
    expect(android['channelId'], 'prayer_vibrate_channel');
  });
  for (final mode in [
    AdhanSoundMode.silent,
    AdhanSoundMode.vibrateOnly,
    AdhanSoundMode.fullAdhan
  ]) {
    test(
        'all prayer-derived notifications route quiet mode safely: ${mode.name}',
        () async {
      SharedPreferences.setMockInitialValues({
        'notif_master_enabled': true,
        'notif_sound_mode': mode.name,
        'notif_morning_adhkar_enabled': false,
        'notif_evening_adhkar_enabled': false,
        'notif_sleep_adhkar_enabled': false,
        'notif_prayer_الشروق': true,
      });
      await PrayerNotificationService.instance.init(forceReload: true);
      await Future<void>.delayed(Duration.zero);
      calls.clear();
      final now = DateTime.now();
      final data = PrayerData(
          latitude: 30,
          longitude: 31,
          locationName: 'القاهرة',
          prayers: [
            PrayerInfo(
                name: 'الفجر',
                time: now.add(const Duration(hours: 2)),
                formattedTime: ''),
            PrayerInfo(
                name: 'الشروق',
                time: now.add(const Duration(hours: 3)),
                formattedTime: ''),
            PrayerInfo(
                name: 'العصر',
                time: now.add(const Duration(hours: 5)),
                formattedTime: ''),
          ],
          qiblaDegrees: 135,
          lastUpdated: now);
      await PrayerNotificationService.instance
          .schedulePrayerNotifications(data);
      final scheduled =
          calls.where((c) => c.method == 'zonedSchedule').toList();
      expect(scheduled.length, 12);
      for (final call in scheduled) {
        final args = call.arguments as Map;
        final android = args['platformSpecifics'] as Map;
        if (mode != AdhanSoundMode.fullAdhan) {
          expect(
              android['channelId'],
              mode == AdhanSoundMode.silent
                  ? 'prayer_silent_channel'
                  : 'prayer_vibrate_channel',
              reason: args['title']);
          expect(android['playSound'], isFalse, reason: args['title']);
          expect(android['enableVibration'], mode != AdhanSoundMode.silent,
              reason: args['title']);
        } else {
          expect(android['channelId'],
              isNot(anyOf('prayer_silent_channel', 'prayer_vibrate_channel')));
          expect(android['playSound'], isTrue, reason: args['title']);
        }
      }
      expect(calls.any((c) => c.method.startsWith('request')), isFalse);
      expect(PrayerNotificationService.instance.prayerSchedulingError, isNull);
    });
  }
  for (final mode in [AdhanSoundMode.silent, AdhanSoundMode.vibrateOnly]) {
    for (final kind in ['adhan', 'iqamah', 'pre', 'snooze']) {
      test('test and snooze respect ${mode.name}: $kind', () async {
        SharedPreferences.setMockInitialValues(
            {'notif_master_enabled': false, 'notif_sound_mode': mode.name});
        await PrayerNotificationService.instance.init(forceReload: true);
        calls.clear();
        switch (kind) {
          case 'adhan':
            await PrayerNotificationService.instance.sendTestNotification();
          case 'iqamah':
            await PrayerNotificationService.instance
                .sendTestIqamahNotification();
          case 'pre':
            await PrayerNotificationService.instance
                .sendTestPreReminderNotification('العصر');
          case 'snooze':
            await PrayerNotificationService.instance.snoozeAdhan(5, 'العصر');
        }
        final notification = calls.singleWhere(
            (c) => c.method == 'show' || c.method == 'zonedSchedule');
        final android =
            (notification.arguments as Map)['platformSpecifics'] as Map;
        expect(
            android['channelId'],
            mode == AdhanSoundMode.silent
                ? 'prayer_silent_channel'
                : 'prayer_vibrate_channel');
        expect(android['playSound'], isFalse);
        expect(android['enableVibration'], mode != AdhanSoundMode.silent);
      });
    }
  }
  test(
      'mode routing preserves every notification time/id/payload and saved voice',
      () async {
    final now = DateTime.now();
    final data = PrayerData(
        latitude: 30,
        longitude: 31,
        locationName: 'القاهرة',
        prayers: [
          PrayerInfo(
              name: 'الفجر',
              time: now.add(const Duration(hours: 3)),
              formattedTime: '')
        ],
        qiblaDegrees: 135,
        lastUpdated: now);
    List<Map>? baseline;
    for (final mode in [
      AdhanSoundMode.fullAdhan,
      AdhanSoundMode.silent,
      AdhanSoundMode.vibrateOnly
    ]) {
      SharedPreferences.setMockInitialValues({
        'notif_master_enabled': true,
        'notif_sound_mode': mode.name,
        'notif_prayer_voice_الفجر': 'adhan_fajr',
      });
      await PrayerNotificationService.instance.init(forceReload: true);
      await Future<void>.delayed(Duration.zero);
      calls.clear();
      await PrayerNotificationService.instance
          .schedulePrayerNotifications(data);
      final scheduled = calls
          .where((c) => c.method == 'zonedSchedule')
          .map((c) => Map.of(c.arguments as Map))
          .toList();
      final fingerprints = scheduled
          .map((args) => Map.of(args)..remove('platformSpecifics'))
          .toList();
      if (baseline == null) {
        baseline = fingerprints;
      } else {
        expect(fingerprints, baseline);
      }
      final fixedAdhkar =
          scheduled.where((args) => [801, 802, 803].contains(args['id']));
      expect(fixedAdhkar.length, 3);
      for (final args in fixedAdhkar) {
        final android = args['platformSpecifics'] as Map;
        expect(android['playSound'], isTrue);
        expect(android['channelId'], startsWith('adhkar_'));
      }
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('notif_sound_mode'), mode.name);
      expect(prefs.getString('notif_prayer_voice_الفجر'), 'adhan_fajr');
      expect(
          calls.any((c) =>
              c.method == 'createNotificationChannel' ||
              c.method.startsWith('request')),
          isFalse);
    }
  });
}
