import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/features/settings/widgets/sections/settings_adhkar_reminders_section.dart';
import 'package:almomin/features/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Adhkar Notification Timing & Settings Tests', () {
    late PrayerNotificationService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'has_completed_onboarding': true,
        'notif_master_enabled': true,
        'notif_morning_adhkar_enabled': true,
        'notif_morning_adhkar_hour': 7,
        'notif_morning_adhkar_minute': 0,
        'notif_evening_adhkar_enabled': true,
        'notif_evening_adhkar_hour': 17,
        'notif_evening_adhkar_minute': 0,
        'notif_sleep_adhkar_enabled': true,
        'notif_sleep_adhkar_hour': 22,
        'notif_sleep_adhkar_minute': 30,
      });

      service = PrayerNotificationService.instance;
      await service.init(forceReload: true);
    });

    test('Loads default Adhkar notification times and enabled states', () {
      expect(service.morningAdhkarEnabled, isTrue);
      expect(service.morningAdhkarHour, 7);
      expect(service.morningAdhkarMinute, 0);
      expect(service.morningAdhkarTime, const TimeOfDay(hour: 7, minute: 0));

      expect(service.eveningAdhkarEnabled, isTrue);
      expect(service.eveningAdhkarHour, 17);
      expect(service.eveningAdhkarMinute, 0);
      expect(service.eveningAdhkarTime, const TimeOfDay(hour: 17, minute: 0));

      expect(service.sleepAdhkarEnabled, isTrue);
      expect(service.sleepAdhkarHour, 22);
      expect(service.sleepAdhkarMinute, 30);
      expect(service.sleepAdhkarTime, const TimeOfDay(hour: 22, minute: 30));
    });

    test('Correctly updates and persists custom Adhkar notification times', () async {
      // Modify Morning Adhkar to 06:15
      await service.setMorningAdhkarTime(6, 15);
      expect(service.morningAdhkarHour, 6);
      expect(service.morningAdhkarMinute, 15);
      expect(service.morningAdhkarTime, const TimeOfDay(hour: 6, minute: 15));

      // Modify Evening Adhkar to 18:45
      await service.setEveningAdhkarTime(18, 45);
      expect(service.eveningAdhkarHour, 18);
      expect(service.eveningAdhkarMinute, 45);
      expect(service.eveningAdhkarTime, const TimeOfDay(hour: 18, minute: 45));

      // Modify Sleep Adhkar to 23:15
      await service.setSleepAdhkarTime(23, 15);
      expect(service.sleepAdhkarHour, 23);
      expect(service.sleepAdhkarMinute, 15);
      expect(service.sleepAdhkarTime, const TimeOfDay(hour: 23, minute: 15));

      // Toggle off and on
      await service.toggleMorningAdhkar(false);
      expect(service.morningAdhkarEnabled, isFalse);

      await service.toggleMorningAdhkar(true);
      expect(service.morningAdhkarEnabled, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('notif_morning_adhkar_hour'), 6);
      expect(prefs.getInt('notif_morning_adhkar_minute'), 15);
      expect(prefs.getInt('notif_evening_adhkar_hour'), 18);
      expect(prefs.getInt('notif_evening_adhkar_minute'), 45);
      expect(prefs.getInt('notif_sleep_adhkar_hour'), 23);
      expect(prefs.getInt('notif_sleep_adhkar_minute'), 15);
    });

    test('formatTimeArabic formats hours and minutes into clean 12-hour Arabic strings', () {
      expect(PrayerNotificationService.formatTimeArabic(7, 0), '07:00 ص');
      expect(PrayerNotificationService.formatTimeArabic(12, 0), '12:00 م');
      expect(PrayerNotificationService.formatTimeArabic(17, 30), '05:30 م');
      expect(PrayerNotificationService.formatTimeArabic(0, 15), '12:15 ص');
      expect(PrayerNotificationService.formatTimeArabic(22, 45), '10:45 م');
    });

    testWidgets('SettingsAdhkarRemindersSection renders cards and preset chips', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsAdhkarRemindersSection(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header and cards
      expect(find.text('مواقيت وتنبيهات أذكار المسلم'), findsOneWidget);
      expect(find.textContaining('أذكار الصباح المباركة'), findsOneWidget);
      expect(find.textContaining('أذكار المساء المباركة'), findsOneWidget);
      expect(find.textContaining('أذكار وسنن النوم'), findsOneWidget);

      // Verify preset chips appear
      expect(find.text('٠٧:٠٠ ص'), findsWidgets);
      expect(find.text('٠٥:٠٠ م'), findsWidgets);
      expect(find.text('١٠:٣٠ م'), findsWidgets);

      // Tap a preset chip for morning adhkar (e.g. ٠٨:٠٠ ص)
      final preset8AM = find.text('٠٨:٠٠ ص');
      expect(preset8AM, findsOneWidget);
      await tester.tap(preset8AM);
      await tester.pumpAndSettle();

      expect(service.morningAdhkarHour, 8);
      expect(service.morningAdhkarMinute, 0);
    });

    testWidgets('SettingsScreen contains SettingsAdhkarRemindersSection', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final adhkarTitle = find.text('مواقيت وتنبيهات أذكار المسلم');
      await tester.scrollUntilVisible(
        adhkarTitle,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(adhkarTitle, findsOneWidget);
      expect(find.byType(SettingsAdhkarRemindersSection), findsOneWidget);
    });
  });
}
