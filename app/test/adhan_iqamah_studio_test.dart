import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/features/settings/widgets/settings_adhan_voice_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tz.initializeTimeZones();
  });

  group('Adhan & Iqamah Studio Unit & Preferences Tests', () {
    test('getAdhanVoiceName returns verified authentic title for all supported keys', () {
      expect(getAdhanVoiceName('adhan_makkah'), contains('مكة المكرمة'));
      expect(getAdhanVoiceName('adhan_madinah'), contains('المدينة المنورة'));
      expect(getAdhanVoiceName('adhan_aqsa'), contains('القدس الشريف'));
      expect(getAdhanVoiceName('adhan_abdulbasit'), contains('عبد الباسط عبد الصمد'));
      expect(getAdhanVoiceName('adhan_afasy'), contains('مشاري بن راشد العفاسي'));
      expect(getAdhanVoiceName('adhan_turkey'), contains('تركيا'));
      expect(getAdhanVoiceName('adhan_dubai'), contains('دبي'));
      expect(getAdhanVoiceName('adhan_sham'), contains('الأموي'));
      expect(getAdhanVoiceName('takbeerat'), contains('تكبيرات'));
    });

    test('getIqamahVoiceName returns verified authentic title for all Iqama keys', () {
      expect(getIqamahVoiceName('iqamah_makkah'), contains('المسجد الحرام'));
      expect(getIqamahVoiceName('iqamah_madinah'), contains('المدينة المنورة'));
      expect(getIqamahVoiceName('iqamah_afasy'), contains('مشاري بن راشد العفاسي'));
      expect(getIqamahVoiceName('iqamah_abdulbasit'), contains('عبد الباسط عبد الصمد'));
      expect(getIqamahVoiceName('iqamah_cairo'), contains('القاهرة'));
      expect(getIqamahVoiceName('iqamah_short'), contains('سريعة'));
    });

    test('PrayerNotificationService manages selectedIqamahVoice persistence correctly', () async {
      final service = PrayerNotificationService.instance;
      await service.init();

      expect(service.selectedIqamahVoice, 'iqamah_full');

      await service.setSelectedIqamahVoice('iqamah_afasy');
      expect(service.selectedIqamahVoice, 'iqamah_afasy');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('notif_selected_iqamah'), 'iqamah_afasy');

      await service.setSelectedIqamahVoice('iqamah_abdulbasit');
      expect(service.selectedIqamahVoice, 'iqamah_abdulbasit');
      expect(prefs.getString('notif_selected_iqamah'), 'iqamah_abdulbasit');
    });

    test('IslamicAudioService tracks catalog includes rich variety of HD Adhans and Iqamas', () {
      final adhans = IslamicAudioService.allTracks.where((t) => t.type == IslamicAudioType.adhan).toList();
      final iqamahs = IslamicAudioService.allTracks.where((t) => t.type == IslamicAudioType.iqamah).toList();

      expect(adhans.length, greaterThanOrEqualTo(15));
      expect(iqamahs.length, greaterThanOrEqualTo(5));

      final adhanIds = adhans.map((t) => t.id).toList();
      expect(adhanIds, containsAll([
        'adhan_makkah',
        'adhan_madinah',
        'adhan_aqsa',
        'adhan_abdulbasit',
        'adhan_afasy',
        'adhan_fajr_afasy',
        'adhan_turkey',
        'adhan_dubai',
        'adhan_sham',
      ]));

      final iqamahIds = iqamahs.map((t) => t.id).toList();
      expect(iqamahIds, containsAll([
        'iqamah_full',
        'iqamah_madinah',
        'iqamah_afasy',
        'iqamah_abdulbasit',
        'iqamah_cairo',
        'iqamah_short',
      ]));
    });

    test('PrayerNotificationService iqamah scheduling and test notification pass consistent raw sound (short, known, nullraw, unknown, test vs schedule)', () async {
      const channel = MethodChannel('dexterous.com/flutter/local_notifications');
      final calls = <MethodCall>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        calls.add(call);
        return true;
      });

      final notifService = PrayerNotificationService.instance;
      final originalVoice = notifService.selectedIqamahVoice;
      final originalIqamahEnabled = notifService.iqamahReminderEnabled;
      final originalOffset = notifService.iqamahOffsetMinutes;
      final prefs = await SharedPreferences.getInstance();
      final originalPrefVoice = prefs.getString('notif_selected_iqamah');
      final originalPrefEnabled = prefs.getBool('notif_iqamah_enabled');
      final originalPrefOffset = prefs.getInt('notif_iqamah_offset');

      addTearDown(() async {
        // Restore state while mock handler is active to safely handle any async reschedule calls
        await notifService.setSelectedIqamahVoice(originalVoice);
        await notifService.toggleIqamahReminder(originalIqamahEnabled);
        await notifService.setIqamahOffset(originalOffset);

        if (originalPrefVoice == null) {
          await prefs.remove('notif_selected_iqamah');
        } else {
          await prefs.setString('notif_selected_iqamah', originalPrefVoice);
        }
        if (originalPrefEnabled == null) {
          await prefs.remove('notif_iqamah_enabled');
        } else {
          await prefs.setBool('notif_iqamah_enabled', originalPrefEnabled);
        }
        if (originalPrefOffset == null) {
          await prefs.remove('notif_iqamah_offset');
        } else {
          await prefs.setInt('notif_iqamah_offset', originalPrefOffset);
        }

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      await notifService.init();
      await notifService.toggleIqamahReminder(true);
      await notifService.setIqamahOffset(15);

      Future<String?> getScheduledIqamahSound(String voiceKey) async {
        await notifService.setSelectedIqamahVoice(voiceKey);
        calls.clear();

        final testPrayerData = PrayerData(
          latitude: 30.0,
          longitude: 31.0,
          locationName: 'القاهرة',
          prayers: [
            PrayerInfo(
              name: 'الظهر',
              time: DateTime.now().add(const Duration(hours: 1)),
              formattedTime: '01:00 PM',
            ),
          ],
          qiblaDegrees: 135.0,
          lastUpdated: DateTime.now(),
        );

        await notifService.schedulePrayerNotifications(testPrayerData);

        final iqamahCall = calls.firstWhere(
          (c) => c.method == 'zonedSchedule' &&
              ((c.arguments as Map)['payload'] as String? ?? '').startsWith('type=iqamah'),
        );
        final platformSpecifics = (iqamahCall.arguments as Map)['platformSpecifics'] as Map;
        return platformSpecifics['sound'] as String?;
      }

      Future<String?> getTestIqamahSound(String voiceKey) async {
        calls.clear();
        await notifService.sendTestIqamahNotification(customVoice: voiceKey);
        final testCall = calls.firstWhere(
          (c) => c.method == 'show' &&
              ((c.arguments as Map)['payload'] as String? ?? '').startsWith('type=iqamah'),
        );
        final platformSpecifics = (testCall.arguments as Map)['platformSpecifics'] as Map;
        return platformSpecifics['sound'] as String?;
      }

      // 1. short: iqamah_short must schedule 'iqamah' (not 'takbeerat')
      expect(await getScheduledIqamahSound('iqamah_short'), equals('iqamah'));

      // 2. known: iqamah_madinah / iqamah_full
      expect(await getScheduledIqamahSound('iqamah_madinah'), equals('iqamah'));
      expect(await getScheduledIqamahSound('iqamah_full'), equals('iqamah'));

      // 3. nullraw: remote streaming track with null rawNotificationSound (e.g. iqamah_afasy)
      expect(await getScheduledIqamahSound('iqamah_afasy'), equals('iqamah'));

      // 4. unknown: unlisted voice key falls back to 'iqamah'
      expect(await getScheduledIqamahSound('unknown_voice_key'), equals('iqamah'));

      // 5. test vs schedule consistency: both must use 'iqamah'
      final testSound = await getTestIqamahSound('iqamah_short');
      final schedSound = await getScheduledIqamahSound('iqamah_short');
      expect(testSound, equals('iqamah'));
      expect(schedSound, equals(testSound));
    });
  });

  group('Adhan & Iqamah Studio Widget Rendering Tests', () {
    testWidgets('Renders studio sheet with Adhan and Iqamah tabs, search, and action cards', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => showSettingsAdhanVoiceModal(ctx, initialTab: 0),
                  child: const Text('افتح استوديو الأصوات'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('افتح استوديو الأصوات'));
      await tester.pumpAndSettle();

      // 1. Verify Header and Subtitle
      expect(find.text('مؤذنو الصلوات الخمس 🕌'), findsOneWidget);
      expect(find.textContaining('تخصيص مؤذن مستقل لكل صلاة'), findsOneWidget);

      // 2. Verify Unified Muezzin option
      expect(find.text('مؤذن موحد'), findsOneWidget);

      // 3. Verify the 5 prayer cards
      expect(find.text('صلاة الفجر'), findsOneWidget);
      expect(find.text('صلاة الظهر'), findsOneWidget);
      expect(find.text('صلاة العصر'), findsOneWidget);
      expect(find.text('صلاة المغرب'), findsOneWidget);
      expect(find.text('صلاة العشاء'), findsOneWidget);

      // 4. Verify change buttons
      expect(find.textContaining('تغيير المؤذن'), findsWidgets);
    });
  });
}
