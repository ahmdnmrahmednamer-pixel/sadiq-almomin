import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/budur_source.dart';
import '../lib/core/models/ayah.dart';
import '../lib/core/models/surah.dart';
import '../lib/core/services/budur_shared_contexts.dart';

void main() {
  test('shared contexts fail closed without exact original source', () {
    expect(BudurSource.sharedContexts('', surahId: 75, ayahNumber: 1), isEmpty);
    expect(BudurSource.sharedContexts('unreviewed text', surahId: 80, ayahNumber: 1), isEmpty);
  });
  final sourcePath = Platform.environment['BUDUR_REFERENCE_SOURCE'];
  test('shared Hud summary cannot become private ayah 64 or ayah 1 content', () {
    final source=File(sourcePath!).readAsStringSync();
    final surah=(jsonDecode(File('assets/data/surahs.json').readAsStringSync()) as List)
        .map((r)=>Surah.fromJson(Map<String,dynamic>.from(r))).singleWhere((s)=>s.id==11);
    final ayahs=(jsonDecode(File('assets/data/surahs/11.json').readAsStringSync()) as List)
        .map((r)=>Ayah.fromRow(Map<String,dynamic>.from(r))).toList();
    final passages=BudurSource.passages(source,surah,ayahs);
    expect(passages[7].text,startsWith('" آية "'));
    expect(passages[8].text,startsWith('" الر "'));
    expect(passages[7].ayahs,isEmpty);
    expect(passages[8].ayahs,isEmpty);
    expect(BudurSource.sharedContexts(source,surahId:11,ayahNumber:1).single.text,contains(passages[7].text));
    expect(BudurSource.sharedContexts(source,surahId:11,ayahNumber:64),isEmpty);
  },skip:sourcePath==null?'Set BUDUR_REFERENCE_SOURCE to the original book':false);
  test('all reviewed quarter contexts preserve text, boundaries and attribution', () {
    final source = File(sourcePath!).readAsStringSync();
    expect(budurSharedContextGrants, hasLength(51));
    for (final grant in budurSharedContextGrants) {
      final raw = source.substring(grant.start, grant.end);
      final expected = raw.replaceAll(RegExp(r'\s*الجزء:\s*\d+\s*¦\s*الصفحة:\s*\d+\s*'), '\n\n').trim();
      expect(sha256.convert(utf8.encode(raw)).toString(), grant.sha256);
      expect(raw, startsWith('الممال'));
      expect(raw, contains('المدغم'));
      for (final range in grant.ranges) {
        for (var ayah = range.$2; ayah <= range.$3; ayah++) {
          final matches = BudurSource.sharedContexts(source, surahId: range.$1, ayahNumber: ayah);
          expect(matches, hasLength(1), reason: '${range.$1}:$ayah');
          final p = matches.single;
          expect(p.text, expected);
          expect(p.ayahs, isEmpty);
          expect(p.contextNote, contains('سياق مشترك'));
          expect(p.firstPage, grant.firstPage);
          expect(p.lastPage, grant.lastPage);
        }
        for (final outside in [range.$2 - 1, range.$3 + 1]) {
          if (outside < 1) continue;
          expect(BudurSource.sharedContexts(source, surahId: range.$1, ayahNumber: outside)
              .where((p) => p.text == expected), isEmpty);
        }
        final whole = BudurSource.sharedContexts(source, surahId: range.$1, ayahNumber: 0)
            .where((p) => p.text == expected);
        expect(whole, range.$1 == grant.physicalSurah ? isEmpty : hasLength(1));
      }
      final target = grant.ranges.first;
      for (final at in [grant.start, grant.end - 1, grant.labelStart, grant.labelEnd - 1]) {
        final changed = source.replaceRange(at, at + 1, 'X');
        expect(BudurSource.sharedContexts(changed, surahId: target.$1, ayahNumber: target.$2), isEmpty);
      }
    }
  }, skip: sourcePath == null ? 'Set BUDUR_REFERENCE_SOURCE to the original book' : false);
}
