import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/models/ayah.dart';
import '../lib/core/models/surah.dart';
import '../lib/core/services/budur_source.dart';
import '../lib/core/services/budur_verse_linker.dart';

List<Ayah> sample(List<String> verses, {int surah = 1}) => [
      for (var i = 0; i < verses.length; i++)
        Ayah.fromRow({
          'id': 9000 + i,
          'surah_id': surah,
          'ayah_number': i + 1,
          'juz': 1,
          'page': 1,
          'text_uthmani': verses[i],
        }),
    ];
void main() {
  test('repetition requires two immediately adjacent independent anchors', () {
    final ayahs = sample(['مكرر', 'مرساة اولى', 'مكرر', 'مرساة اخيرة', 'مكرر']);
    expect(
        BudurVerseLinker.link([
          '"مرساة اولى"',
          '"مكرر"',
          '"مرساة اخيرة"'
        ], [
          false,
          false,
          false
        ], ayahs, repeatedReviewed: (_) => true),
        [
          [2],
          [3],
          [4]
        ]);
    expect(
        BudurVerseLinker.link(
                ['"مكرر"', '"مرساة اخيرة"'], [false, false], ayahs)
            .first,
        isEmpty);
  });
  test(
      'no inherited anchor, block crossing, reversed anchor or multiple candidates',
      () {
    final ayahs = sample(['مرساة اولى', 'مكرر', 'مكرر', 'مرساة اخيرة']);
    expect(
        BudurVerseLinker.link(['"مرساة اولى"', '"مكرر"', '"مرساة اخيرة"'],
            [false, false, false], ayahs)[1],
        isEmpty);
    expect(
        BudurVerseLinker.link(['"مرساة اخيرة"', '"مكرر"', '"مرساة اولى"'],
            [false, false, false], ayahs)[1],
        isEmpty);
    expect(
        BudurVerseLinker.link(
            ['"مرساة اولى"', 'الممال', '"مكرر"', '"مرساة اخيرة"'],
            [false, true, false, false],
            ayahs)[2],
        isEmpty);
  });
  test('immediate author both label requires exactly two complete occurrences',
      () {
    expect(
        BudurVerseLinker.link(['" لفظ " معا SOURCE'], [false], sample(['لفظ'])),
        [[]]);
    expect(
        BudurVerseLinker.link(
            ['" لفظ " معا SOURCE'], [false], sample(['لفظ لفظ'])),
        [
          [1]
        ]);
    final two = sample(['لفظ', 'لفظ']);
    expect(BudurVerseLinker.link(['" لفظ " معا SOURCE'], [false], two), [
      [1, 2]
    ]);
    expect(BudurVerseLinker.link(['" لفظ " معا SOURCE'], [true], two), [[]]);
    expect(
        BudurVerseLinker.link(
            ['" لفظ " معا SOURCE'], [false], sample(['لفظ', 'لفظ', 'لفظ'])),
        [[]]);
    expect(
        BudurVerseLinker.link(['" لفظ " general prose ثم معا'], [false], two),
        [[]]);
    expect(BudurVerseLinker.link(['" لفظ، آخر " معا'], [false], two), [[]]);
  });
  test('quoted summary item never becomes an ordinary verse heading', () {
    const surah = Surah(
        id: 1,
        nameAr: 'اختبار',
        nameSimple: 'اختبار',
        revelationPlace: 'makkah',
        revelationOrder: 1,
        ayahCount: 3,
        hasBasmala: false,
        pageStart: 1,
        pageEnd: 1);
    const text =
        'سورة اختبار\n"نهاية ثابتة" آخر الربع.\nالممال\n"لفظ قديم" SUMMARY_ONLY\nالمدغم\n"مستأنف" NEXT_SECTION\nالجزء: 1 ¦ الصفحة: 1\nتصويبات للشيخ';
    final results = BudurSource.passages(
        text, surah, sample(['لفظ قديم', 'نهاية ثابتة', 'مستأنف']));
    expect(results.firstWhere((p) => p.text.contains('SUMMARY_ONLY')).ayahs,
        isEmpty);
    expect(
        results.firstWhere((p) => p.text.contains('NEXT_SECTION')).ayahs, [3]);
    final doubtful = BudurSource.passages(
        text.replaceFirst('نهاية ثابتة', 'غير مثبت'),
        surah,
        sample(['لفظ قديم', 'نهاية ثابتة', 'مستأنف']));
    expect(doubtful.firstWhere((p) => p.text.contains('NEXT_SECTION')).ayahs,
        isEmpty);
  });
  test('word boundaries and within-verse repetitions are not unique', () {
    final ayahs = sample(['مرساة اولى', 'مكرر مكرر', 'مرساة اخيرة', 'ومكررون']);
    expect(BudurVerseLinker.occurrences('مكرر', ayahs).length, 2);
    expect(
        BudurVerseLinker.link(['"مرساة اولى"', '"مكرر"', '"مرساة اخيرة"'],
            [false, false, false], ayahs)[1],
        isEmpty);
    expect(BudurVerseLinker.occurrences('كرر', ayahs), isEmpty);
  });
  test('every quote in a multiple-verse paragraph needs its own evidence', () {
    final ayahs = sample(['اول', 'ثان', 'مكرر', 'مكرر']);
    expect(BudurVerseLinker.link(['"اول، ثان"'], [false], ayahs), [
      [1, 2]
    ]);
    expect(BudurVerseLinker.link(['"اول، مكرر"'], [false], ayahs), [[]]);
  });
  test('actual source and shipped Quran corpus structural regression', () {
    final sourcePath = Platform.environment['BUDUR_REFERENCE_SOURCE'];
    if (sourcePath == null) return;
    final source = File(sourcePath).readAsStringSync();
    final surahs =
        (jsonDecode(File('assets/data/surahs.json').readAsStringSync()) as List)
            .map((r) => Surah.fromJson(Map<String, dynamic>.from(r)))
            .toList();
    var passages = 0, assigned = 0;
    for (final surah in surahs) {
      final ayahs = (jsonDecode(File('assets/data/surahs/${surah.id}.json')
              .readAsStringSync()) as List)
          .map((r) => Ayah.fromRow(Map<String, dynamic>.from(r)))
          .toList();
      final result = BudurSource.passages(source, surah, ayahs);
      expect(result, isNotEmpty, reason: 'missing chapter ${surah.id}');
      const actualBoth = <int, Map<String, List<int>>>{
        6: {
          'ذكر اسم الله': [118, 119],
          'آلذكرين': [143, 144]
        },
        7: {
          'تأتيهم': [163]
        },
        8: {
          'بالعدوة': [42]
        },
        98: {
          'البرية': [6, 7]
        },
        99: {
          'يره': [7, 8]
        },
      };
      for (final expected
          in (actualBoth[surah.id] ?? const <String, List<int>>{}).entries) {
        final q = BudurVerseLinker.normalize(expected.key);
        final entry = result.singleWhere((p) =>
            BudurVerseLinker.quotes(p.text).length == 1 &&
            BudurVerseLinker.quotes(p.text).single == q &&
            p.text.contains('معا'));
        expect(entry.ayahs, expected.value,
            reason: 'source both ${surah.id} ${expected.key}');
      }
      const reviewedListAyahs = <int, Map<String, List<int>>>{
        2: {
          "\" اليسر والعسر \" قرأ أبو جعفر بضم السين فيهما، والباقون بالإسكان.":
              [185],
          "\" فيغفر ويعذب \" قرأ الشامي وعاصم وأبو جعفر ويعقوب برفع الراء والباء من الفعلين والباقون بجزمهما.":
              [284],
        },
        4: {
          "\" نوله ونصله \" قرأ قالون ويعقوب وهشام بخلف عنه بكسر الهاء من غير صلة، وقرأ البصري وشعبة وحمزة وأبو جعفر بإسكانها، والباقون بكسرها مع الصلة، وهو الوجه الثاني لهشام.":
              [115],
        },
        10: {
          "\" ولا أصغر ولا أكبر \" قرأ يعقوب وخلف وحمزة برفع الراء فيهما، والباقون بنصبها فيهما.":
              [61],
        },
        36: {
          "\" سدا، معا \" فتح السين فيهما حفص والأخوان وخلف، وضمها غيرهم.": [9],
        },
        39: {
          "\" فتحت وفتحت \" خفف التاء فيهما الكوفيون وشددها غيرهم.": [71, 73],
        },
        64: {
          "\" يكفر. ويدخله \" قرأ المدنيان والشامي بالنون في الفعلين والباقون بالياء التحتية فيهما.":
              [9],
        },
        71: {
          "\" ويؤخركم لا يؤخر \" أبدل ورش وأبو جعفر الهمزة واوا خالصة مطلقا، وكذلك حمزة عند الوقف.":
              [4],
        },
        75: {
          "\" تحبون وتذرون \" قرأ المكي والبصريان والشامي بياء الغيبة فيهما، والباقون بتاء الخطاب كذلك.":
              [20, 21],
        },
        66: {
          "\" امرأت الثلاثة وابنت \" رسمت كلها بالتاء ووقف عليها بالهاء المكي والبصريان والكسائي، والباقون بالتاء.":
              [10, 11, 12],
        },
      };
      for (final expected
          in (reviewedListAyahs[surah.id] ?? const <String, List<int>>{})
              .entries) {
        expect(result.singleWhere((p) => p.text == expected.key).ayahs,
            expected.value);
      }
      if (surah.id == 66) {
        final reviewed = result
            .singleWhere((p) => p.text.startsWith('" امرأت الثلاثة وابنت "'));
        final changed = BudurSource.passages(
            source.replaceFirst(
                reviewed.text, '${reviewed.text} UNREVIEWED_CHANGE'),
            surah,
            ayahs);
        expect(
            changed
                .singleWhere((p) => p.text.contains('UNREVIEWED_CHANGE'))
                .ayahs,
            isEmpty);
        final noThird = BudurSource.passages(
            source, surah, ayahs.where((a) => a.ayahNumber != 11).toList());
        expect(
            noThird.singleWhere((p) => p.text == reviewed.text).ayahs, isEmpty,
            reason: 'all three source occurrences are required');
      }
      if (surah.id == 36) {
        final withoutEvidence = BudurSource.passages(
            source, surah, ayahs.where((a) => a.ayahNumber != 9).toList());
        final entry = withoutEvidence
            .singleWhere((p) => p.text.startsWith('" سدا، معا "'));
        expect(entry.ayahs, isEmpty,
            reason:
                'reviewed list still requires both actual Quran occurrences');
      }
      passages += result.length;
      assigned += result.where((p) => p.ayahs.isNotEmpty).length;
      for (final p in result) {
        expect(p.ayahs.every((n) => n > 0 && n <= surah.ayahCount), isTrue);
        expect(p.firstPage <= p.lastPage, isTrue);
        if (p.text.startsWith('الممال') || p.text.startsWith('المدغم'))
          expect(p.ayahs, isEmpty);
      }
      if (surah.id == 1) {
        expect(result.where((p) => p.text.startsWith('" الرحيم')).single.ayahs,
            [3]);
        expect(result.where((p) => p.text.startsWith('" الصراط')).single.ayahs,
            isEmpty); // rasm differs, not guessed
      }
      if (surah.id == 2) {
        final p =
            result.firstWhere((p) => p.text.startsWith('" الحساب " آخر الربع'));
        expect(p.text.contains('الأهلة'),
            isFalse); // next block must not inherit verse 202
        final block = result.firstWhere(
            (p) => p.text.startsWith('الممال') && p.text.contains('الأهلة'));
        expect(block.ayahs, isEmpty);
        final repeated =
            result.where((p) => p.text.startsWith('" عليهم')).toList();
        for (final p in repeated)
          expect(p.ayahs.every((a) => a != 9000), isTrue);
      }
    }
    print(
        'Actual-source navigation: $passages passages, $assigned assigned passages; count is not a correctness/coverage percentage.');
  },
      skip: Platform.environment['BUDUR_REFERENCE_SOURCE'] == null
          ? 'Set BUDUR_REFERENCE_SOURCE to the original downloaded text'
          : false);
}
