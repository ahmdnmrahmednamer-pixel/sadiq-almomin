import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/settings_service.dart';
import '../lib/core/services/bundled_tafsir_source.dart';
import '../lib/features/mushaf/widgets/tafsir_viewer_sheet.dart';
import 'dart:convert';import 'dart:io';import 'package:dio/dio.dart';import 'package:flutter/services.dart';import 'package:flutter_test/flutter_test.dart';import '../lib/core/services/tafsir_service.dart';import '../lib/core/services/verse_source_client.dart';import '../lib/core/services/quran_repository.dart';
class NoNetwork implements HttpClientAdapter{
 @override Future<ResponseBody> fetch(RequestOptions o,Stream<Uint8List>? s,Future<dynamic>? c)async=>throw StateError('Network forbidden');
 @override void close({bool force=false}){}
}
void main(){TestWidgetsFlutterBinding.ensureInitialized();
 setUpAll((){TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));TafsirService.setClientForTesting(AlQuranCloudTafsirClient(dio:Dio()..httpClientAdapter=NoNetwork()));});
 tearDownAll((){TafsirService.setClientForTesting(null);QuranRepository.resetCachesForTesting();TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null);});
 test('Saadi 22:20 loads through the checksum-verified runtime with the printed word',()async{
  final r=await TafsirService.getTafsir(surahId:22,ayahNumber:20,editionId:'saadi');
  expect(r.hasSourceText,isTrue);
  expect(r.tafsirText,contains('يصهر به ما في بطونهم'));expect(r.sourceNotice,contains('٥٣٦'));expect(r.sourceNotice,contains('تصحيح موضعي واحد'));
 });
 test('Saadi notice reaches TafsirResult only for 26:134 and 56:30',()async{
  Future<String> w(int s,int a)async=>(await TafsirService.getTafsir(surahId:s,ayahNumber:a,editionId:'saadi')).sourceNotice??'';
  expect(await w(26,134),contains('٥٩٥'));
  expect(await w(16,64),contains('٤٤٣'));
  expect(await w(7,24),contains('لا يظهر شرح مستقل صريح'));expect(await w(7,24),contains('سياق الآيات المجاورة'));
  expect(await w(7,23),isNot(contains('لا يرد لهذه الآية')));
  expect(await w(7,25),isNot(contains('لا يرد لهذه الآية')));
  expect(await w(16,63),isNot(contains('لا يرد لهذه الآية')));
  expect(await w(16,65),isNot(contains('لا يرد لهذه الآية')));
  expect(await w(56,30),contains('٨٣٣'));
  expect(await w(26,180),contains('٥٩٧'));
  expect(await w(26,183),contains('٥٩٧'));
  expect(await w(26,181),isNot(contains('لا يرد لهذه الآية')));
  expect(await w(26,135),isNot(contains('لا يرد لهذه الآية')));
  expect(await w(1,2),isNot(contains('لا يرد لهذه الآية')));
 });
 test('Saadi 7:24 shows the print 23 passage and the continuation headed 25-26, 7:23 and 7:25 unchanged',()async{
  Future<String> t(int a)async=>(await TafsirService.getTafsir(surahId:7,ayahNumber:a,editionId:'saadi')).tafsirText??'';
  final a24=await t(24);
  expect(a24,contains('فغفر الله لهما ذلك'));
  expect(a24,contains('لما أهبط الله آدم وزوجته وذريتهما'));
  expect(await t(23),isNot(contains('لما أهبط الله آدم وزوجته وذريتهما')));
  expect(await t(25),contains('لما أهبط الله آدم وزوجته وذريتهما'));
  expect(await t(25),isNot(contains('فغفر الله لهما ذلك')));
 });
 test('Saadi 6:105-107 keys carry the printed footnote that attributes the commentary to al-Najjar',()async{
  for(final a in [105,106,107]){
   final r=await TafsirService.getTafsir(surahId:6,ayahNumber:a,editionId:'saadi');
   expect(r.hasSourceText,isTrue,reason:'6:\$a');
   expect(r.tafsirText,contains('فقام النجار بتفسيرها دون الإشارة إلى أنها ليست من كلام الشيخ'),reason:'6:\$a');
  }
  final other=await TafsirService.getTafsir(surahId:6,ayahNumber:1,editionId:'saadi');
  expect(other.tafsirText,isNot(contains('فقام النجار بتفسيرها')));
 });
}
