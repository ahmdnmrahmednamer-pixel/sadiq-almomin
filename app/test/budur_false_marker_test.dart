import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/budur_source.dart';
import '../lib/core/models/ayah.dart';
import '../lib/core/models/surah.dart';

// Regression: the Maida chapter wraps the sentence "المدغم الواقع بعد حرف
// المد" across a line boundary. The lone المدغم line is a sentence subject,
// not a summary label, so the headings after it are ordinary verse headings.
// The passage split, text and order stay verbatim; only the summary
// classification is withheld for the fingerprinted passage.
String loadBundled() {
  final bytes = File('assets/data/budur-original.gz').readAsBytesSync();
  final value = utf8.decode(gzip.decode(bytes));
  final stop = value.indexOf('تصويبات للشيخ');
  return value.substring(0, stop);
}

void main() {
  test('Maida false marker keeps text and releases only its blocked headings',
      () {
    final source = loadBundled();
    final surahsJson =
        jsonDecode(File('assets/data/surahs.json').readAsStringSync()) as List;
    final s = surahsJson.firstWhere((e) => e['id'] == 5);
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
    final rows = (jsonDecode(File('assets/data/surahs/5.json').readAsStringSync())
            as List)
        .cast<Map<String, dynamic>>();
    final ayahs = rows.map(Ayah.fromRow).toList();
    final ps = BudurSource.passages(source, surah, ayahs);
    expect(ps.length, 172);
    // The wrapped sentence is preserved verbatim in its original position.
    expect(ps[1].text, startsWith('المدغم'));
    expect(ps[1].text, contains('الواقع بعد حرف المد'));
    expect(ps[1].ayahs, isEmpty);
    // The headings the false marker blocked resolve to their unique verses.
    final expected = <int, List<int>>{
      2: [2],
      4: [2],
      5: [2],
      6: [3],
      7: [3],
      9: [3],
      11: [6],
      12: [6],
      13: [6],
      15: [6],
      17: [9],
      19: [11],
    };
    expected.forEach((i, a) => expect(ps[i].ayahs, a, reason: 'passage 5:$i'));
    // Negative controls: repeated quotes and the real summary after the true
    // quarter marker stay unlinked.
    expect(ps[3].ayahs, isEmpty);
    expect(ps[21].ayahs, isEmpty);
  });
}
