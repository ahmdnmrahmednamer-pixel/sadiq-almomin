import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/bundled_tafsir_source.dart';

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('printed-heading page index reaches all Quran verses without remote API',()async{
  final source=BundledTafsirSource(readAsset:(p)=>File(p).readAsString());
  final chapters=jsonDecode(await File('assets/data/quran_ayahs.json').readAsString()) as Map;
  var count=0;
  for(final key in chapters.keys){final s=int.parse(key);for(var a=1;a<=(chapters[key]as List).length;a++){
   final entry=await source.fetch('ibn_kathir_pages',s,a);expect(entry,isNotNull,reason:'$s:$a');
   expect(entry!.pages,isNotEmpty);expect(entry.pages.first.text.runes.length,greaterThan(entry.pages.first.focusOffset));
   final focus=String.fromCharCodes(entry.pages.first.text.runes.skip(entry.pages.first.focusOffset));
   expect(focus,startsWith('['),reason:'source heading absent $s:$a');count++;
  }}
  expect(count,6236);
  final nas=(await source.fetch('ibn_kathir_pages',114,2))!;
  expect(nas.pages.map((p)=>p.sourceId).toList(),[461204,461205,461206]);
  expect(nas.pages.map((p)=>p.text).join(),isNot(contains('فهرس المحتويات')));
  final infitar=(await source.fetch('ibn_kathir_pages',82,13))!;
  final text=String.fromCharCodes(infitar.pages.first.text.runes.skip(infitar.pages.first.focusOffset));
  expect(text,startsWith('[سورة الانفطار'));expect(text,contains('١٣'));expect(text,contains('١٩'));
  for(final a in [73,74]){
   final r=(await source.fetch('ibn_kathir_pages',16,a))!;
   final t=String.fromCharCodes(r.pages.first.text.runes.skip(r.pages.first.focusOffset));
   expect(t,startsWith('[سورة النحل'));expect(t,contains('يَعْبُدُونَ')); // unchanged original source, not a generated replacement
  }
 },timeout:const Timeout(Duration(minutes:3)));
}
