import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/budur_source.dart';
import '../lib/core/models/ayah.dart';
import '../lib/core/models/surah.dart';

// Regression: Baqara passage 402 groups both mentions of الأرض in 2:255
// (ما في الأرض and والأرض) under the author's "معا" label, with وبإذنه in the
// book's listing conjunction. Source review confirmed the passage belongs to
// 2:255 by position (unbroken 402-406 run between anchors 2:401→254 and
// 2:407→256) and by quote order. The scoped grant links it to [255] only
// through the exact three-passage fingerprint plus the joined Quran phrase,
// which occurs exactly once in the sura, at 255. No normalizer change.
String loadBundled() {
  final bytes = File('assets/data/budur-original.gz').readAsBytesSync();
  final value = utf8.decode(gzip.decode(bytes));
  final stop = value.indexOf('تصويبات للشيخ');
  return value.substring(0, stop);
}

void main() {
  test('Baqara passage 402 links to 2:255 through the scoped grant', () {
    final source = loadBundled();
    final surahsJson =
        jsonDecode(File('assets/data/surahs.json').readAsStringSync()) as List;
    final s = surahsJson.firstWhere((e) => e['id'] == 2);
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
            File('assets/data/surahs/2.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    final ayahs = rows.map(Ayah.fromRow).toList();
    final ps = BudurSource.passages(source, surah, ayahs);
    expect(ps.length, 480);
    // Text is preserved verbatim.
    expect(ps[402].text, '" الأرض معا، وبإذنه " لا يخفى.');
    expect(ps[402].ayahs, [255]);
    // Anchors unchanged, monotone 254 → 255 → 256 → 257.
    expect(ps[401].ayahs, [254]);
    expect(ps[407].ayahs, [256]);
    expect(ps[408].ayahs, [257]);
    // The rest of the 255 run keeps its previous unlinked state.
    expect(ps[403].ayahs, isEmpty);
    expect(ps[404].ayahs, isEmpty);
    expect(ps[405].ayahs, isEmpty);
    expect(ps[406].ayahs, isEmpty);
    // Fail closed on mutation of the paragraph itself.
    final changed = source.replaceFirst('" الأرض معا، وبإذنه " لا يخفى.',
        '" الأرض معا، وبإذنه "  لا يخفى.');
    expect(changed, isNot(source));
    expect(BudurSource.passages(changed, surah, ayahs)[402].ayahs, isEmpty,
        reason: 'an unreviewed context must fail closed');
    // Fail closed on mutation of a fingerprint neighbour.
    final changedPrev = source.replaceFirst(
        '" لا بيع فيه ولا خلة ولا شفاعة " قرأ',
        '" لا بيع فيه ولا خلة ولا شفاعة "  قرأ');
    expect(changedPrev, isNot(source));
    expect(
        BudurSource.passages(changedPrev, surah, ayahs)[402].ayahs, isEmpty,
        reason: 'a changed neighbour must break the stored fingerprint');
  });
}
