import 'dart:convert';import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/bundled_tafsir_source.dart';
void main(){TestWidgetsFlutterBinding.ensureInitialized();test('Qurtubi printed-heading bundle retains original source and all context keys',()async{
 final source=BundledTafsirSource(readAsset:(path)=>File(path).readAsString());
 final quran=jsonDecode(await File('assets/data/quran_ayahs.json').readAsString())as Map;var n=0;
 for(final key in quran.keys){final s=int.parse(key);for(var a=1;a<=(quran[key]as List).length;a++){
  final entry=await source.fetch('qurtubi_printed',s,a);expect(entry,isNotNull,reason:'$s:$a');expect(entry!.bookId,14565);expect(entry.pages,isNotEmpty);expect(entry.sourceUrl,'https://quranpedia.net/book/14565');n++;
 }}expect(n,6236);
 for(final p in <(int,int,String)>[(7,161,'وَإِذْ قِيلَ'),(68,37,'أَمْ لَكُمْ'),(5,39,'فَمَنْ تابَ'),(6,86,'واليسع'),(37,164,'وما منا')]){
  final entry=(await source.fetch('qurtubi_printed',p.$1,p.$2))!;expect(entry.pages.map((v)=>v.text).join('\n'),contains(p.$3));
 }
 final first=(await source.fetch('qurtubi_printed',1,1))!.pages.first;expect(first.focusOffset,greaterThan(100000));expect(first.previousContextTitle,'مقدمة الكتاب وتفسير الاستعاذة');expect(first.text.substring(first.focusOffset),startsWith('[سورة الفاتحة'));
});}
