import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
    await PrayerNotificationService.instance.init();
  });

  group('PrayerNotificationService Extended Unit Tests (FR-NOT-006)', () {
    test('Default values are initialized properly', () {
      final notif = PrayerNotificationService.instance;

      expect(notif.preReminderEnabled, isTrue);
      expect(notif.preReminderMinutes, 10);
      expect(notif.qiyamReminderEnabled, isTrue);
      expect(notif.qiyamOffsetMinutes, 60);
      expect(notif.fridayReminderEnabled, isTrue);
      expect(notif.fridayReminderHour, 9);
    });

    test('togglePreReminder updates state and persists in SharedPreferences', () async {
      final notif = PrayerNotificationService.instance;
      await notif.togglePreReminder(false);
      expect(notif.preReminderEnabled, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('notif_pre_reminder_enabled'), isFalse);

      await notif.togglePreReminder(true);
      expect(notif.preReminderEnabled, isTrue);
      expect(prefs.getBool('notif_pre_reminder_enabled'), isTrue);
    });

    test('setPreReminder updates minutes and persists in SharedPreferences', () async {
      final notif = PrayerNotificationService.instance;
      await notif.setPreReminder(15);
      expect(notif.preReminderMinutes, 15);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('notif_pre_reminder'), 15);

      await notif.setPreReminder(10);
      expect(notif.preReminderMinutes, 10);
    });

    test('toggleQiyamReminder updates state and persists in SharedPreferences', () async {
      final notif = PrayerNotificationService.instance;
      await notif.toggleQiyamReminder(false);
      expect(notif.qiyamReminderEnabled, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('notif_qiyam_enabled'), isFalse);

      await notif.toggleQiyamReminder(true);
      expect(notif.qiyamReminderEnabled, isTrue);
    });

    test('setQiyamOffset updates minutes and persists in SharedPreferences', () async {
      final notif = PrayerNotificationService.instance;
      await notif.setQiyamOffset(90);
      expect(notif.qiyamOffsetMinutes, 90);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('notif_qiyam_offset'), 90);

      await notif.setQiyamOffset(60);
      expect(notif.qiyamOffsetMinutes, 60);
    });

    test('toggleFridayReminder updates state and persists in SharedPreferences', () async {
      final notif = PrayerNotificationService.instance;
      await notif.toggleFridayReminder(false);
      expect(notif.fridayReminderEnabled, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('notif_friday_enabled'), isFalse);

      await notif.toggleFridayReminder(true);
      expect(notif.fridayReminderEnabled, isTrue);
    });

    test('setFridayReminderHour updates hour and persists in SharedPreferences', () async {
      final notif = PrayerNotificationService.instance;
      await notif.setFridayReminderHour(8);
      expect(notif.fridayReminderHour, 8);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('notif_friday_hour'), 8);

      await notif.setFridayReminderHour(9);
      expect(notif.fridayReminderHour, 9);
    });

    test('toggleDuhaReminder updates state and persists in SharedPreferences', () async {
      final notif = PrayerNotificationService.instance;
      await notif.toggleDuhaReminder(false);
      expect(notif.duhaReminderEnabled, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('notif_duha_enabled'), isFalse);

      await notif.toggleDuhaReminder(true);
      expect(notif.duhaReminderEnabled, isTrue);
    });

    test('setDuhaOffset updates minutes and persists in SharedPreferences', () async {
      final notif = PrayerNotificationService.instance;
      await notif.setDuhaOffset(40);
      expect(notif.duhaReminderMinutesAfterSunrise, 40);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('notif_duha_offset'), 40);

      await notif.setDuhaOffset(25);
      expect(notif.duhaReminderMinutesAfterSunrise, 25);
    });

    test('togglePostPrayerAdhkar updates state and persists in SharedPreferences', () async {
      final notif = PrayerNotificationService.instance;
      await notif.togglePostPrayerAdhkar(false);
      expect(notif.postPrayerAdhkarReminderEnabled, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('notif_post_adhkar_enabled'), isFalse);

      await notif.togglePostPrayerAdhkar(true);
      expect(notif.postPrayerAdhkarReminderEnabled, isTrue);
    });

    test('setSoundMode updates mode and persists in SharedPreferences', () async {
      final notif = PrayerNotificationService.instance;
      await notif.setSoundMode(AdhanSoundMode.takbeerat);
      expect(notif.soundMode, AdhanSoundMode.takbeerat);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('notif_sound_mode'), 'takbeerat');

      await notif.setSoundMode(AdhanSoundMode.fullAdhan);
      expect(notif.soundMode, AdhanSoundMode.fullAdhan);
    });

    test('toggleFajrDistinctVoice updates state and persists', () async {
      final notif = PrayerNotificationService.instance;
      await notif.toggleFajrDistinctVoice(false);
      expect(notif.fajrDistinctVoiceEnabled, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('notif_fajr_distinct'), isFalse);

      await notif.toggleFajrDistinctVoice(true);
      expect(notif.fajrDistinctVoiceEnabled, isTrue);
    });
  });

  group('PrayerNotificationService Past Prayer Followups & Controls (Candidate B)', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');

    bool isAdhanCall(MethodCall call, String prayerName) {
      if (call.method != 'zonedSchedule') return false;
      final args = call.arguments as Map;
      final payload = args['payload'] as String? ?? '';
      return payload == 'type=adhan&prayer=$prayerName';
    }

    bool isIqamahCall(MethodCall call, String prayerName) {
      if (call.method != 'zonedSchedule') return false;
      final args = call.arguments as Map;
      final payload = args['payload'] as String? ?? '';
      final specifics = args['platformSpecifics'] as Map?;
      return payload == 'type=iqamah&prayer=$prayerName' &&
          specifics?['channelId'] == 'prayer_iqamah_channel';
    }

    bool isAdhkarCall(MethodCall call, String prayerName) {
      if (call.method != 'zonedSchedule') return false;
      final args = call.arguments as Map;
      final title = args['title'] as String? ?? '';
      final specifics = args['platformSpecifics'] as Map?;
      return title == 'أذكار ما بعد صلاة $prayerName 📿' &&
          specifics?['channelId'] == 'prayer_post_adhkar_channel';
    }

    bool isSunriseCall(MethodCall call) {
      if (call.method != 'zonedSchedule') return false;
      final args = call.arguments as Map;
      final title = args['title'] as String? ?? '';
      final specifics = args['platformSpecifics'] as Map?;
      return title == 'شروق الشمس 🌅' &&
          specifics?['channelId'] == 'prayer_sunrise_channel';
    }

    Future<void Function()> setupIsolatedMockEnvironment(List<MethodCall> calls) async {
      final notifService = PrayerNotificationService.instance;
      final prefs = await SharedPreferences.getInstance();

      final keysToSnapshot = [
        'notif_master_enabled',
        'notif_iqamah_enabled',
        'notif_iqamah_offset',
        'notif_post_adhkar_enabled',
        'notif_post_adhkar_offset',
        'notif_pre_reminder_enabled',
        'notif_pre_reminder',
        'notif_sound_mode',
        'notif_mute_until',
        'notif_prayer_الفجر',
        'notif_prayer_الشروق',
        'notif_prayer_الظهر',
        'notif_prayer_العصر',
        'notif_prayer_المغرب',
        'notif_prayer_العشاء',
      ];

      final initialPrefs = <String, Object?>{};
      for (final key in keysToSnapshot) {
        if (prefs.containsKey(key)) {
          initialPrefs[key] = prefs.get(key);
        }
      }

      final origMaster = notifService.masterEnabled;
      final origIqamahEnabled = notifService.iqamahReminderEnabled;
      final origIqamahOffset = notifService.iqamahOffsetMinutes;
      final origPostAdhkarEnabled = notifService.postPrayerAdhkarReminderEnabled;
      final origPostAdhkarOffset = notifService.postPrayerAdhkarMinutes;
      final origPreReminderEnabled = notifService.preReminderEnabled;
      final origSoundMode = notifService.soundMode;
      final origMuteUntil = notifService.muteUntil;
      final origPrayerToggles = Map<String, bool>.from(notifService.prayerToggles);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        calls.add(call);
        return true;
      });

      return () async {
        final p = await SharedPreferences.getInstance();

        // 1. Restore singleton in-memory state via setters while mock handler is active
        if (notifService.masterEnabled != origMaster) {
          await notifService.toggleMaster(origMaster);
        }
        if (notifService.iqamahReminderEnabled != origIqamahEnabled) {
          await notifService.toggleIqamahReminder(origIqamahEnabled);
        }
        if (notifService.iqamahOffsetMinutes != origIqamahOffset) {
          await notifService.setIqamahOffset(origIqamahOffset);
        }
        if (notifService.postPrayerAdhkarReminderEnabled != origPostAdhkarEnabled) {
          await notifService.togglePostPrayerAdhkar(origPostAdhkarEnabled);
        }
        if (notifService.postPrayerAdhkarMinutes != origPostAdhkarOffset) {
          await notifService.setPostPrayerAdhkarOffset(origPostAdhkarOffset);
        }
        if (notifService.preReminderEnabled != origPreReminderEnabled) {
          await notifService.togglePreReminder(origPreReminderEnabled);
        }
        if (notifService.soundMode != origSoundMode) {
          await notifService.setSoundMode(origSoundMode);
        }
        for (final entry in origPrayerToggles.entries) {
          if (notifService.isPrayerEnabled(entry.key) != entry.value) {
            await notifService.togglePrayer(entry.key, entry.value);
          }
        }
        if (origMuteUntil == null) {
          if (notifService.muteUntil != null) {
            await notifService.cancelTemporaryMute();
          }
        } else {
          final diff = origMuteUntil.difference(DateTime.now());
          if (diff.isNegative) {
            await notifService.cancelTemporaryMute();
          } else {
            await notifService.muteForDuration(diff);
          }
        }

        // 2. Restore exact SharedPreferences keys & values (without forceReload)
        for (final key in keysToSnapshot) {
          if (initialPrefs.containsKey(key)) {
            final val = initialPrefs[key];
            if (val is bool) {
              await p.setBool(key, val);
            } else if (val is int) {
              await p.setInt(key, val);
            } else if (val is String) {
              await p.setString(key, val);
            }
          } else {
            await p.remove(key);
          }
        }

        // 3. Assert exact in-memory state and exact prefs match initial snapshot
        expect(notifService.masterEnabled, equals(origMaster), reason: 'masterEnabled must match initial state');
        expect(notifService.iqamahReminderEnabled, equals(origIqamahEnabled), reason: 'iqamahReminderEnabled must match initial state');
        expect(notifService.iqamahOffsetMinutes, equals(origIqamahOffset), reason: 'iqamahOffsetMinutes must match initial state');
        expect(notifService.postPrayerAdhkarReminderEnabled, equals(origPostAdhkarEnabled), reason: 'postPrayerAdhkarReminderEnabled must match initial state');
        expect(notifService.postPrayerAdhkarMinutes, equals(origPostAdhkarOffset), reason: 'postPrayerAdhkarMinutes must match initial state');
        expect(notifService.preReminderEnabled, equals(origPreReminderEnabled), reason: 'preReminderEnabled must match initial state');
        expect(notifService.soundMode, equals(origSoundMode), reason: 'soundMode must match initial state');
        expect(notifService.prayerToggles, equals(origPrayerToggles), reason: 'prayerToggles must match initial state');

        for (final key in keysToSnapshot) {
          if (initialPrefs.containsKey(key)) {
            expect(p.get(key), equals(initialPrefs[key]), reason: 'Key $key must match initial pref value');
          } else {
            expect(p.containsKey(key), isFalse, reason: 'Key $key must be absent from prefs');
          }
        }

        // 4. Remove mock handler
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      };
    }

    test('schedules pending future iqamah and adhkar when prayer started in past, omits past adhan', () async {
      final calls = <MethodCall>[];
      final cleanup = await setupIsolatedMockEnvironment(calls);
      addTearDown(cleanup);

      tz.initializeTimeZones();
      final notifService = PrayerNotificationService.instance;
      await notifService.init();
      await notifService.toggleMaster(true);
      await notifService.togglePrayer('الظهر', true);
      await notifService.togglePrayer('العصر', true);
      await notifService.toggleIqamahReminder(true);
      await notifService.setIqamahOffset(15);
      await notifService.togglePostPrayerAdhkar(true);
      await notifService.setPostPrayerAdhkarOffset(10);
      await notifService.cancelTemporaryMute();

      final now = DateTime.now();
      final dhuhrTime = now.subtract(const Duration(minutes: 5));
      final asrTime = now.add(const Duration(hours: 3));

      final testPrayerData = PrayerData(
        latitude: 30.0,
        longitude: 31.0,
        locationName: 'القاهرة',
        prayers: [
          PrayerInfo(name: 'الظهر', time: dhuhrTime, formattedTime: '12:00 PM'),
          PrayerInfo(name: 'العصر', time: asrTime, formattedTime: '03:00 PM'),
        ],
        qiblaDegrees: 135.0,
        lastUpdated: now,
      );

      calls.clear();
      await notifService.schedulePrayerNotifications(testPrayerData);

      // Scoped derived-range cancellation only (must NOT call destructive cancelAll)
      expect(calls.any((c) => c.method == 'cancelAll'), isFalse);
      expect(
        calls.any((c) =>
            c.method == 'cancel' &&
            (c.arguments == PrayerNotificationService.prayerDerivedNotificationIdStart ||
                (c.arguments is Map &&
                    (c.arguments as Map)['id'] ==
                        PrayerNotificationService.prayerDerivedNotificationIdStart))),
        isTrue,
      );

      // 1. Past Dhuhr Adhan must NOT be scheduled
      final dhuhrAdhan = calls.where((c) => isAdhanCall(c, 'الظهر')).toList();
      expect(dhuhrAdhan, isEmpty, reason: 'Past prayer adhan must not be scheduled');

      // 2. Future Dhuhr Iqamah (+10m) must be scheduled
      final dhuhrIqamah = calls.where((c) => isIqamahCall(c, 'الظهر')).toList();
      expect(dhuhrIqamah, hasLength(1), reason: 'Future iqamah for past prayer must be scheduled');

      // 3. Future Dhuhr Post-prayer Adhkar (+20m) must be scheduled
      final dhuhrAdhkar = calls.where((c) => isAdhkarCall(c, 'الظهر')).toList();
      expect(dhuhrAdhkar, hasLength(1), reason: 'Future post-prayer adhkar for past prayer must be scheduled');

      // 4. Future Asr prayer: Adhan, Iqamah, Adhkar must all be scheduled
      final asrAdhan = calls.where((c) => isAdhanCall(c, 'العصر')).toList();
      expect(asrAdhan, hasLength(1), reason: 'Future prayer adhan must be scheduled');

      final asrIqamah = calls.where((c) => isIqamahCall(c, 'العصر')).toList();
      expect(asrIqamah, hasLength(1), reason: 'Future prayer iqamah must be scheduled');

      final asrAdhkar = calls.where((c) => isAdhkarCall(c, 'العصر')).toList();
      expect(asrAdhkar, hasLength(1), reason: 'Future prayer post-prayer adhkar must be scheduled');
    });

    test('disabled prayer control: does not schedule any notifications for disabled prayer while enabled prayer schedules normally', () async {
      final calls = <MethodCall>[];
      final cleanup = await setupIsolatedMockEnvironment(calls);
      addTearDown(cleanup);

      tz.initializeTimeZones();
      final notifService = PrayerNotificationService.instance;
      await notifService.init();
      await notifService.toggleMaster(true);
      await notifService.togglePrayer('الظهر', false);
      await notifService.togglePrayer('العصر', true);
      await notifService.toggleIqamahReminder(true);
      await notifService.setIqamahOffset(15);
      await notifService.togglePostPrayerAdhkar(true);
      await notifService.setPostPrayerAdhkarOffset(10);
      await notifService.cancelTemporaryMute();

      final now = DateTime.now();
      final dhuhrTime = now.subtract(const Duration(minutes: 5));
      final asrTime = now.add(const Duration(hours: 3));

      final testPrayerData = PrayerData(
        latitude: 30.0,
        longitude: 31.0,
        locationName: 'القاهرة',
        prayers: [
          PrayerInfo(name: 'الظهر', time: dhuhrTime, formattedTime: '12:00 PM'),
          PrayerInfo(name: 'العصر', time: asrTime, formattedTime: '03:00 PM'),
        ],
        qiblaDegrees: 135.0,
        lastUpdated: now,
      );

      calls.clear();
      await notifService.schedulePrayerNotifications(testPrayerData);

      // Verify no Dhuhr notifications of any kind are scheduled
      final dhuhrAdhan = calls.where((c) => isAdhanCall(c, 'الظهر')).toList();
      final dhuhrIqamah = calls.where((c) => isIqamahCall(c, 'الظهر')).toList();
      final dhuhrAdhkar = calls.where((c) => isAdhkarCall(c, 'الظهر')).toList();
      expect(dhuhrAdhan, isEmpty, reason: 'Disabled prayer adhan must not be scheduled');
      expect(dhuhrIqamah, isEmpty, reason: 'Disabled prayer iqamah must not be scheduled');
      expect(dhuhrAdhkar, isEmpty, reason: 'Disabled prayer adhkar must not be scheduled');

      // Verify Asr notifications are still scheduled
      final asrAdhan = calls.where((c) => isAdhanCall(c, 'العصر')).toList();
      final asrIqamah = calls.where((c) => isIqamahCall(c, 'العصر')).toList();
      final asrAdhkar = calls.where((c) => isAdhkarCall(c, 'العصر')).toList();
      expect(asrAdhan, hasLength(1), reason: 'Enabled prayer adhan must be scheduled');
      expect(asrIqamah, hasLength(1), reason: 'Enabled prayer iqamah must be scheduled');
      expect(asrAdhkar, hasLength(1), reason: 'Enabled prayer adhkar must be scheduled');
    });

    test('temporary mute control: suppresses notifications within mute window and preserves prayers after mute window', () async {
      final calls = <MethodCall>[];
      final cleanup = await setupIsolatedMockEnvironment(calls);
      addTearDown(cleanup);

      tz.initializeTimeZones();
      final notifService = PrayerNotificationService.instance;
      await notifService.init();
      await notifService.toggleMaster(true);
      await notifService.togglePrayer('الظهر', true);
      await notifService.togglePrayer('العصر', true);
      await notifService.toggleIqamahReminder(true);
      await notifService.setIqamahOffset(15);
      await notifService.togglePostPrayerAdhkar(true);
      await notifService.setPostPrayerAdhkarOffset(10);

      // Mute for 1 hour from now
      await notifService.muteForDuration(const Duration(hours: 1));

      final now = DateTime.now();
      // Dhuhr prayer time was 5 minutes ago (within mute window)
      final dhuhrTime = now.subtract(const Duration(minutes: 5));
      // Asr prayer time is in 3 hours (after mute window)
      final asrTime = now.add(const Duration(hours: 3));

      final testPrayerData = PrayerData(
        latitude: 30.0,
        longitude: 31.0,
        locationName: 'القاهرة',
        prayers: [
          PrayerInfo(name: 'الظهر', time: dhuhrTime, formattedTime: '12:00 PM'),
          PrayerInfo(name: 'العصر', time: asrTime, formattedTime: '03:00 PM'),
        ],
        qiblaDegrees: 135.0,
        lastUpdated: now,
      );

      calls.clear();
      await notifService.schedulePrayerNotifications(testPrayerData);

      // Verify Dhuhr notifications are suppressed under mute
      final dhuhrAdhan = calls.where((c) => isAdhanCall(c, 'الظهر')).toList();
      final dhuhrIqamah = calls.where((c) => isIqamahCall(c, 'الظهر')).toList();
      final dhuhrAdhkar = calls.where((c) => isAdhkarCall(c, 'الظهر')).toList();
      expect(dhuhrAdhan, isEmpty, reason: 'Muted prayer adhan must not be scheduled');
      expect(dhuhrIqamah, isEmpty, reason: 'Muted prayer iqamah must not be scheduled');
      expect(dhuhrAdhkar, isEmpty, reason: 'Muted prayer adhkar must not be scheduled');

      // Verify Asr (outside mute window) is scheduled
      final asrAdhan = calls.where((c) => isAdhanCall(c, 'العصر')).toList();
      final asrIqamah = calls.where((c) => isIqamahCall(c, 'العصر')).toList();
      final asrAdhkar = calls.where((c) => isAdhkarCall(c, 'العصر')).toList();
      expect(asrAdhan, hasLength(1), reason: 'Prayer after mute window schedules adhan');
      expect(asrIqamah, hasLength(1), reason: 'Prayer after mute window schedules iqamah');
      expect(asrAdhkar, hasLength(1), reason: 'Prayer after mute window schedules adhkar');
    });

    test('sunrise controls: schedules future sunrise when enabled, omits past, disabled, and muted sunrise', () async {
      final calls = <MethodCall>[];
      final cleanup = await setupIsolatedMockEnvironment(calls);
      addTearDown(cleanup);

      tz.initializeTimeZones();
      final notifService = PrayerNotificationService.instance;
      await notifService.init();
      await notifService.toggleMaster(true);
      await notifService.cancelTemporaryMute();

      final now = DateTime.now();

      // Case A: Future sunrise when enabled -> MUST be scheduled on prayer_sunrise_channel
      await notifService.togglePrayer('الشروق', true);
      calls.clear();
      final futureData = PrayerData(
        latitude: 30.0,
        longitude: 31.0,
        locationName: 'القاهرة',
        prayers: [
          PrayerInfo(name: 'الشروق', time: now.add(const Duration(hours: 2)), formattedTime: '06:00 AM'),
        ],
        qiblaDegrees: 135.0,
        lastUpdated: now,
      );
      await notifService.schedulePrayerNotifications(futureData);
      final futureSunriseCalls = calls.where(isSunriseCall).toList();
      expect(futureSunriseCalls, hasLength(1), reason: 'Future enabled sunrise must be scheduled on prayer_sunrise_channel');

      // Case B: Past / expired sunrise when enabled -> MUST NOT be scheduled
      calls.clear();
      final pastData = PrayerData(
        latitude: 30.0,
        longitude: 31.0,
        locationName: 'القاهرة',
        prayers: [
          PrayerInfo(name: 'الشروق', time: now.subtract(const Duration(minutes: 30)), formattedTime: '05:30 AM'),
        ],
        qiblaDegrees: 135.0,
        lastUpdated: now,
      );
      await notifService.schedulePrayerNotifications(pastData);
      final pastSunriseCalls = calls.where(isSunriseCall).toList();
      expect(pastSunriseCalls, isEmpty, reason: 'Past expired sunrise must not be scheduled');

      // Case C: Future sunrise when disabled -> MUST NOT be scheduled
      await notifService.togglePrayer('الشروق', false);
      calls.clear();
      await notifService.schedulePrayerNotifications(futureData);
      final disabledSunriseCalls = calls.where(isSunriseCall).toList();
      expect(disabledSunriseCalls, isEmpty, reason: 'Disabled sunrise must not be scheduled');

      // Case D: Future sunrise when muted -> MUST NOT be scheduled
      await notifService.togglePrayer('الشروق', true);
      await notifService.muteForDuration(const Duration(hours: 3)); // covers the 2-hour future sunrise
      calls.clear();
      await notifService.schedulePrayerNotifications(futureData);
      final mutedSunriseCalls = calls.where(isSunriseCall).toList();
      expect(mutedSunriseCalls, isEmpty, reason: 'Muted sunrise must not be scheduled');
    });

    test('expired prayer followups: omits adhan, iqamah, and adhkar when prayer and all followups are in the past', () async {
      final calls = <MethodCall>[];
      final cleanup = await setupIsolatedMockEnvironment(calls);
      addTearDown(cleanup);

      tz.initializeTimeZones();
      final notifService = PrayerNotificationService.instance;
      await notifService.init();
      await notifService.toggleMaster(true);
      await notifService.togglePrayer('الفجر', true);
      await notifService.toggleIqamahReminder(true);
      await notifService.setIqamahOffset(15);
      await notifService.togglePostPrayerAdhkar(true);
      await notifService.setPostPrayerAdhkarOffset(10);
      await notifService.cancelTemporaryMute();

      final now = DateTime.now();
      // Fajr was 2 hours ago: prayer at now - 2h, iqamah at now - 1h 45m, adhkar at now - 1h 35m (all in the past)
      final fajrTime = now.subtract(const Duration(hours: 2));

      final testPrayerData = PrayerData(
        latitude: 30.0,
        longitude: 31.0,
        locationName: 'القاهرة',
        prayers: [
          PrayerInfo(name: 'الفجر', time: fajrTime, formattedTime: '04:30 AM'),
        ],
        qiblaDegrees: 135.0,
        lastUpdated: now,
      );

      calls.clear();
      await notifService.schedulePrayerNotifications(testPrayerData);

      final fajrAdhan = calls.where((c) => isAdhanCall(c, 'الفجر')).toList();
      final fajrIqamah = calls.where((c) => isIqamahCall(c, 'الفجر')).toList();
      final fajrAdhkar = calls.where((c) => isAdhkarCall(c, 'الفجر')).toList();

      expect(fajrAdhan, isEmpty, reason: 'Expired prayer adhan must not be scheduled');
      expect(fajrIqamah, isEmpty, reason: 'Expired prayer iqamah must not be scheduled');
      expect(fajrAdhkar, isEmpty, reason: 'Expired prayer post-prayer adhkar must not be scheduled');
    });
  });

  group('SettingsScreen Extended Notifications UI Widget Tests', () {
    testWidgets('Renders Pre-Adhan, Qiyam, and Friday Sunnahs options', (tester) async {
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('settings_category_4')));
      await tester.pumpAndSettle();
      final beforePre = PrayerNotificationService.instance.preReminderMinutes;
      final beforeQiyam = PrayerNotificationService.instance.qiyamOffsetMinutes;
      expect(find.text('التنبيه المسبق'), findsOneWidget);
      expect(find.text('قيام الليل'), findsOneWidget);
      expect(find.text('تذكير الجمعة'), findsOneWidget);

      // Verify Pre-reminder picker opens and changes value
      final prePickerTile = find.text('دقائق قبل الأذان');
      expect(prePickerTile, findsOneWidget);
      await tester.tap(prePickerTile);
      await tester.pumpAndSettle();

      // Tap on 15 minutes
      final option15 = find.text('15').last;
      expect(option15, findsOneWidget);
      await tester.tap(option15);
      await tester.pumpAndSettle();

      expect(PrayerNotificationService.instance.preReminderMinutes, beforePre);

      // Verify Qiyam offset picker opens and changes value
      final qiyamPickerTile = find.text('دقائق قبل الفجر');
      expect(qiyamPickerTile, findsOneWidget);
      await tester.tap(qiyamPickerTile);
      await tester.pumpAndSettle();

      // Tap on 90 minutes
      final option90 = find.text('90').last;
      expect(option90, findsOneWidget);
      await tester.tap(option90);
      await tester.pumpAndSettle();

      expect(PrayerNotificationService.instance.qiyamOffsetMinutes, beforeQiyam);
      await tester.tap(find.byKey(const ValueKey('settings_apply')));
      await tester.pumpAndSettle();
      expect(PrayerNotificationService.instance.preReminderMinutes, 15);
      expect(PrayerNotificationService.instance.qiyamOffsetMinutes, 90);
    });
  });
}
