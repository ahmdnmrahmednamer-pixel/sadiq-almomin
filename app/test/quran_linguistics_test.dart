import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/models/surah.dart';
import 'package:almomin/core/models/ayah.dart';
import 'package:almomin/core/services/quran_linguistics_service.dart';
import 'package:almomin/core/services/lubab_source.dart';
import 'package:almomin/features/mushaf/widgets/ayah_linguistics_sheet.dart';
import 'package:almomin/features/mushaf/widgets/ayah_action_sheet.dart';

// Synthetic transport input, never a religious narration or app data.
class FixtureLubab extends LubabSource {
  final List<LubabEntry> entries;
  final bool fail;
  final List<(int, int)> calls = [];
  FixtureLubab(this.entries, {this.fail = false});
  @override
  Future<List<LubabEntry>> fetch(int surah, int ayah) async {
    calls.add((surah, ayah));
    if (fail) throw const FormatException('synthetic source revision mismatch');
    return entries;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    QuranLinguisticsService.setSourceForTesting(FixtureLubab([]));
  });

  tearDown(() => QuranLinguisticsService.setSourceForTesting(null));

  group('QuranLinguisticsService Unit Tests (FR-QUR-005 & FR-QUR-006)', () {
    test('Returns exact source text and page scope without authenticating an incident', () async {
      final source = FixtureLubab([
        const LubabEntry('SYNTHETIC_SOURCE_112_1\nSOURCE_NOTE', [7, 8]),
      ]);
      QuranLinguisticsService.setSourceForTesting(source);
      final res = await QuranLinguisticsService.getDetails(surahId: 112, ayahNumber: 1);
      expect(source.calls, [(112, 1)]);
      expect(res.asbabNuzul.hasSourceText, isTrue);
      expect(res.asbabNuzul.hasSpecificIncident, isFalse);
      expect(res.asbabNuzul.narration, 'SYNTHETIC_SOURCE_112_1\nSOURCE_NOTE');
      expect(res.asbabNuzul.source, contains('7، 8'));
      expect(res.asbabNuzul.source, contains(LubabSource.sourceUrl));
      expect(res.asbabNuzul.source, contains('ليس حكمًا على صحة الرواية'));
    });

    test('Source errors are unavailable, not an invented cause for the selected verse', () async {
      final source = FixtureLubab([], fail: true);
      QuranLinguisticsService.setSourceForTesting(source);
      for (final surah in [108, 111]) {
        final res = await QuranLinguisticsService.getDetails(surahId: surah, ayahNumber: 1);
        expect(res.asbabNuzul.hasSpecificIncident, isFalse);
        expect(res.asbabNuzul.hasSourceText, isFalse);
        expect(res.asbabNuzul.narration,
            'تعذر تحميل نص المصدر أو تغيّرت نسخته. هذا لا يعني عدم وجود سبب نزول لهذه الآية.');
      }
      expect(source.calls, [(108, 1), (111, 1)]);
    });

    test('Provides classical Ghareeb vocabulary dictionary meanings', () async {
      final res = await QuranLinguisticsService.getDetails(surahId: 112, ayahNumber: 2);
      // Contains ﴿الصمد﴾
      final hasSamad = res.wordMeanings.any((w) => w.word == 'الصمد');
      expect(hasSamad, isTrue);

      final samadMeaning = res.wordMeanings.firstWhere((w) => w.word == 'الصمد');
      expect(samadMeaning.meaning.contains('يُصمد إليه في الحوائج'), isTrue);
    });

    test('An unmapped verse is not declared to have no historical cause', () async {
      final res = await QuranLinguisticsService.getDetails(surahId: 18, ayahNumber: 10);
      expect(res.asbabNuzul.hasSourceText, isFalse);
      expect(res.asbabNuzul.hasSpecificIncident, isFalse);
      expect(res.asbabNuzul.narration,
          'لم يُثبت ربط هذا الموضع في الفهرس بعد. هذا لا يعني عدم وجود سبب نزول لهذه الآية.');
    });

    test('Formats linguistics results for share and copy per FR-QUR-006', () async {
      final res = await QuranLinguisticsService.getDetails(surahId: 112, ayahNumber: 1);
      final shareText = res.formatForShare('الإخلاص');

      expect(shareText.contains('سورة الإخلاص'), isTrue);
      expect(shareText.contains('نص المصدر (لباب النقول، السيوطي)'), isTrue);
      expect(shareText, contains('لم يُثبت ربط هذا الموضع'));
      expect(shareText, contains('الجدول في إعراب القرآن الكريم، محمود صافي'));
      expect(shareText.contains('الإعراب والدلالة النحوية'), isTrue);
      expect(shareText.contains('تطبيق صديق المؤمن'), isTrue);
    });
  });

  group('AyahLinguisticsSheet & AyahActionSheet Widget Tests', () {
    const testSurah = Surah(
      id: 112,
      nameAr: 'الإخلاص',
      nameSimple: 'Al-Ikhlas',
      revelationPlace: 'makkah',
      revelationOrder: 22,
      ayahCount: 4,
      hasBasmala: true,
      pageStart: 604,
      pageEnd: 604,
    );

    const testAyah = Ayah(
      id: 6222,
      surahId: 112,
      ayahNumber: 1,
      juz: 30,
      hizb: 60,
      rub: 240,
      page: 604,
      sajdah: 0,
      textUthmani: 'قُلْ هُوَ اللَّهُ أَحَدٌ',
      textImlaei: 'قل هو الله أحد',
      textSearch: 'قل هو الله احد',
    );

    testWidgets('Renders AyahLinguisticsSheet with 3 tabs and displays content', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AyahLinguisticsSheet(
              surah: testSurah,
              ayah: testAyah,
              initialTabIndex: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check Header and Tabs
      expect(find.text('سورة الإخلاص — آية ١'), findsOneWidget);
      expect(find.text('معاني الكلمات'), findsOneWidget);
      expect(find.text('أسباب النزول'), findsOneWidget);
      expect(find.text('إعراب الآية'), findsOneWidget);

      // Switch to Asbab al-Nuzul Tab
      await tester.tap(find.text('أسباب النزول'));
      await tester.pumpAndSettle();

      expect(find.text('لباب النقول'), findsOneWidget);
      expect(find.textContaining('لم يُثبت ربط هذا الموضع'), findsOneWidget);
      expect(find.text('سؤال المشركين عن نسب الله وصفته'), findsNothing);

      // Switch to I'rab Tab
      await tester.tap(find.text('إعراب الآية'));
      await tester.pumpAndSettle();

      expect(find.text('فتح إعراب الآية'), findsOneWidget);
      expect(find.textContaining('محمود صافي'), findsOneWidget);
    });

    testWidgets('AyahActionSheet includes dedicated buttons for Meanings, Asbab, and Irab', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AyahActionSheet(
              surah: testSurah,
              ayah: testAyah,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('معاني الكلمات'), findsOneWidget);
      expect(find.text('أسباب النزول'), findsOneWidget);
      expect(find.text('إعراب الآية'), findsOneWidget);
      expect(find.text('التفسير والشروح'), findsOneWidget);
    });
  });
}
