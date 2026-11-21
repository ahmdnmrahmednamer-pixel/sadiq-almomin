import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/budur_source.dart';
import '../lib/core/models/ayah.dart';
import '../lib/core/models/surah.dart';

// Regression: Hud passage 53 quotes "وقيل معا، وغيض". With the app's real
// normalizer, وقيل has exactly two occurrences and وغيض exactly one, all in
// 11:44, and the linked neighbours are monotone (11:52→43, 11:55→46). The
// reviewedLists grant therefore links the passage to [44].
// Passage 54 ("ويا سماء أقلعي") stays unlinked: the app normalizer finds zero
// occurrences of that quote even though the ayah text carries the same
// meaning, so it remains ambiguous until a verified bridge exists.
String loadBundled() {
  final bytes = File('assets/data/budur-original.gz').readAsBytesSync();
  final value = utf8.decode(gzip.decode(bytes));
  final stop = value.indexOf('تصويبات للشيخ');
  return value.substring(0, stop);
}

void main() {
  test('Hud passages 53 and scoped 54 link to 11:44', () {
    final source = loadBundled();
    final surahsJson =
        jsonDecode(File('assets/data/surahs.json').readAsStringSync()) as List;
    final s = surahsJson.firstWhere((e) => e['id'] == 11);
    final surah = Surah(
        id: s['id'],
        nameAr: s['name_ar'],
        nameSimple: s['name_simple'],
        revelationPlace: s['revelation_place'],
        revelationOrder: s['revelation_order'],
        ayahCount: s['ayah_count'],
        hasBasmala: s['has_basmala'] == 1,
        pageStart: s['page_start'],
        pageEnd: s['page_end']);
    final rows = (jsonDecode(
            File('assets/data/surahs/11.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    final ayahs = rows.map(Ayah.fromRow).toList();
    final ps = BudurSource.passages(source, surah, ayahs);
    expect(ps.length, 132);
    // Text is preserved verbatim.
    expect(ps[53].text,
        '" وقيل معا، وغيض " قرأ هشام والكسائي ورويس بإشمام الكسرة الضم، والباقون بالكسرة الكاملة.');
    expect(ps[53].ayahs, [44]);
    // Anchors unchanged, monotonic 43 → 44 → 46.
    expect(ps[52].ayahs, [43]);
    expect(ps[55].ayahs, [46]);
    // Independently verified joined Uthmani phrase admits this exact context,
    // without changing source text or broadening the normalizer.
    expect(ps[54].text, startsWith('" ويا سماء أقلعي "'));
    expect(ps[54].ayahs, [44]);
    final changed = source.replaceFirst('" ويا سماء أقلعي " قرأ',
        '" ويا سماء أقلعي "  قرأ');
    expect(changed, isNot(source));
    expect(BudurSource.passages(changed, surah, ayahs)[54].ayahs, isEmpty,
        reason: 'an unreviewed context must fail closed');
    // Negative controls: unrelated neighbours keep their previous state.
    expect(ps[50].ayahs, isEmpty);
    expect(ps[51].ayahs, isEmpty);
  });
}
