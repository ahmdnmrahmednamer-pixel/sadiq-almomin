import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/bundled_tafsir_source.dart';
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('Jalalayn original chapter text and corrected navigation, absent text stays absent',()async{
  final source=BundledTafsirSource(readAsset:(p)=>File(p).readAsString());
  final chapters=jsonDecode(await File('assets/data/quran_ayahs.json').readAsString())as Map;
  final missing=<String>[];var count=0;
  for(final key in chapters.keys){final s=int.parse(key);for(var a=1;a<=(chapters[key]as List).length;a++){
   final entry=await source.fetch('jalalayn_corrected',s,a);
   if(entry==null){missing.add('$s:$a');continue;}expect(entry.pages,isNotEmpty);count++;
  }}
  expect((await source.fetch('jalalayn_corrected',68,49))!.sourceWarning,contains('ينقطع نصها'));
  expect((await source.fetch('jalalayn_corrected',68,50))!.sourceWarning,isNull);
  expect(count,6236);expect(missing,isEmpty);
  for(final p in [(1,1),(55,32)]){final e=(await source.fetch('jalalayn_corrected',p.$1,p.$2))!;expect(e.sourceUrl,'https://quranpedia.net/book/17441');expect(e.pages.single.sourceUrl,e.sourceUrl);}
  final complete=(await source.fetch('jalalayn_corrected',68,49))!;expect(complete.pages.length,2);expect(complete.pages.last.text,contains('غير مذموم'));expect(complete.pages.last.sourceUrl,'https://quranpedia.net/book/17441');
  for(final pair in <(int,int,int)>[(7,198,347566),(47,34,351393),(54,40,351722),(55,18,351756),(55,34,351770),(77,34,352538),(77,37,352541),(77,45,352550),(77,47,352552),(77,49,352554),(83,20,352758)]){
   expect((await source.fetch('jalalayn_corrected',pair.$1,pair.$2))!.pages.first.sourceId,pair.$3);
  }
  for(final pair in <(int,int,int)>[(26,144,349728),(55,28,351766),(55,30,351767)]){
   final entry=(await source.fetch('jalalayn_corrected',pair.$1,pair.$2))!;expect(entry.pages.first.sourceId,pair.$3);expect(entry.pages.first.verseIds,contains('${pair.$2}'));
  }
  expect((await source.fetch('jalalayn_corrected',7,193))!.pages.map((p)=>p.sourceId),isNot(contains(347566)));
 });

 test('Jalalayn 3:98 missing gloss is stated and 3:99 continuation link never claims to recover 3:98',()async{
  final source=BundledTafsirSource(readAsset:(p)=>File(p).readAsString());
  final e98=(await source.fetch('jalalayn_corrected',3,98))!;
  final e99=(await source.fetch('jalalayn_corrected',3,99))!;
  expect(e98.pages.map((p)=>p.sourceId),[346669]);
  expect(e99.pages.map((p)=>p.sourceId),[346669,346670]);
  // The source entry is kept byte-identical: the missing 3:98 gloss is not supplied from anywhere.
  for(final p in e98.pages){expect(p.text.contains('فيجازيكم عليه'),isFalse);expect(p.text.contains('شهيد على ما تعملون'),isFalse);}
  expect(e98.sourceWarning,contains('غير موجود'));expect(e98.sourceWarning,contains('99'));
  expect(e99.sourceWarning,contains('98'));expect(e99.sourceWarning,contains('غير موجود'));
  expect(e99.sourceWarning!.contains('أُكمل'),isFalse);
  for(final a in [97,100]){expect((await source.fetch('jalalayn_corrected',3,a))!.sourceWarning,isNull);}
 });
}
