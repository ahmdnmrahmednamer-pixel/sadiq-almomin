import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/settings/widgets/settings_adhan_voice_modal.dart';
import 'package:almomin/features/prayer/widgets/prayer_muezzin_selector_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'notif_selected_adhan': 'adhan_makkah',
      'notif_selected_fajr_adhan': 'adhan_fajr',
      'notif_prayer_voice_الفجر': 'adhan_fajr',
      'notif_prayer_voice_الظهر': 'adhan_makkah',
      'notif_prayer_voice_العصر': 'adhan_madinah',
      'notif_prayer_voice_المغرب': 'adhan_cairo',
      'notif_prayer_voice_العشاء': 'adhan_aqsa',
    });
    await SettingsService.instance.init();
    await PrayerNotificationService.instance.init(forceReload: true);
  });

  group('Per-Prayer Muezzin Selection Tests (لكل صلاة مؤذن)', () {
    test('unsupported remote voice cannot overwrite saved choices; native supported keys remain available', () async {
      final service = PrayerNotificationService.instance;
      final prefs = await SharedPreferences.getInstance();
      final before = service.getPrayerVoice('العصر');
      final stored = prefs.getString('notif_prayer_voice_العصر');
      for (final id in ['adhan_amr_sobhi', 'adhan_naqshbandi', 'adhan_afasy', 'unknown_voice']) {
        expect(PrayerNotificationService.adhanAssignmentUnavailableReason(id), isNotNull);
        await expectLater(service.setPrayerVoice('العصر', id), throwsStateError);
        await expectLater(service.setAllPrayersVoice(id), throwsStateError);
      }
      expect(service.getPrayerVoice('العصر'), before);
      expect(prefs.getString('notif_prayer_voice_العصر'), stored);
      for (final id in ['adhan_makkah', 'adhan_madinah', 'adhan_hussary', 'adhan_cairo_refaat', 'adhan_aqsa', 'adhan_fajr']) {
        expect(PrayerNotificationService.adhanAssignmentUnavailableReason(id), isNull, reason: id);
      }
    });

    test('loading an old unsupported prayer choice retains its ID and enabled reminder', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notif_prayer_voice_العصر', 'adhan_haza_albalushi');
      final service = PrayerNotificationService.instance;
      final enabledBefore = service.isPrayerEnabled('العصر');
      await service.init(forceReload: true);
      expect(service.getPrayerVoice('العصر'), 'adhan_haza_albalushi');
      expect(service.isPrayerEnabled('العصر'), enabledBefore);
      expect(prefs.getString('notif_prayer_voice_العصر'), 'adhan_haza_albalushi');
    });

    test('unavailable recording cannot overwrite a stored prayer selection', () async {
      final service = PrayerNotificationService.instance;
      final prefs = await SharedPreferences.getInstance();
      final before = service.getPrayerVoice('العصر');
      final savedBefore = prefs.getString('notif_prayer_voice_العصر');
      await expectLater(service.setPrayerVoice('العصر', 'adhan_haza_albalushi'), throwsStateError);
      await expectLater(service.setAllPrayersVoice('adhan_haza_albalushi'), throwsStateError);
      await expectLater(service.setSelectedAdhanVoice('adhan_haza_albalushi'), throwsStateError);
      await expectLater(service.setSelectedFajrVoice('adhan_haza_albalushi'), throwsStateError);
      expect(service.getPrayerVoice('العصر'), before);
      expect(prefs.getString('notif_prayer_voice_العصر'), savedBefore);
    });

    test('Initializes distinct Muezzin voices for each of the 5 prayers', () {
      final notif = PrayerNotificationService.instance;

      expect(notif.getPrayerVoice('الفجر'), equals('adhan_fajr'));
      expect(notif.getPrayerVoice('الظهر'), equals('adhan_makkah'));
      expect(notif.getPrayerVoice('العصر'), equals('adhan_madinah'));
      expect(notif.getPrayerVoice('المغرب'), equals('adhan_cairo'));
      expect(notif.getPrayerVoice('العشاء'), equals('adhan_aqsa'));
    });

    test('setPrayerVoice updates and persists voice for specific prayer',
        () async {
      final notif = PrayerNotificationService.instance;

      // Assign Sheikh Hussary for Asr
      await notif.setPrayerVoice('العصر', 'adhan_hussary');
      expect(notif.getPrayerVoice('العصر'), equals('adhan_hussary'));

      final prefs = await SharedPreferences.getInstance();
      expect(
          prefs.getString('notif_prayer_voice_العصر'), equals('adhan_hussary'));

      // Dhuhr remains untouched
      expect(notif.getPrayerVoice('الظهر'), equals('adhan_makkah'));
    });

    test('setAllPrayersVoice updates all 5 prayers to chosen Muezzin',
        () async {
      final notif = PrayerNotificationService.instance;

      await notif.setAllPrayersVoice('adhan_hussary');

      expect(notif.getPrayerVoice('الفجر'), equals('adhan_hussary'));
      expect(notif.getPrayerVoice('الظهر'), equals('adhan_hussary'));
      expect(notif.getPrayerVoice('العصر'), equals('adhan_hussary'));
      expect(notif.getPrayerVoice('المغرب'), equals('adhan_hussary'));
      expect(notif.getPrayerVoice('العشاء'), equals('adhan_hussary'));
    });

    testWidgets(
        'Renders Per-Prayer Muezzin Manager Sheet with 5 prayers and preview buttons',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showSettingsAdhanVoiceModal(context),
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      // Open the sheet
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Verify Header
      expect(find.textContaining('مؤذنو الصلوات الخمس'), findsOneWidget);

      // Verify all 5 prayers are listed
      expect(find.text('صلاة الفجر'), findsOneWidget);
      expect(find.text('صلاة الظهر'), findsOneWidget);
      expect(find.text('صلاة العصر'), findsOneWidget);
      expect(find.text('صلاة المغرب'), findsOneWidget);
      expect(find.text('صلاة العشاء'), findsOneWidget);

      await tester.tap(find.text('صلاة الفجر'));
      await tester.pumpAndSettle();
      expect(find.text('مؤذن الفجر'), findsOneWidget);
      expect(find.text('استماع'), findsWidgets);
      expect(find.text('تعيين'), findsWidgets);
    });

    testWidgets(
        'PrayerMuezzinSelectorCard renders 5 prayers with dropdown buttons and preview on screen',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PrayerMuezzinSelectorCard(isDark: false),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Header
      expect(find.textContaining('اختيار مؤذن لكل صلاة'), findsOneWidget);

      // Verify all 5 prayers exist
      expect(find.text('صلاة الفجر'), findsOneWidget);
      expect(find.text('صلاة الظهر'), findsOneWidget);
      expect(find.text('صلاة العصر'), findsOneWidget);
      expect(find.text('صلاة المغرب'), findsOneWidget);
      expect(find.text('صلاة العشاء'), findsOneWidget);

      await tester.tap(find.text('صلاة العصر'));
      await tester.pumpAndSettle();
      expect(find.text('مؤذن العصر'), findsOneWidget);
      expect(find.text('استماع'), findsWidgets);
      expect(find.text('تعيين'), findsWidgets);
    });
  });
}
