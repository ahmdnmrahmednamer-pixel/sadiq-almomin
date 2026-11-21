import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/budur_source.dart';
import '../lib/core/services/budur_verse_linker.dart';
import '../lib/core/models/ayah.dart';
import '../lib/core/models/surah.dart';

void main() {
 final raw=utf8.decode(gzip.decode(File('assets/data/budur-original.gz').readAsBytesSync()));
 final source=raw.substring(0,raw.indexOf('تصويبات للشيخ'));
 final chapters=(jsonDecode(File('assets/data/surahs.json').readAsStringSync()) as List).map((r)=>Surah.fromJson(Map<String,dynamic>.from(r))).toList();
 List<Ayah> verses(int sid) => (jsonDecode(File('assets/data/surahs/$sid.json').readAsStringSync()) as List).map((r)=>Ayah.fromRow(Map<String,dynamic>.from(r))).toList();
 List<BudurPassage> run(int sid, String text, [List<Ayah>? rows]) => BudurSource.passages(text, chapters.firstWhere((s)=>s.id==sid), rows??verses(sid));
 final expected=<String,List<int>>{
 '12:37': [31],
 '12:38': [31],
 '12:40': [33],
 '12:41': [33],
 '12:45': [36],
 '12:46': [37],
 '12:47': [37],
 '12:48': [37],
 '12:50': [39],
 '12:51': [43],
 '12:55': [45],
 '12:56': [45],
 '12:57': [46],
 '12:58': [47],
 '12:59': [49],
 '12:63': [51],
 '12:64': [51],
 '12:65': [52],
 '15:15': [49],
 '15:16': [49],
 '15:17': [51],
 '15:18': [53],
 '15:19': [54],
 '15:20': [56],
 '15:21': [59],
 '15:22': [60],
 '15:23': [61],
 '15:24': [65],
 '15:25': [65],
 '15:26': [67],
 '15:27': [68, 69],
 '15:28': [71],
 '15:31': [94],
 '15:33': [99],
};
 test('two fingerprinted source-end labels release only supported headings', () {
  final bySurah={12:run(12,source),15:run(15,source)};
  for(final e in expected.entries) {
   final parts=e.key.split(':').map(int.parse).toList();
   expect(bySurah[parts[0]]![parts[1]].ayahs,e.value,reason:e.key);
  }
  // This spelling mismatch is not a global normalizer repair or direct link.
  expect(BudurVerseIndex(verses(12)).occurrences('الخاطئين'),isEmpty);
  expect(bySurah[12]![30].ayahs,isEmpty);
  expect(bySurah[15]![10].ayahs,isEmpty);
  expect(bySurah[12]![34].ayahs,isEmpty);
  expect(bySurah[15]![11].ayahs,isEmpty);
  // The independent ledger's scalar 68 omitted the second explicit quote.
  // The unchanged combined heading has two separately grounded occurrences.
  expect(BudurVerseLinker.quotes(bySurah[15]![27].text),['تفضحون','تخزون']);
  expect(BudurVerseIndex(verses(15)).occurrences('تفضحون').map((c)=>c.ayah).toList(),[68]);
  expect(BudurVerseIndex(verses(15)).occurrences('تخزون').map((c)=>c.ayah).toList(),[69]);
 });
 test('source fingerprint changes fail closed without changing the quote gate', () {
  final alteredY=source.replaceFirst('" الخاطئين " قرأ أبو جعفر','" الخاطئين " قرأ ابو جعفر');
  final alteredH=source.replaceFirst('بمخرجين. آخر الربع.','بمخرجين. آخر الربع. تحقق');
  expect(alteredY,isNot(source));expect(alteredH,isNot(source));
  final y=run(12,alteredY),h=run(15,alteredH);
  for(final e in expected.entries) {
    final parts=e.key.split(':').map(int.parse).toList();
    expect((parts[0]==12?y:h)[parts[1]].ayahs,isEmpty,reason:'mutated ${e.key}');
  }
 });
}
