import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Saadi 16:64, 26:134 and 56:30 carry edition-scoped print notices only', () {
    final m = jsonDecode(File('assets/data/tafsir_saadi_roots_manifest.json').readAsStringSync()) as Map;
    final w = Map<String, dynamic>.from(m['sourceWarnings'] as Map);
    expect(w.keys.toSet(), {'16:64', '26:134', '26:180', '26:183', '56:30', '22:20', '7:24'});
    expect(w['26:134'], contains('٥٩٥'));
    expect(w['56:30'], contains('٨٣٣'));
    expect(w['16:64'], contains('٤٤٣'));
    expect(w['7:24'], contains('ليس استكمالًا'));expect(w['7:24'], contains('٢٨٥'));
    expect(w['22:20'], contains('٥٣٦'));
    for (final v in w.entries.where((e)=>e.key!='22:20').map((e)=>e.value)) {
      expect(v, contains('في كل طبعة'));
      expect(v, isNot(contains('قال السعدي')));
    }
  });
}
