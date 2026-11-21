import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/budur_source.dart';
import '../lib/core/models/ayah.dart';
import '../lib/core/models/surah.dart';

// Regression: registry fingerprints are written over (previous, own, next)
// passage texts with an empty string for a missing neighbor. The runtime used
// to return null at the edges, so the existing 63:0 quarter-end entry could
// never validate and every Munafiqun passage stayed blocked. With the edge
// context computed, the stored fingerprint validates and exactly the six
// downstream headings link, in monotone order 4,5,10,10,11,11.
String loadBundled() {
  final bytes = File('assets/data/budur-original.gz').readAsBytesSync();
  final value = utf8.decode(gzip.decode(bytes));
  final stop = value.indexOf('تصويبات للشيخ');
  return value.substring(0, stop);
}

void main() {
  test('Munafiqun edge fingerprint validates and releases its six headings', () {
    final source = loadBundled();
    final surahsJson =
        jsonDecode(File('assets/data/surahs.json').readAsStringSync()) as List;
    final s = surahsJson.firstWhere((e) => e['id'] == 63);
    final surah = Surah(
        id: s['id'], nameAr: s['name_ar'], nameSimple: s['name_simple'],
        revelationPlace: s['revelation_place'], revelationOrder: s['revelation_order'],
        ayahCount: s['ayah_count'], hasBasmala: s['has_basmala'] == 1,
        pageStart: s['page_start'], pageEnd: s['page_end']);
    final rows = (jsonDecode(File('assets/data/surahs/63.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    final ayahs = rows.map(Ayah.fromRow).toList();
    final ps = BudurSource.passages(source, surah, ayahs);
    expect(ps.length, 10);
    expect(ps[0].text, '" لا يفقهون " آخر الربع.');
    expect(ps[0].ayahs, isEmpty, reason: 'the quarter-end marker itself never links');
    final expected = <int, List<int>>{
      4: [4], 5: [5], 6: [10], 7: [10], 8: [11], 9: [11],
    };
    for (final e in expected.entries) {
      expect(ps[e.key].ayahs, e.value, reason: 'passage ${e.key}');
    }
    // Negative controls: the marker, the summary labels and the pre-heading
    // passage keep no links.
    expect(ps[1].ayahs, isEmpty);
    expect(ps[2].ayahs, isEmpty);
    expect(ps[3].ayahs, isEmpty);
  });
}
