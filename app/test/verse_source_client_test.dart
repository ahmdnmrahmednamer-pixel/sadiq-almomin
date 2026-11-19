import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/verse_source_client.dart';
class FixtureAdapter implements HttpClientAdapter {
  final Map<String,dynamic> data;
  FixtureAdapter(this.data);
  @override Future<ResponseBody> fetch(RequestOptions o,Stream<Uint8List>? s,Future<dynamic>? c)async => ResponseBody.fromString(jsonEncode({'code':200,'data':data}),200,headers:{Headers.contentTypeHeader:['application/json']});
  @override void close({bool force=false}){}
}
void main(){
 Map<String,dynamic> response()=>{'surah':{'number':2},'numberInSurah':255,'edition':{'identifier':'ar.qurtubi','type':'tafsir'},'text':'SOURCE_FIXTURE\nunchanged'};
 AlQuranCloudTafsirClient client(Map<String,dynamic> d)=>AlQuranCloudTafsirClient(dio:Dio(BaseOptions(baseUrl:'https://api.alquran.cloud/v1'))..httpClientAdapter=FixtureAdapter(d));
 test('preserves source text and exact identity without generated additions',()async{
  final s=await client(response()).fetch(editionId:'ar.qurtubi',surah:2,ayah:255);
  expect(s.text,'SOURCE_FIXTURE\nunchanged');expect(s.bookId,'ar.qurtubi');expect(s.contains(2,255),isTrue);expect(s.contains(2,254),isFalse);expect(s.sourceUrl,'https://api.alquran.cloud/v1/ayah/2:255/ar.qurtubi');
 });
 for(final fault in ['edition','surah','ayah','empty','type'])test('rejects $fault mismatch',()async{
  final d=response();if(fault=='edition')d['edition']={'identifier':'ar.muyassar','type':'tafsir'};
  if(fault=='surah')d['surah']={'number':1};if(fault=='ayah')d['numberInSurah']=254;
  if(fault=='empty')d['text']=' ';if(fault=='type')d['edition']={'identifier':'ar.qurtubi','type':'quran'};
  expect(()=>client(d).fetch(editionId:'ar.qurtubi',surah:2,ayah:255),throwsFormatException);
 });
 test('range retains shared source scope, never copies it as a single verse',(){
  const s=VerseSourceText(providerId:'fixture',bookId:'b',text:'SOURCE',sourceUrl:'https://example.org',surah:2,firstAyah:10,lastAyah:14);
  expect(s.contains(2,11),isTrue);expect(s.contains(3,11),isFalse);expect(s.contains(2,15),isFalse);
 });
}
