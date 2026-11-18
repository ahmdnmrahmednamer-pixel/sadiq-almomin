import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/ramadan_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/ramadan/ramadan_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
    await PrayerService.instance.init();
    await RamadanService.instance.init();
  });

  group('RamadanService Unit Tests (FR-CAL-004)', () {
    test('generateImsakiyyah returns empty when location is UNKNOWN and generates 30-day table for verified coordinates', () {
      expect(RamadanService.instance.generateImsakiyyah(), isEmpty);

      final days = RamadanService.instance.generateImsakiyyah(
        latitude: 24.7136,
        longitude: 46.6753,
      );
      expect(days.length, 30);

      for (int i = 0; i < 30; i++) {
        final d = days[i];
        expect(d.dayNumber, i + 1);
        expect(d.dayName.isNotEmpty, isTrue);
        expect(d.imsakTime.isNotEmpty, isTrue);
        expect(d.fajrTime.isNotEmpty, isTrue);
        expect(d.maghribTime.isNotEmpty, isTrue);
        expect(d.ishaTime.isNotEmpty, isTrue);
        expect(d.dailyDuaa.isNotEmpty, isTrue);
      }
    });

    test('getCountdown returns null when location is UNKNOWN and valid CountdownInfo when verified GPS exists', () async {
      expect(RamadanService.instance.getCountdown(), isNull);

      SharedPreferences.setMockInitialValues({
        PrayerService.locationSourceKey: PrayerService.locationSourceGps,
        PrayerService.locationUpdatedAtMsKey:
            DateTime.now().toUtc().millisecondsSinceEpoch,
        'last_latitude': 24.7136,
        'last_longitude': 46.6753,
        'last_city': 'الرياض، السعودية (موقعك الفعلي)',
      });
      await PrayerService.instance.init(forceReload: true);

      final countdown = RamadanService.instance.getCountdown();
      expect(countdown, isNotNull);
      expect(countdown!.title.isNotEmpty, isTrue);
      expect(countdown.remaining.isNegative, isFalse);
      expect(countdown.targetTimeFormatted.isNotEmpty, isTrue);
    });

    test('Fasting, Taraweeh, and Quran daily trackers mutate state and persist', () async {
      final service = RamadanService.instance;

      expect(service.isDayFasted(1), isFalse);
      expect(service.isTaraweehCompleted(1), isFalse);
      expect(service.isQuranCompleted(1), isFalse);
      expect(service.totalFastedCount, 0);

      // Toggle Fasted Day 1
      await service.toggleFasted(1);
      expect(service.isDayFasted(1), isTrue);
      expect(service.totalFastedCount, 1);
      expect(service.fastingProgress, closeTo(1 / 30.0, 0.001));

      // Toggle Taraweeh Day 1
      await service.toggleTaraweeh(1);
      expect(service.isTaraweehCompleted(1), isTrue);
      expect(service.totalTaraweehCount, 1);

      // Toggle Quran Day 1
      await service.toggleQuran(1);
      expect(service.isQuranCompleted(1), isTrue);
      expect(service.totalQuranCount, 1);

      // Verify persistence in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('ramadan_fasted_days'), contains('1'));
      expect(prefs.getStringList('ramadan_taraweeh_days'), contains('1'));
      expect(prefs.getStringList('ramadan_quran_days'), contains('1'));

      // Untoggle
      await service.toggleFasted(1);
      expect(service.isDayFasted(1), isFalse);
      expect(service.totalFastedCount, 0);
    });

    test('Ramadan supplications list contains authentic verified Duas', () {
      const duass = RamadanService.supplications;
      expect(duass.length, greaterThanOrEqualTo(5));

      for (final d in duass) {
        expect(d.title.isNotEmpty, isTrue);
        expect(d.arabicText.isNotEmpty, isTrue);
        expect(d.category.isNotEmpty, isTrue);
        expect(d.source.isNotEmpty, isTrue);
      }
    });
  });

  group('RamadanScreen Widget Tests', () {
    testWidgets('Renders RamadanScreen with 3 tabs and hero countdown', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: RamadanScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Screen title
      expect(find.text('إمساكية ومحراب رمضان المبارك'), findsOneWidget);

      // 3 Tabs
      expect(find.textContaining('الإمساكية'), findsOneWidget);
      expect(find.textContaining('متابع الصيام والعبادات'), findsOneWidget);
      expect(find.textContaining('أدعية وسنن الصائم'), findsOneWidget);

      // Hero banner
      expect(find.textContaining('تحديث الموقع الفعلي'), findsOneWidget);

      // Switch to Tab 2: Tracker
      await tester.tap(find.textContaining('متابع الصيام والعبادات'));
      await tester.pumpAndSettle();

      expect(find.text('سجل إنجاز العبادات الرمضانية'), findsOneWidget);
      expect(find.byTooltip('صليت التراويح / القيام'), findsWidgets);
      expect(find.text('التراويح'), findsOneWidget);

      // Switch to Tab 3: Supplications
      await tester.tap(find.textContaining('أدعية وسنن الصائم'));
      await tester.pumpAndSettle();

      expect(find.textContaining('دعاء النبي ﷺ عند الإفطار'), findsOneWidget);
      expect(find.textContaining('رمضان مبارك — تقبل الله منا ومنكم'), findsOneWidget);
    });
  });
}
