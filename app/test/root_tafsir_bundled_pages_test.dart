import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/bundled_tafsir_source.dart';
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('root-constrained editions retain all selected locations and exclude introductions',()async{
  final source=BundledTafsirSource(readAsset:(p)=>File(p).readAsString());
  final chapters=jsonDecode(await File('assets/data/quran_ayahs.json').readAsString())as Map;
  for(final edition in ['tabari_roots','baghawi_roots']){
   var count=0;
   for(final key in chapters.keys){final s=int.parse(key);for(var a=1;a<=(chapters[key]as List).length;a++){
    final entry=await source.fetch(edition,s,a);expect(entry,isNotNull,reason:'$edition $s:$a');expect(entry!.pages,isNotEmpty);expect(entry.pages.every((p)=>p.text.isNotEmpty),isTrue);count++;
   }}expect(count,6236);
   final nas=(await source.fetch(edition,114,2))!;expect(nas.pages.length,3);
   expect(nas.pages.first.text,contains('رَبِّ النَّاسِ'));expect(nas.pages.map((p)=>p.text).join(),isNot(contains('مقدمة التحقيق')));
   if(edition=='tabari_roots'){
    expect(nas.pages.map((p)=>p.sourceId).toList(),[21764,21765,21766]);
    final ahqaf=(await source.fetch(edition,46,1))!;expect(ahqaf.pages.first.sourceId,19914);expect(ahqaf.pages.first.text,contains('الأحقاف'));
    expect((await source.fetch(edition,40,1))!.pages.map((p)=>p.sourceId),isNot(contains(19914)));
   }else{expect(nas.pages.map((p)=>p.sourceId).toList(),[5012,5013,5014]);}
  }
 },timeout:const Timeout(Duration(minutes:3)));
}
