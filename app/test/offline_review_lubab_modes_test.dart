import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/services/lubab_source.dart';
class CountDeniedHttp implements HttpClientAdapter{
 int attempts=0;
 @override Future<ResponseBody> fetch(RequestOptions options,Stream<Uint8List>? stream,Future<dynamic>? cancel)async{attempts++;throw StateError('Network must remain unused');}
 @override void close({bool force=false}){}
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 const sample='قوله SYNTHETIC_FIXTURE_ONLY';
 late Map<String,dynamic> metadata,index;
 late String packed;
 late CountDeniedHttp adapter;
 late List<String> reads;
 setUp((){
  for(final path in ['assets/data/lubab_verse_index.json','assets/data/lubab_book_manifest.json','assets/data/lubab_book_1.b64']){rootBundle.evict(path);}
  final bytes=utf8.encode(jsonEncode({'contents':[{'id':1,'text':sample}]}));packed=base64Encode(GZipEncoder().encode(bytes));
  metadata={'bookId':69,'source':LubabSource.sourceUrl,'parts':1,'sha256':sha256.convert(bytes).toString(),'contentCount':1};
  index={'bookId':69,'provider':'quranpedia.net','linkType':'explicit_heading_quote','records':[{'surah':2,'ayah':3,'segments':[{'id':1,'from':0,'to':sample.runes.length}]}],'pages':[{'id':1,'page':1,'sha256':sha256.convert(utf8.encode(sample)).toString()}]};
  adapter=CountDeniedHttp();reads=[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(message)async{
   final path=utf8.decode(message!.buffer.asUint8List());reads.add(path);
   if(path.endsWith('lubab_verse_index.json'))return ByteData.sublistView(utf8.encode(jsonEncode(index)));
   if(path.endsWith('lubab_book_manifest.json'))return ByteData.sublistView(utf8.encode(jsonEncode(metadata)));
   if(path.endsWith('lubab_book_1.b64'))return ByteData.sublistView(utf8.encode(packed));
   return null;
  });
 });
 tearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
 LubabSource source()=>LubabSource(dio:Dio()..httpClientAdapter=adapter);
 test('default uses embedded source even with injected Dio and never calls HTTP',()async{
  final result=await source().fetch(2,3);expect(result.single.text,sample);expect(reads.any((p)=>p.endsWith('lubab_book_1.b64')),isTrue);expect(adapter.attempts,0);
 });
 test('embedded checksum mismatch fails closed without network fallback',()async{
  metadata['sha256']='wrong';await expectLater(source().fetch(2,3),throwsFormatException);expect(adapter.attempts,0);
 });
 test('index identity rejects before embedded source access',()async{
  index['bookId']=1;await expectLater(source().fetch(2,3),throwsFormatException);expect(reads.any((p)=>p.endsWith('lubab_book_manifest.json')),isFalse);expect(adapter.attempts,0);
 });
 test('embedded manifest source identity remains checked',()async{
  metadata['bookId']=1;await expectLater(source().fetch(2,3),throwsFormatException);expect(adapter.attempts,0);
 });
 test('embedded source span range remains checked',()async{
  index['records'][0]['segments'][0]['to']=999;await expectLater(source().fetch(2,3),throwsFormatException);expect(adapter.attempts,0);
 });
 test('missing indexed ayah never reads another source or opens network',()async{
  expect(await source().fetch(2,4),isEmpty);expect(reads.any((p)=>p.endsWith('lubab_book_manifest.json')),isFalse);expect(adapter.attempts,0);
 });
}
