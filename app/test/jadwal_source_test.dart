import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import '../lib/core/services/jadwal_source.dart';
class JadwalAdapter implements HttpClientAdapter {
  final Map<String,dynamic> content; final int author; int calls=0;
  JadwalAdapter(this.content,{this.author=1346});
  @override Future<ResponseBody> fetch(RequestOptions o,Stream<Uint8List>? s,Future<dynamic>? c)async{calls++;return ResponseBody.fromString(jsonEncode(o.uri.path=='/v1/book/1772'?{'id':1772,'author':{'id':author},'contents_url':JadwalSource.sourceUrl}:content),200,headers:{Headers.contentTypeHeader:['application/json']});}
  @override void close({bool force=false}){}
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async{final path=utf8.decode(m!.buffer.asUint8List());final f=File(path);return f.existsSync()?ByteData.sublistView(f.readAsBytesSync()):null;});
 const text='نص تجريبي\nعنوان الآية\nحاشية في آخر الصفحة';
 Map<String,dynamic> index()=>{'bookId':1772,'authorId':1346,'provider':'quranpedia.net','records':[{'surah':2,'ayahFrom':3,'ayahTo':4,'segments':[{'id':1,'from':10,'to':20}]}],'pages':[{'id':1,'part':1,'page':7,'sha256':sha256.convert(utf8.encode(text)).toString()}],'quarantine':[]};
 JadwalSource source({String value=text,int author=1346,Map<String,dynamic>? custom})=>JadwalSource(useBundled:false, storageDirectory:()async=>Directory('/tmp/jadwal-no-offline-in-transport-test'),dio:Dio()..httpClientAdapter=JadwalAdapter({'contents':[{'id':1,'text':value}]},author:author),loadIndex:()async=>custom??index());
 test('whole page keeps footnotes and shared range, with a source focus',()async{final e=(await source().fetch(2,3))!;expect(e.pages.single.text,text);expect(e.pages.single.focusOffset,10);expect(e.ayahTo,4);expect(e.notice,contains('مشترك'));});
 test('does not substitute adjacent verse',()async{expect(await source().fetch(2,5),isNull);});
 test('source changes fail closed',()async{await expectLater(()=>source(value:'changed').fetch(2,3),throwsFormatException);});
 test('author mismatch fails closed',()async{await expectLater(()=>source(author:3).fetch(2,3),throwsFormatException);});
 test('invalid source offset fails closed',()async{final i=index();i['records'][0]['segments'][0]['to']=999;await expectLater(()=>source(custom:i).fetch(2,3),throwsFormatException);});
 test('concurrent fetches share one on-demand content load',()async{final a=JadwalAdapter({'contents':[{'id':1,'text':text}]});final s=JadwalSource(useBundled:false, storageDirectory:()async=>Directory('/tmp/jadwal-no-offline-in-transport-test'),dio:Dio()..httpClientAdapter=a,loadIndex:()async=>index());await Future.wait([s.fetch(2,3),s.fetch(2,4)]);expect(a.calls,2);});
 test('private download survives new instance without network and deletes fully',()async{
   final dir=await Directory.systemTemp.createTemp('jadwal-private-');addTearDown(()=>dir.delete(recursive:true));
   final adapter=JadwalAdapter({'contents':[{'id':1,'text':text}]});
   JadwalSource fresh()=>JadwalSource(useBundled:false, storageDirectory:()async=>dir,dio:Dio()..httpClientAdapter=adapter,loadIndex:()async=>index());
   final first=fresh();await first.downloadForOffline();expect(adapter.calls,2);expect(await first.offlineSavedAt(),isNotNull);
   final second=fresh();expect((await second.fetch(2,3))!.pages.single.text,text);expect(adapter.calls,2);expect(await second.offlineSavedAt(),isNotNull);
   await second.deleteOffline();expect(await second.offlineSavedAt(),isNull);expect(await File('${dir.path}/jadwal/book-1772-v1.json').exists(),isFalse);
   await second.fetch(2,3);expect(adapter.calls,4);
 });
 test('corrupt private copy fails closed and can be removed',()async{
   final dir=await Directory.systemTemp.createTemp('jadwal-corrupt-');addTearDown(()=>dir.delete(recursive:true));
   final a=JadwalAdapter({'contents':[{'id':1,'text':text}]});
   JadwalSource fresh()=>JadwalSource(useBundled:false, storageDirectory:()async=>dir,dio:Dio()..httpClientAdapter=a,loadIndex:()async=>index());
   await fresh().downloadForOffline();final file=File('${dir.path}/jadwal/book-1772-v1.json');final envelope=jsonDecode(await file.readAsString());envelope['content']['contents'][0]['text']='bad';await file.writeAsString(jsonEncode(envelope));
   final s=fresh();await expectLater(()=>s.offlineSavedAt(),throwsFormatException);await expectLater(()=>s.fetch(2,3),throwsFormatException);expect(a.calls,2);await s.deleteOffline();await s.fetch(2,3);expect(a.calls,4);
 });
 test('refresh validates entire copy and preserves previous file on rejection',()async{
   final dir=await Directory.systemTemp.createTemp('jadwal-refresh-');addTearDown(()=>dir.delete(recursive:true));
   final content={'contents':[{'id':1,'text':text}]};final a=JadwalAdapter(content);
   final s=JadwalSource(useBundled:false, storageDirectory:()async=>dir,dio:Dio()..httpClientAdapter=a,loadIndex:()async=>index());
   await s.downloadForOffline();final file=File('${dir.path}/jadwal/book-1772-v1.json');final original=await file.readAsString();content['contents']![0]['text']='changed';
   await expectLater(()=>s.downloadForOffline(refresh:true),throwsFormatException);expect(await file.readAsString(),original);
 });
 test('bundled navigation decodes on demand without bundled source text',()async{final s=JadwalSource(useBundled:false, );expect(await s.fetch(999,1),isNull);});
 final path=Platform.environment['JADWAL_LOCAL_SOURCE'];
 if(path!=null){test('actual source all 6236 navigation points and reviewed exceptions',()async{final i=jsonDecode(File('/tmp/jadwal-preparation/jadwal_verse_index.json').readAsStringSync()) as Map<String,dynamic>;final content=jsonDecode(File(path).readAsStringSync()) as Map<String,dynamic>;final a=JadwalAdapter(content);final s=JadwalSource(useBundled:false, storageDirectory:()async=>Directory('/tmp/jadwal-no-offline-in-transport-test'),dio:Dio()..httpClientAdapter=a,loadIndex:()async=>i);var count=0;for(final r in i['records']){for(var v=r['ayahFrom'] as int;v<=r['ayahTo'];v++){expect((await s.fetch(r['surah'],v))!.pages,isNotEmpty);count++;}}expect(count,6236);expect(a.calls,2);for(final v in [3,4]){expect((await s.fetch(35,v))!.notice,contains('غير كامل'));}expect((await s.fetch(40,10))!.pages.single.page,226);expect((await s.fetch(40,9))!.pages.last.text,contains('حُجب'));expect((await s.fetch(40,9))!.pages.last.text, isNot(contains('يَأْكُلُونَ أَمْوالَ الْيَتامى')));expect((await s.fetch(114,6))!.pages.map((p)=>p.page),[429,430]);print('6236 navigation points verified, not a claim of complete source text');},timeout:const Timeout(Duration(minutes:3)));}
}
