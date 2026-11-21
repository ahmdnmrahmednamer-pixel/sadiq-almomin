import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/models/ayah.dart';
import '../lib/core/models/surah.dart';
import '../lib/core/services/budur_source.dart';
import '../lib/core/services/budur_bounded_quarters.dart';

void main() {
  final sourcePath = Platform.environment['BUDUR_REFERENCE_SOURCE'];
  test('bounded original quarter labels reopen only the following source context', () {
    if (sourcePath == null) return;
    final source = File(sourcePath).readAsStringSync();
    final chapters = (jsonDecode(File('assets/data/surahs.json').readAsStringSync()) as List)
        .map((r) => Surah.fromJson(Map<String,dynamic>.from(r))).toList();
    const endpoints = <int,Map<int,int>>{
      2:{130:74,294:188},4:{95:73,137:113,180:147,194:162},
      9:{82:92},12:{90:76},17:{35:49},20:{45:82},
    };
    final results = <int,List<BudurPassage>>{};
    for(final chapter in endpoints.entries) {
      final surah=chapters.singleWhere((s)=>s.id==chapter.key);
      final ayahs=(jsonDecode(File('assets/data/surahs/${surah.id}.json').readAsStringSync())as List)
          .map((r)=>Ayah.fromRow(Map<String,dynamic>.from(r))).toList();
      final passages=BudurSource.passages(source,surah,ayahs);results[surah.id]=passages;
      for(final end in chapter.value.entries) {
        final meta=budurBoundedQuarterEnds['${surah.id}:${end.key}']!;
        expect(meta.$1,end.value);
        // A bound is structural context only, not an ordinary verse link.
        expect(passages[end.key].ayahs,isEmpty);
        expect(passages[end.key+1].text,startsWith('الممال'));
        expect(passages[end.key+1].ayahs,isEmpty);
      }
      if(surah.id==2) {
        expect(passages[134].ayahs,[75]);
        expect(passages[298].ayahs,[189]);
        for(final n in [104,130,156]) {
          final original=passages[n].text;
          expect(source.contains(original),isTrue);
          final changed=BudurSource.passages(source.replaceFirst(original,'$original CHANGED_SOURCE'),surah,ayahs);
          expect(changed[134].ayahs,isEmpty,reason:'changed target or either independent bound revokes grant');
        }
        final absent=BudurSource.passages(source,surah,ayahs.where((a)=>a.ayahNumber!=59).toList());
        expect(absent[134].ayahs,isEmpty,reason:'missing independent lower Quran evidence');
      }
    }
    // Ordinary quoted words in a summary must not be promoted by this change.
    expect(results[2]![226].ayahs,isEmpty);
    expect(results[2]![297].ayahs,isEmpty);
  }, skip:sourcePath==null?'Set BUDUR_REFERENCE_SOURCE to the original book':false);
}
