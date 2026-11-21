import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/bundled_tafsir_source.dart';

void main(){
 test('exact selected location, page context, bounded chapter cache and no network',()async{
   var reads=0;
   Future<String> asset(String p)async{
     reads++;
     if(p.endsWith('manifest.json')){
       final chapters=<String,dynamic>{};
       for(var s=1;s<=4;s++){final raw=utf8.encode(jsonEncode({'bookId':9,'surah':s,'pages':[{'text':'<p>مقطع اختباري $s</p><br/>هامش محفوظ','part':'2','page':7,'ayahs':'12,13'}],'locations':{'2':[0]}}));chapters['$s']={'parts':1,'sha256':sha256.convert(raw).toString()};}
       return jsonEncode({'edition':'sample','book':{'id':9},'surahs':chapters});
     }
     final s=int.parse(p.split('_')[2]);
     final raw=utf8.encode(jsonEncode({'bookId':9,'surah':s,'pages':[{'text':'<p>مقطع اختباري $s</p><br/>هامش محفوظ','part':'2','page':7,'ayahs':'12,13'}],'locations':{'2':[0]}}));
     return base64Encode(gzip.encode(raw));
   }
   final source=BundledTafsirSource(readAsset:asset);
   expect(await source.fetch('sample',1,1),isNull);
   final e=await source.fetch('sample',1,2);expect(e!.bookId,9);expect(e.pages.single.text,contains('هامش محفوظ'));expect(e.pages.single.page,7);expect(e.pages.single.verseIds,'12,13');expect(reads,2);
   await source.fetch('sample',2,2);await source.fetch('sample',3,2);await source.fetch('sample',4,2);expect(reads,5);
   await source.fetch('sample',1,2);expect(reads,6);
 });
 test('repeated concurrent source failures remain caught, never stale source text',()async{
   var reads=0;
   final source=BundledTafsirSource(readAsset:(path)async{reads++;throw const FormatException('Source asset unavailable');});
   for(var n=0;n<3;n++){
     final calls=[source.fetch('sample',1,2),source.fetch('sample',1,2)];
     await Future.wait([for(final call in calls)expectLater(call,throwsFormatException)]);
   }
   expect(reads,greaterThan(0));
 });
 test('source order retained even with malformed table markup',(){
   expect(BundledTafsirSource.plain('<table><tr><td>أ</td></tr>ب</table>ج'),'أبج');
 });
 test('bad identity fails closed',()async{
   final s=BundledTafsirSource(readAsset:(p)async=>jsonEncode({'edition':'wrong','book':{'id':1},'surahs':{}}));
   expect(()=>s.fetch('sample',1,2),throwsFormatException);
 });
 final prep=Platform.environment['TAFSIR_PREPARED'];
 if(prep!=null)test('prepared original pages survive packing unchanged across chapters',()async{
   var checked=0;
   for(final edition in ['jalalayn','tabari','baghawi','ibn_kathir_alt']){
     final source=BundledTafsirSource(readAsset:(p)=>File('$prep/${p.split('/').last}').readAsString());
     final id={'jalalayn':272,'tabari':4,'baghawi':2,'ibn_kathir_alt':331}[edition]!;
     final original=jsonDecode(utf8.decode(gzip.decode(File('/tmp/offline-corpus-preparation/tafsir-book-$id.json.gz').readAsBytesSync())));
     final rows=original['ayahs'] as List;
     for(final s in [1,2,35,40,104,114]){
       final candidates=rows.where((r)=>r['surah']==s).toList();if(candidates.isEmpty)continue;
       for(final r in [candidates.first,candidates.last]){
         final entry=await source.fetch(edition,s,r['ayah']);expect(entry,isNotNull);
         final pieces=r['content'] as List;expect(entry!.pages.length,pieces.length);
         for(var n=0;n<pieces.length;n++){expect(entry.pages[n].text,BundledTafsirSource.plain(pieces[n]['text']));expect(entry.pages[n].verseIds,pieces[n]['ayahs'].toString());}
         checked++;
       }
     }
   }
   expect(checked,greaterThan(30));
 });
}
