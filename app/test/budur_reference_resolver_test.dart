import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/models/ayah.dart';
import '../lib/core/models/surah.dart';
import '../lib/core/services/budur_source.dart';
import '../lib/core/services/budur_reference_resolver.dart';

void main() {
  test(
      'reference recognition rejects wrong chapter and missing author direction',
      () {
    expect(
        BudurReferenceResolver.references(
                21, '" أف لكم " تقدم في سورة الإسراء.')
            .single
            .surah,
        17);
    expect(
        BudurReferenceResolver.references(
            22, '" أف لكم " تقدم في سورة الإسراء.'),
        isEmpty);
    expect(BudurReferenceResolver.references(21, '" أف لكم "'), isEmpty);
    expect(
        BudurReferenceResolver.references(
            21, '" أف لكم، آخر " تقدم في سورة الإسراء.'),
        isEmpty);
  });
  test('source target ambiguity and wrong chapter fail closed', () {
    const surah = Surah(
        id: 2,
        nameAr: 'اختبار',
        nameSimple: 'اختبار',
        revelationPlace: 'makkah',
        revelationOrder: 1,
        ayahCount: 1,
        hasBasmala: false,
        pageStart: 1,
        pageEnd: 1);
    final ayahs = [
      Ayah.fromRow({
        'id': 1,
        'surah_id': 2,
        'ayah_number': 1,
        'juz': 1,
        'page': 1,
        'text_uthmani': 'لفظ'
      })
    ];
    const source =
        'سورة اختبار\n"لفظ" SOURCE_ONE\n"لفظ" SOURCE_TWO\nتصويبات للشيخ';
    expect(
        BudurReferenceResolver.resolve(
            source, const BudurReference(2, 'لفظ'), surah, ayahs),
        isNull);
    expect(
        BudurReferenceResolver.resolve(
            source, const BudurReference(3, 'لفظ'), surah, ayahs),
        isNull);
  });
  test(
      'an explicitly reviewed target identity disambiguates only that paragraph',
      () {
    const surah = Surah(
        id: 2,
        nameAr: 'اختبار',
        nameSimple: 'اختبار',
        revelationPlace: 'makkah',
        revelationOrder: 1,
        ayahCount: 1,
        hasBasmala: false,
        pageStart: 1,
        pageEnd: 1);
    final ayahs = [
      Ayah.fromRow({
        'id': 1,
        'surah_id': 2,
        'ayah_number': 1,
        'juz': 1,
        'page': 1,
        'text_uthmani': 'لفظ'
      })
    ];
    const source =
        'سورة اختبار\n"لفظ" SOURCE_ONE\n"لفظ" SOURCE_TWO\nتصويبات للشيخ';
    final resolved = BudurReferenceResolver.resolve(
        source,
        const BudurReference(2, 'لفظ', exactText: '"لفظ" SOURCE_ONE'),
        surah,
        ayahs);
    expect(resolved?.text, '"لفظ" SOURCE_ONE');
    expect(
        BudurReferenceResolver.resolve(
            source,
            const BudurReference(2, 'لفظ', exactText: '"لفظ" MISSING'),
            surah,
            ayahs),
        isNull);
  });
  test('reviewed author references resolve to unique original source passages',
      () {
    final path = Platform.environment['BUDUR_REFERENCE_SOURCE'];
    if (path == null) return;
    final source = File(path).readAsStringSync();
    final surahs =
        (jsonDecode(File('assets/data/surahs.json').readAsStringSync()) as List)
            .map((r) => Surah.fromJson(Map<String, dynamic>.from(r)))
            .toList();
    List<Ayah> ayahs(int n) =>
        (jsonDecode(File('assets/data/surahs/$n.json').readAsStringSync())
                as List)
            .map((r) => Ayah.fromRow(Map<String, dynamic>.from(r)))
            .toList();
    var count = 0;
    for (final n in [3, 5, 6, 10, 11, 13, 16, 18, 21, 23, 24, 28, 30, 32, 34, 53, 56]) {
      final passages = BudurSource.passages(
          source, surahs.singleWhere((s) => s.id == n), ayahs(n));
      for (final p in passages) {
        for (final ref in BudurReferenceResolver.references(n, p.text)) {
          final target = BudurReferenceResolver.resolve(source, ref,
              surahs.singleWhere((s) => s.id == ref.surah), ayahs(ref.surah));
          expect(p.ayahs, isNotEmpty,
              reason:
                  'reviewed reference must appear under its own verse n=$n text=${p.text}');
          if (n == 3) {
            expect(p.ayahs, [49]);
            final changed =
                source.replaceFirst(p.text, '${p.text} EXTRA_UNREVIEWED');
            final changedPassage = BudurSource.passages(
                    changed, surahs.singleWhere((s) => s.id == 3), ayahs(3))
                .singleWhere(
                    (candidate) => candidate.text.contains('EXTRA_UNREVIEWED'));
            expect(changedPassage.ayahs, isEmpty,
                reason:
                    'reviewed override must require original paragraph identity');
          }
          if (n == 5) expect(p.ayahs, ref.quote == 'فمن اضطر' ? [3] : [110]);
          if (n == 28) expect(p.ayahs, ref.surah == 21 ? [5] : [41]);
          if (n == 10) {
            expect(p.ayahs, [59]);
            final altered =
                source.replaceFirst('" قل آلله "', '" MISSING_NEIGHBOR "');
            final withoutNeighbor = BudurSource.passages(
                altered, surahs.singleWhere((s) => s.id == 10), ayahs(10));
            expect(
                withoutNeighbor
                    .singleWhere((candidate) => candidate.text == p.text)
                    .ayahs,
                isEmpty);
          }
          if (n == 11) expect(p.ayahs, [28]);
          if (n == 16) expect(p.ayahs, [48]);
          if (n == 24) expect(p.ayahs, [8]);
          if (n == 18) expect(p.ayahs, [50]);
          if (n == 30) expect(p.ayahs, [11]);
          if (n == 32) expect(p.ayahs, [24]);
          expect(target, isNotNull, reason: '$n ${ref.quote}');
          expect(target!.text, isNotEmpty);
          expect(target.firstPage, greaterThan(0));
          print(jsonEncode({
            'from': n,
            'fromPage': p.firstPage,
            'fromAyahs': p.ayahs,
            'to': ref.surah,
            'targetPage': target.firstPage,
            'quote': ref.quote,
            'targetText': target.text
          }));
          count++;
        }
      }
    }
    expect(count, 20);
  });
}
