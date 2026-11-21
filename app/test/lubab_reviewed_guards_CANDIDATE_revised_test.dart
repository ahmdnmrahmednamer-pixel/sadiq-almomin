import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/lubab_source.dart';
class LubabAdapter implements HttpClientAdapter {
 final Map<String,dynamic> content;
 final int author;
 LubabAdapter(this.content,{this.author=14264});
 @override Future<ResponseBody> fetch(RequestOptions o,Stream<Uint8List>? s,Future<dynamic>? c)async=>ResponseBody.fromString(jsonEncode(o.uri.path=='/v1/book/69'?{'id':69,'type':'asbab','author':{'id':author}}:content),200,headers:{Headers.contentTypeHeader:['application/json']});
 @override void close({bool force=false}){}
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('all bundled indexed locations load without network and keep source pages',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async{final p=utf8.decode(m!.buffer.asUint8List());return ByteData.sublistView(await File(p).readAsBytes());});
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final index=jsonDecode(await File('assets/data/lubab_verse_index.json').readAsString());
  final source=LubabSource(dio:Dio()..httpClientAdapter=LubabAdapter({'contents':[]},author:1));
  var count=0;
  for(final r in index['records']){final entries=await source.fetch(r['surah'],r['ayah']);expect(entries,isNotEmpty);if(r['boundaryKind']=='reviewed_narration'){expect(entries.any((e)=>sha256.convert(utf8.encode(e.text)).toString()==r['spanSha256']),isTrue);}else{expect(entries.any((e)=>e.text.startsWith('قوله')),isTrue);}count++;}
  expect(count,greaterThan(0));
 });

 test('reviewed headings retain interior quotations and do not invent a new title',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async{final p=utf8.decode(m!.buffer.asUint8List());return ByteData.sublistView(await File(p).readAsBytes());});
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource(dio:Dio()..httpClientAdapter=LubabAdapter({'contents':[]},author:1));
  final hijr=await source.fetch(15,45);expect(hijr.single.text,startsWith('قوله تعالى إن المتقين'));expect(hijr.single.text,contains('لما سمع قوله تعالى'));expect(hijr.single.text,contains('إن المتقين في جنات وعيون'));
  {final c=await source.fetch(15,43);expect(c.length,1);expect(c.single.contextNote,isNotNull);expect(c.single.text,(await source.fetch(15,45)).single.text);}{final c=(await source.fetch(15,43)).single.text;expect(c,contains('سلمان الفارسي'));expect(c,contains('وإن جهنم لموعدهم أجمعين'));}/* grounded in printed-edition witness witness-15-43.pdf (sha dfabc18f...), read by hand *//* UPDATED: 15:43 is now a later, labelled prior-quotation context (reviewNote), no longer empty; it must carry the index note and share the 15:45 source entry */expect((await source.fetch(39,9)).length,1);expect((await source.fetch(74,7)).single.text,(await source.fetch(74,1)).single.text);
  for(final pair in [(2,26),(2,158),(4,33),(5,41),(9,58),(9,79),(17,56),(49,1)]){expect(await source.fetch(pair.$1,pair.$2),isNotEmpty);}
  expect(await source.fetch(22,3),isNotEmpty);expect(await source.fetch(22,8),isEmpty);
  expect((await source.fetch(4,69)).single.text,contains('والرسول'));
 });

 test('reviewed independent witnesses and unheaded narrations retain exact boundaries',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource(dio:Dio()..httpClientAdapter=LubabAdapter({'contents':[]},author:1));
  for(final pair in [(2,14),(2,190),(2,240),(4,48),(4,69),(5,2),(5,15),(22,3),(33,28),(40,4),(40,56),(40,57),(40,66),(74,1),(74,2),(74,7),(74,11),(74,30),(74,31),(74,52)]){expect(await source.fetch(pair.$1,pair.$2),isNotEmpty);}
  for(final pair in [(2,244),(22,8)]){expect(await source.fetch(pair.$1,pair.$2),isEmpty);}
  final g56=(await source.fetch(40,56)).single.text;expect((await source.fetch(40,57)).single.text,g56);expect((await source.fetch(40,66)).single.text,isNot(g56));
  final first=(await source.fetch(74,1)).single.text;for(var n=2;n<=7;n++){expect((await source.fetch(74,n)).single.text,first);}
  for(final n in [11,31,52]){expect((await source.fetch(74,n)).single.text,isNot(first));}
  {final e=await source.fetch(74,30);expect(e.length,greaterThan(1));expect(e.every((x)=>x.text!=first),isTrue);expect(e.any((x)=>x.contextNote!=null),isTrue);}{final e=(await source.fetch(74,30)).map((x)=>x.text).toList();expect(e.length,4);expect(e.where((t)=>t.contains('عن البراء')).length,1);expect(e.where((t)=>t.contains('أبا الأشد')).length,1);expect(e.where((t)=>t.contains('ثكلتكم')||t.contains('أبو جهل')).length,greaterThanOrEqualTo(2));expect(e.where((t)=>t.contains('عن ابن إسحق')).length,1);expect(e.where((t)=>t.contains('عليها تسعة عشر')).length,3);}/* 2026-11-21 auditor correction 7ddb545a: printed Kunuz scan p.280 shows a fourth in-section narration (Ibn Ishaq, footnoted to 31); it does not contain the literal phrase, so the old every-entry-contains assertion was a count artifact, not source authority *//* grounded by reading source spans 101967[458:625], 101967[877:1091], 101968[153:436] of the chapter whose sha equals the manifest value; no separate witness file retained for 74:30 *//* UPDATED: 74:30 gained a labelled later-context entry; the old 'single' assertion became 'no entry may equal the 74:1 narration, at least one carries the index note' */
 });

 test('reviewed ranges use actual Quran endpoints, not remembered verse offsets',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource(dio:Dio()..httpClientAdapter=LubabAdapter({'contents':[]},author:1));
  expect(await source.fetch(56,38),isEmpty);expect(await source.fetch(56,39),isNotEmpty);expect((await source.fetch(56,40)).single.text,(await source.fetch(56,39)).single.text);
  for(final pair in [(49,1),(49,2),(49,3),(49,4),(49,5),(49,6),(49,7),(49,8),(53,32),(57,28),(64,16),(73,20),(80,17),(112,4),(114,6)]){expect(await source.fetch(pair.$1,pair.$2),isNotEmpty);}
 });

 test('older headings cannot swallow distinct later reports or explicit endpoints',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource();
  final b120=(await source.fetch(2,120)).single;
  final b125=(await source.fetch(2,125)).first;
  expect((await source.fetch(2,125)).length,2);
  expect(b120.text,contains('ولن ترضى'));
  expect(b120.text,isNot(contains('مقام إبراهيم')));
  expect(b125.text,contains('مقام إبراهيم'));
  expect(b125.text,isNot(contains('ولن ترضى')));
  final b108=await source.fetch(2,108);expect(b108.length,2);
  expect(b108.map((e)=>e.text).join(),isNot(contains('وكان حيي بن أخطب')));
  expect((await source.fetch(2,109)).single.text,startsWith('وكان حيي بن أخطب'));
  expect((await source.fetch(2,99)).single.text,isNot(contains('وقال مالك بن الصيف')));
  expect((await source.fetch(2,100)).single.text,startsWith('وقال مالك بن الصيف'));
  expect((await source.fetch(2,150)).single.text,startsWith('وأخرج ابن جرير من طريق السدي'));
  expect((await source.fetch(2,143)).length,2);
  expect((await source.fetch(2,144)).any((e)=>e.contextNote?.contains('142 و143 و144')??false),isTrue);
  expect((await source.fetch(2,27)).single.contextNote,contains('الرقم الوارد'));
  expect((await source.fetch(2,190)).single.text,isNot(contains('الشهر الحرام بالشهر الحرام')));
  expect((await source.fetch(2,194)).single.text,contains('الشهر الحرام بالشهر الحرام'));
  expect((await source.fetch(2,200)).length,2);
  expect((await source.fetch(2,202)).single.text,contains('والله سريع الحساب'));
  expect((await source.fetch(2,202)).single.contextNote,contains('نهاية الاقتباس من الآية 202'));
  expect((await source.fetch(2,218)).single.text,(await source.fetch(2,217)).single.text);
  expect((await source.fetch(2,279)).single.text,(await source.fetch(2,278)).single.text);
  expect((await source.fetch(2,284)).single.text,(await source.fetch(2,286)).single.text);
  expect((await source.fetch(2,286)).single.contextNote,contains('ثم يروي نزول الآيتين 285 و286'));
  for(final n in [20,27,81,82,98,100,109,125,143,144,150,194,201,202,218,279,284,286]){expect(await source.fetch(2,n),isNotEmpty);}
 });

 test('AlImran explicit ends and individual Najran reports keep their own scope',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource();
  final a58=(await source.fetch(3,58)).where((e)=>e.text.startsWith('قوله تعالى ذلك نتلوه')).single;
  expect(a58.text,isNot(contains('وأخرج ابن سعد')));
  expect(a58.contextNote,contains('58 إلى 60'));
  final a62=(await source.fetch(3,62)).where((e)=>e.text.startsWith('وأخرج ابن سعد')).single;
  expect(a62.contextNote,contains('59 إلى 62'));
  expect(a62.text,contains('وإن الله لهو العزيز الحكيم'));
  expect((await source.fetch(3,73)).any((e)=>e.text.startsWith('(ك) وأخرج ابن أبي حاتم عن السدي')),isTrue);
  expect((await source.fetch(3,89)).single.contextNote,contains('86 إلى 89'));
  expect((await source.fetch(3,103)).single.contextNote,contains('عنوان المصدر من الآية 100'));
  expect((await source.fetch(3,99)).single.text,startsWith('وأخرج ابن إسحق وأبو الشيخ'));
  expect((await source.fetch(3,115)).single.text,startsWith('وأخرج أحمد وغيره عن ابن مسعود'));
  expect((await source.fetch(3,124)).single.text,startsWith('وأخرج ابن أبي شبية في المصنف'));
  final uhud=(await source.fetch(3,121)).single;
  expect(uhud.contextNote,contains('لا مدى متصل'));
  expect(uhud.text,isNot(contains('وأخرج الشيخان عن جابر')));
  expect((await source.fetch(3,154)).any((e)=>e.text==uhud.text),isTrue);
  expect((await source.fetch(3,173)).length,2);
  expect((await source.fetch(3,174)).single.contextNote,contains('172، 174'));

 });

 test('Nisa inheritance, marriage and cross-surah reports never inherit an earlier heading',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource();
  final e11=await source.fetch(4,11);expect(e11.length,2);
  expect(e11.first.text,contains('قال الحافظ ابن حجر'));
  expect(e11.every((e)=>!e.text.contains('وجه آخر فأخرج القاضي')),isTrue);
  expect((await source.fetch(4,12)).map((e)=>e.text).toList(),e11.map((e)=>e.text).toList());
  expect((await source.fetch(4,127)).any((e)=>e.text.startsWith('(ك) وقد ورد في قصة سعد بن الربيع')),isTrue);
  final e19=await source.fetch(4,19);expect(e19.length,3);
  expect(e19.every((e)=>!e.text.contains('وحلائل أبنائكم')),isTrue);
  final e23=(await source.fetch(4,23)).single;
  expect(e23.text,contains('وحلائل أبنائكم الذين من أصلابكم'));
  expect(e23.contextNote,contains('النساء 23 والأحزاب 4 و40'));
  for(final n in [4,40]){expect((await source.fetch(33,n)).any((e)=>e.text==e23.text),isTrue);}
  final e66=(await source.fetch(4,66)).single;
  expect(e66.text,startsWith('(ك) وأخرج ابن جرير عن السدي'));
  final e65=(await source.fetch(4,65)).single;
  expect(e65.text,isNot(contains('افتخر ثابت بن قيس')));
  expect(e65.text,contains('مرسل غريب في إسناده ابن لهيعة'));
  expect((await source.fetch(4,39)).single.text,contains('وكان بهم عليما'));
  expect((await source.fetch(4,54)).length,2);
  expect((await source.fetch(4,62)).single.contextNote,contains('60 إلى 62'));
  expect((await source.fetch(108,3)).any((e)=>e.contextNote?.contains('النساء 51 إلى 52 والكوثر 3')??false),isTrue);
  expect((await source.fetch(20,114)).any((e)=>e.contextNote?.contains('النساء 34')??false),isTrue);
  expect((await source.fetch(4,97)).length,3);
  final migration=(await source.fetch(4,97)).last;
  expect(migration.contextNote,contains('العنكبوت 10 والنحل 110'));
  for(final pair in [(29,10),(16,110)]){expect((await source.fetch(pair.$1,pair.$2)).any((e)=>e.text==migration.text),isTrue);}
  expect((await source.fetch(4,101)).length,1);
  expect((await source.fetch(4,102)).length,3);
  expect((await source.fetch(4,113)).single.contextNote,contains('لا يُفترض من ذلك ربط الآية 114'));
  expect((await source.fetch(4,115)).length,2);
  expect((await source.fetch(4,116)).single.contextNote,contains('105 إلى 113'));
  final n116=(await source.fetch(4,116)).single.text;
  expect((await source.fetch(4,48)).every((e)=>e.text!=n116),isTrue);
  final works=(await source.fetch(4,124)).single;
  expect((await source.fetch(4,123)).any((e)=>e.text==works.text),isTrue);
  expect((await source.fetch(4,156)).single.contextNote,contains('الأنعام 91'));
  expect((await source.fetch(6,91)).any((e)=>e.contextNote?.contains('النساء 153 إلى 156')??false),isTrue);
  final e32=(await source.fetch(4,32)).first;
  expect((await source.fetch(33,35)).any((e)=>e.text==e32.text),isTrue);
 });

 test('Maida later reports and explicit ends retain separate verse scopes',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource();
  expect((await source.fetch(5,19)).single.text,isNot((await source.fetch(5,15)).single.text));
  expect((await source.fetch(5,18)).single.text,isNot((await source.fetch(5,19)).single.text));
  expect((await source.fetch(5,39)).single.contextNote,contains('آية الرواية'));
  expect((await source.fetch(5,41)).length,2);
  expect((await source.fetch(5,42)).length,2);
  expect((await source.fetch(5,42)).last.text,startsWith('(ك)'));
  expect((await source.fetch(5,45)).single.contextNote,contains('41 إلى 45'));
  expect((await source.fetch(5,50)).single.contextNote,contains('49 إلى 50'));
  expect((await source.fetch(5,6)).single.contextNote,contains('الخلاف وتعليله محفوظان'));
  expect((await source.fetch(5,61)).single.contextNote,contains('57 إلى 61'));
  expect((await source.fetch(5,83)).length,2);
  expect((await source.fetch(5,93)).length,2);
  expect((await source.fetch(5,91)).single.contextNote,contains('ليست الآية 92'));
  final deferred=await source.fetch(2,219);
  expect(deferred.any((e)=>e.contextNote?.contains('تسلسل مشترك')??false),isTrue);
  expect(deferred.where((e)=>e.contextNote?.contains('تسلسل مشترك')??false).single.text.length,greaterThan(600));
  expect((await source.fetch(5,108)).single.contextNote,contains('106 إلى 108'));

 });

 test('Anam report partitions preserve the critical note and cross-surah context',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource();
  expect((await source.fetch(6,52)).length,4);
  expect((await source.fetch(6,54)).length,3);
  final cross=(await source.fetch(6,52)).where((e)=>e.contextNote?.contains('تعقيب ابن كثير')??false).single;
  expect(cross.text.length,greaterThan(650));
  expect((await source.fetch(18,28)).any((e)=>e.text==cross.text),isTrue);
  expect((await source.fetch(6,67)).single.contextNote,contains('66 و67'));
  expect((await source.fetch(6,111)).single.contextNote,contains('109 إلى 111'));
  expect((await source.fetch(6,121)).length,2);
  expect((await source.fetch(6,118)).single.text,isNot((await source.fetch(6,121)).last.text));
 });

 test('Araf and Anfal scope stays explicit and unresolved quotations stay labelled',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource();
  expect((await source.fetch(7,33)).single.contextNote,contains('32 و33'));
  expect((await source.fetch(8,32)).length,4);
  expect((await source.fetch(8,33)).length,4);
  expect((await source.fetch(8,34)).length,2);
  expect((await source.fetch(8,34)).last.text,startsWith('(ك)'));
  final shared=(await source.fetch(8,49)).single;
  for(final pair in [(8,48),(8,17),(14,28),(23,64),(54,45)]){expect((await source.fetch(pair.$1,pair.$2)).any((e)=>e.text==shared.text),isTrue);}
  expect((await source.fetch(8,65)).single.contextNote,contains('تعارض في المصدر لم يُحسم'));
  expect(await source.fetch(8,66),isEmpty);
  expect((await source.fetch(8,67)).length,2);
  expect((await source.fetch(8,68)).length,2);
 });

 test('Tawba headers do not absorb distinct verses or unbounded story endings',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource();
  expect((await source.fetch(9,17)).single.contextNote,contains('تصرحان'));
  expect((await source.fetch(9,19)).length,3);
  expect((await source.fetch(9,24)).single.contextNote,contains('19، 24'));
  expect((await source.fetch(9,38)).single.contextNote,contains('39 و40'));
  expect((await source.fetch(9,66)).single.text,isNot((await source.fetch(9,65)).first.text));
  expect((await source.fetch(9,77)).single.contextNote,contains('بسند ضعيف'));
  final hard=(await source.fetch(9,91)).single.text;
  expect((await source.fetch(9,92)).every((e)=>e.text!=hard),isTrue);
  expect((await source.fetch(9,106)).single.contextNote,contains('102، 106، 118'));
  expect((await source.fetch(9,108)).single.text,isNot((await source.fetch(9,107)).single.text));
  expect((await source.fetch(9,107)).single.contextNote,contains('بلا نهاية محددة'));
  final e=(await source.fetch(9,113)).single;
  expect((await source.fetch(28,56)).any((z)=>z.text==e.text),isTrue);
  expect((await source.fetch(9,119)).single.contextNote,contains('117 إلى 119'));
 });

 test('Yunus through Nahl explicit contexts do not inherit previous headings',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource();
  final yunus=(await source.fetch(10,2)).single;
  for(final pair in [(12,109),(43,31),(43,32)]){expect((await source.fetch(pair.$1,pair.$2)).any((e)=>e.text==yunus.text),isTrue);}
  expect((await source.fetch(15,50)).single.contextNote,contains('49 إلى 50'));
  expect((await source.fetch(16,42)).single.contextNote,contains('41 إلى 42'));
  expect((await source.fetch(16,76)).single.text,startsWith('وفي قوله'));
  expect((await source.fetch(16,75)).single.text,isNot(contains('عثمان')));
  expect((await source.fetch(16,106)).single.text,isNot(contains('وأخرج ابن سعد في الطبقات')));
  expect((await source.fetch(16,110)).any((e)=>e.text.startsWith('وأخرج ابن سعد في الطبقات')),isTrue);
  expect((await source.fetch(16,128)).single.contextNote,contains('اختلاف زمن النزول'));
  final source73=(await source.fetch(17,73)).single;
  expect(source73.contextNote,contains('لا تصحيح لتلك الروايات'));
  expect(source73.text,contains('وإسناده ضعيف'));
  expect((await source.fetch(22,52)).any((e)=>e.text==source73.text),isTrue);
  expect((await source.fetch(17,80)).any((e)=>e.contextNote?.contains('ليس مدى متصلًا')??false),isTrue);
  expect((await source.fetch(17,93)).single.contextNote,contains('90 إلى 93'));

 });

 test('Kahf deferral includes the full original report and Hajj endpoints stay local',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource();
  final kahf=await source.fetch(18,28);
  expect(kahf.length,3);
  expect(kahf.any((e)=>e.contextNote?.contains('تعقيب ابن كثير')??false),isTrue);
  final spirit=(await source.fetch(18,109)).single;
  expect((await source.fetch(17,85)).any((e)=>e.text==spirit.text),isTrue);
  expect((await source.fetch(22,19)).length,3);
  expect((await source.fetch(22,22)).single.text,startsWith('وأخرج الحاكم عن علي'));
  expect((await source.fetch(22,22)).single.contextNote,contains('19 إلى 22'));
 });

 test('Nur complete Ifk narration remains whole without swallowing later reports',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource();
  expect((await source.fetch(24,9)).single.contextNote,contains('6 إلى 9'));
  final ifk=(await source.fetch(24,11)).single;
  expect(ifk.text.length,greaterThan(4000));
  expect(ifk.contextNote,contains('لا تُضاف الآية 21'));
  expect(ifk.text,isNot(contains('قلت لسعيد بن جبير')));
  expect((await source.fetch(24,22)).any((e)=>e.text==ifk.text),isTrue);
  expect((await source.fetch(24,26)).length,3);
  expect((await source.fetch(24,21)).length,0);
  expect((await source.fetch(24,26)).last.contextNote,contains('لم تُستنتج البداية بالحساب'));
  expect((await source.fetch(24,26)).every((e)=>e.text!=ifk.text),isTrue);
  expect((await source.fetch(24,29)).single.text,isNot((await source.fetch(24,27)).single.text));
  expect((await source.fetch(24,64)).single.contextNote,contains('62 إلى 64'));
 });

 test('Ahzab mixed headings partition by report and Qasas deferral is inline',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource();
  final qasas=await source.fetch(28,52);
  expect(qasas.any((e)=>e.text.length>500),isTrue);
  expect((await source.fetch(28,54)).single.text.length,greaterThan(250));
  expect((await source.fetch(33,12)).single.text.length,greaterThan(900));
  expect((await source.fetch(33,13)).length,2);
  expect((await source.fetch(33,10)),isEmpty);
  final forty=await source.fetch(33,40);
  expect(forty.any((e)=>e.text.length<150),isTrue);
  expect((await source.fetch(33,37)).length,2);
  expect((await source.fetch(33,53)).any((e)=>e.contextNote?.contains('37')??false),isTrue);
  expect((await source.fetch(33,56)).single.contextNote,contains('بعد السؤال'));
  expect((await source.fetch(48,5)).any((e)=>e.contextNote?.contains('الأحزاب 47')??false),isTrue);
  expect((await source.fetch(33,51)).length,2);
 });

 test('Zumar later reports and explicitly deferred reports open at their own ayahs',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource();
  expect((await source.fetch(39,18)).single.contextNote,contains('17 و18'));
  expect((await source.fetch(39,67)).length,2);
  expect((await source.fetch(39,67)).first.contextNote,contains('التلاوة والنزول'));
  expect((await source.fetch(39,66)).single.text.length,lessThan(250));
  expect((await source.fetch(39,64)).length,2);
  expect((await source.fetch(4,48)).any((e)=>e.contextNote?.contains('بالضعف')??false),isTrue);
  final umar=(await source.fetch(2,125)).first;
  expect((await source.fetch(66,5)).any((e)=>e.text==umar.text),isTrue);
  expect((await source.fetch(33,53)).any((e)=>e.text==umar.text),isTrue);
  expect((await source.fetch(44,44)).any((e)=>e.contextNote?.contains('الإسراء 60')??false),isTrue);
 });

 test('named deferrals return actual full reports with distinct topic notes',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource();
  expect((await source.fetch(33,35)).any((e)=>e.contextNote?.contains('ليس اقتباسًا')??false),isTrue);
  for(final target in [(18,28),(20,114),(28,52),(29,10),(33,53),(39,23),(39,53),(39,64),(43,31),(66,5)]){
   final entries=await source.fetch(target.$1,target.$2);
   expect(entries.where((e)=>e.text.length>200),isNotEmpty,reason:'${target.$1}:${target.$2}');
  }
 });

 test('Baqara subsidiary references keep weak chains and noncontiguous scopes',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource();
  expect((await source.fetch(2,115)).length,5);
  final qibla=(await source.fetch(2,115))[1];
  expect(qibla.contextNote,contains('لا تشمل الآية 143'));
  expect((await source.fetch(2,143)).every((e)=>e.text!=qibla.text),isTrue);
  expect((await source.fetch(3,199)).any((e)=>e.contextNote?.contains('الإعضال')??false),isTrue);
  expect((await source.fetch(2,174)).length,2);
  expect((await source.fetch(3,77)).any((e)=>e.contextNote?.contains('174')??false),isTrue);
  expect((await source.fetch(40,60)).length,2);
  expect((await source.fetch(4,10)).any((e)=>e.contextNote?.contains('لم يعيّن')??false),isTrue);
  expect((await source.fetch(2,236)).any((e)=>e.contextNote?.contains('241')??false),isTrue);
  expect((await source.fetch(2,261)).any((e)=>e.contextNote?.contains('ترتيب الرواية')??false),isTrue);
 });

 test('later cited contexts preserve report bounds and do not fill intervening ayahs',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource();
  expect((await source.fetch(2,164)).length,2);
  expect((await source.fetch(2,163)).single.contextNote,contains('ليستا سببًا خاصًا'));
  final migration=(await source.fetch(4,100))[1];
  expect(migration.contextNote,contains('لا تضيف الآية 99'));
  expect((await source.fetch(4,99)).every((e)=>e.text!=migration.text),isTrue);
  expect((await source.fetch(16,90)).any((e)=>e.contextNote?.contains('ضعف الإسناد')??false),isTrue);
  expect((await source.fetch(16,81)).single.contextNote,contains('لا تضاف الآية 82'));
  expect((await source.fetch(16,82)).isEmpty,isTrue);
  expect((await source.fetch(4,29)).any((e)=>e.contextNote?.contains('النور 61')??false),isTrue);
  expect((await source.fetch(24,61)).length,4);
  expect((await source.fetch(9,80)).any((e)=>e.contextNote?.contains('المنافقون 6')??false),isTrue);
  expect((await source.fetch(58,12)).any((e)=>e.contextNote?.contains('وصف الترمذي')??false),isTrue);
  expect((await source.fetch(61,10)).any((e)=>e.contextNote?.contains('نزول 11')??false),isTrue);
  expect((await source.fetch(8,32)).any((e)=>e.contextNote?.contains('المعارج 1')??false),isTrue);
  expect((await source.fetch(21,98)).single.contextNote,contains('لا سبب خاص'));
  expect((await source.fetch(25,68)).any((e)=>e.contextNote?.contains('لا سبب خاص')??false),isTrue);
 });

 test('long shared reports retain criticism and chain references without broad inferred ranges',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource();
  expect((await source.fetch(2,136)).single.contextNote,contains('إحالة إسنادية'));
  expect((await source.fetch(3,84)).isEmpty,isTrue);
  final lian=(await source.fetch(24,4)).single;
  expect(lian.text.length,greaterThan(2600));
  expect(lian.text,contains('قال الحافظ ابن حجر'));
  expect(lian.contextNote,contains('لا تضاف الآية 5'));
  expect((await source.fetch(24,5)).isEmpty,isTrue);
  expect((await source.fetch(31,27)).length,3);
  expect((await source.fetch(17,85)).any((e)=>e.text.contains('نزلت بمكة')),isTrue);
  expect((await source.fetch(17,85)).every((e)=>!e.text.contains('يوشك أن ينفذ')),isTrue);
  expect((await source.fetch(63,7)).single.text,(await source.fetch(63,8)).first.text);
  expect((await source.fetch(63,8)).length,2);
  expect((await source.fetch(9,74)).length,3);
  final sf=await source.fetch(61,2);expect(sf.length,3);
  expect(sf.map((e)=>e.text).toSet().length,3);
  expect(sf[1].text,isNot(contains(sf[2].text)));
  expect(sf[2].text,isNot(contains(sf[1].text)));
 });

 test('shorter quotes distinguish explicit prior context and repeated formulas',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource();
  expect((await source.fetch(3,181)).last.contextNote,contains('بالتخمين'));
  expect((await source.fetch(9,92)).any((e)=>e.contextNote?.contains('بني مقرن')??false),isTrue);
  expect((await source.fetch(41,5)).single.contextNote,contains('لم يُستنتج مدى'));
  expect((await source.fetch(23,12)).single.contextNote,contains('لا تضيف 13'));
  expect((await source.fetch(23,13)),isEmpty);
  expect((await source.fetch(2,269)).single.contextNote,contains('استشهاد'));
  expect((await source.fetch(44,10)).single.text,(await source.fetch(44,15)).single.text);
  expect((await source.fetch(44,16)).single.text,(await source.fetch(44,10)).single.text);
  expect((await source.fetch(44,11)),isEmpty);
  expect((await source.fetch(81,28)).single.text,(await source.fetch(81,29)).single.text);
  expect((await source.fetch(76,30)),isEmpty);
  expect((await source.fetch(25,7)).single.contextNote,contains('لا سبب خاص'));
  expect((await source.fetch(25,7)).single.text,(await source.fetch(25,20)).single.text);
 });

 test('one selected ayah never repeats overlapping raw source spans',()async{
  final index=jsonDecode(await File('assets/data/lubab_verse_index.json').readAsString());
  final byTarget=<String,List<Map<String,dynamic>>>{};
  for(final raw in index['records'] as List){
   final row=Map<String,dynamic>.from(raw as Map);
   (byTarget['${row['surah']}:${row['ayah']}']??=[]).add(row);
  }
  for(final group in byTarget.entries){
   final rows=group.value;
   for(var i=0;i<rows.length;i++){
    for(var j=i+1;j<rows.length;j++){
     for(final a in rows[i]['segments'] as List){
      for(final b in rows[j]['segments'] as List){
       if(a['id']!=b['id'])continue;
       final overlaps=(a['from'] as int)<(b['to'] as int)&&(b['from'] as int)<(a['to'] as int);
       expect(overlaps,isFalse,reason:'Repeated source at ${group.key}, records $i/$j');
      }
     }
    }
   }
  }
 });

 test('shared context labels stay outside the original narration',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource();final entries=await source.fetch(49,3);
  expect(entries.length,2);
  expect(entries.first.contextNote,contains('1 إلى 5'));
  expect(entries.first.contextNote,contains('ليس محصورًا'));
  expect(entries.last.contextNote,contains('الآيتين 2 و3'));
  expect((await source.fetch(49,2)).any((e)=>e.text==entries.last.text),isTrue);
  expect(entries.last.text,startsWith('(ك) وأخرج أيضا عن محمد بن ثابت'));
  expect(entries.last.text,contains('فأنزل الله إن الذين يغضون أصواتهم'));
  for(final e in entries){expect(e.text, isNot(contains('تنبيه الفهرس')));expect(e.annotatedText,contains('تنبيه الفهرس'));}
  expect((await source.fetch(3,80)).any((e)=>e.contextNote?.contains('1 إلى 80')??false),isTrue);
  expect((await source.fetch(3,80)).any((e)=>e.contextNote?.contains('79 إلى 80')??false),isTrue);
 });

 test('chapter context is explicit opt-in and never an unknown-verse fallback',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null));
  final source=LubabSource(dio:Dio()..httpClientAdapter=LubabAdapter({'contents':[]},author:1));
  expect(await source.fetch(94,1),isEmpty);final chapter=await source.fetchChapterContext(112);expect(chapter.single.text,startsWith('سورة الإخلاص'));expect(chapter.single.text,contains('قل هو الله أحد'));
  expect(await source.fetchChapterContext(1),isEmpty);
  final intro=await source.fetchFrontmatter();expect(intro,isNotEmpty);expect(intro.single.pages,[3,4,5,6]);expect(intro.single.text,contains('تنبيهات'));
  expect((await source.fetchChapterContext(113)).single.text,(await source.fetchChapterContext(114)).single.text);
  final index=jsonDecode(await File('assets/data/lubab_verse_index.json').readAsString());expect(index['pages'].length,218);
  for(final s in (index['chapterContexts']as Map).keys){expect(await source.fetchChapterContext(int.parse(s)),isNotEmpty);}
 });
 const text='قوله تعالى لفظ تجريبي SOURCE\nتتمة وحاشية محفوظتان';
 Map<String,dynamic> index()=>{'bookId':69,'provider':'quranpedia.net','linkType':'explicit_heading_quote','records':[{'surah':2,'ayah':3,'segments':[{'id':1,'from':0,'to':text.runes.length}]}],'pages':[{'id':1,'page':7,'sha256':sha256.convert(utf8.encode(text)).toString()}]};
 LubabSource source({String value=text,int author=14264,Map<String,dynamic>? custom})=>LubabSource(useBundled:false,dio:Dio()..httpClientAdapter=LubabAdapter({'contents':[{'id':1,'text':value}]},author:author),loadIndex:()async=>custom??index());
 test('returns verbatim source entry with notes and printed page',()async{final p=await source().fetch(2,3);expect(p.single.text,text);expect(p.single.pages,[7]);});
 test('does not reuse adjacent verse or return unindexed content',()async{expect(await source().fetch(2,4),isEmpty);});
 test('fails closed on source correction rather than using stale offsets',()async{expect(()=>source(value:'changed').fetch(2,3),throwsFormatException);});
 test('rejects a different author even with same title',()async{expect(()=>source(author:1).fetch(2,3),throwsFormatException);});
 test('rejects invalid span',()async{final i=index();i['records'][0]['segments'][0]['to']=999;expect(()=>source(custom:i).fetch(2,3),throwsFormatException);});
 test('unheaded narration requires an exact reviewed span checksum',()async{
  const value='REVIEWED_NARRATION_WITH_NOTE';final valid=index();valid['pages'][0]['sha256']=sha256.convert(utf8.encode(value)).toString();final record=valid['records'][0];record['segments'][0]['to']=value.length;record['boundaryKind']='reviewed_narration';record['spanSha256']=sha256.convert(utf8.encode(value)).toString();
  expect((await source(value:value,custom:valid).fetch(2,3)).single.text,value);
  record['spanSha256']='changed';expect(()=>source(value:value,custom:valid).fetch(2,3),throwsFormatException);
  record.remove('boundaryKind');record['spanSha256']=sha256.convert(utf8.encode(value)).toString();expect(()=>source(value:value,custom:valid).fetch(2,3),throwsFormatException);
 });
 test('HTML line and paragraph boundaries remain visible',(){expect(LubabSource.plain('<p>one</p>two<br />three'),'\none\ntwo\nthree');});
}
