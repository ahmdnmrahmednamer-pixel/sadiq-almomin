import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/settings_service.dart';
import '../lib/core/services/bundled_tafsir_source.dart';
import '../lib/features/mushaf/widgets/tafsir_viewer_sheet.dart';
import 'dart:convert';import 'dart:io';import 'package:dio/dio.dart';import 'package:flutter/services.dart';import 'package:flutter_test/flutter_test.dart';import '../lib/core/services/tafsir_service.dart';import '../lib/core/services/verse_source_client.dart';import '../lib/core/services/quran_repository.dart';
class NoNetwork implements HttpClientAdapter{
 @override Future<ResponseBody> fetch(RequestOptions o,Stream<Uint8List>? s,Future<dynamic>? c)async=>throw StateError('Network forbidden in bundled test');
 @override void close({bool force=false}){}
}
class MissingBundle extends BundledTafsirSource{@override Future<BundledTafsirEntry?> fetch(String e,int s,int a)async=>null;}
void main(){TestWidgetsFlutterBinding.ensureInitialized();
 setUpAll((){TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async=>ByteData.sublistView(await File(utf8.decode(m!.buffer.asUint8List())).readAsBytes()));TafsirService.setClientForTesting(AlQuranCloudTafsirClient(dio:Dio()..httpClientAdapter=NoNetwork()));});
 tearDownAll((){TafsirService.setClientForTesting(null);QuranRepository.resetCachesForTesting();TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null);});
 test('actual verse options reach embedded tafsir without live API',()async{
  for(final edition in ['jalalayn','ibn_kathir','tabari','baghawi','qurtubi']){for(final s in [1,2,35,40,114]){
   final r=await TafsirService.getTafsir(surahId:s,ayahNumber:2,editionId:edition);expect(r.hasSourceText,isTrue,reason:'$edition $s');expect(r.editionId,edition);expect(r.tafsirText.length,greaterThan(0));expect(r.tafsirText,contains('ج'));
  }}
 });
 testWidgets('unproved Jalalayn location is disclosed and cannot be copied or shared',(t)async{
  TafsirService.setBundledSourceForTesting(MissingBundle());addTearDown(()=>TafsirService.setBundledSourceForTesting(null));
  SharedPreferences.setMockInitialValues({'default_tafsir_edition':'jalalayn'});
  late dynamic surah;late dynamic ayah;
  await t.runAsync(()async{await SettingsService.instance.init(forceReload:true);surah=await QuranRepository.getSurah(1);ayah=await QuranRepository.getAyah(1,1);});
  await t.pumpWidget(MaterialApp(home:Scaffold(body:Directionality(textDirection:TextDirection.rtl,child:TafsirViewerSheet(surah:surah,initialAyah:ayah)))));
  await t.runAsync(()async{for(var n=0;n<40;n++){await Future<void>.delayed(const Duration(milliseconds:10));await t.pump();if(find.textContaining('لم يُثبت').evaluate().isNotEmpty)break;}});await t.pumpAndSettle();
  expect(find.textContaining('لم يُثبت'),findsOneWidget);expect(find.textContaining('لا يُستبدل'),findsOneWidget);
  expect(t.widget<IconButton>(find.widgetWithIcon(IconButton,Icons.copy_rounded)).onPressed,isNull);
  expect(t.widget<IconButton>(find.widgetWithIcon(IconButton,Icons.share_rounded)).onPressed,isNull);
  expect(t.takeException(),isNull);
 });
 test('incomplete source fragment warning accompanies copies and shares',()async{
  final r=await TafsirService.getTafsir(surahId:68,ayahNumber:49,editionId:'jalalayn');
  expect(r.hasSourceText,isTrue);expect(r.sourceNotice,contains('ينقطع نصها'));
  expect(r.formatForShare('القلم'),contains('ينقطع نصها'));
  expect(r.tafsirText,contains('نعمة'));
 });
 test('Jalalayn 3:98 shows the missing-gloss notice and 3:99 shows its continuation notice, no recovery of 3:98 text',()async{
  final r98=await TafsirService.getTafsir(surahId:3,ayahNumber:98,editionId:'jalalayn');
  final r99=await TafsirService.getTafsir(surahId:3,ayahNumber:99,editionId:'jalalayn');
  expect(r98.hasSourceText,isTrue);expect(r99.hasSourceText,isTrue);
  expect(r98.sourceNotice,contains('شرح هذه الآية غير موجود'));
  expect(r98.formatForShare('آل عمران'),contains('غير موجود'));
  expect(r98.tafsirText,isNot(contains('فيجازيكم عليه')));
  expect(r99.sourceNotice,contains('شرح الآية 98 نفسه غير موجود'));
  expect(r99.tafsirText,contains('تَصْرِفُونَ'));expect(r99.tafsirText,contains('تَبْغُونَهَا'));
  expect(r99.tafsirText.indexOf('تَصْرِفُونَ'),lessThan(r99.tafsirText.indexOf('تَبْغُونَهَا')));
 });
 test('missing original location does not borrow adjacent tafsir or network',()async{
  TafsirService.setBundledSourceForTesting(MissingBundle());addTearDown(()=>TafsirService.setBundledSourceForTesting(null));
  final r=await TafsirService.getTafsir(surahId:1,ayahNumber:1,editionId:'jalalayn');expect(r.hasSourceText,isFalse);expect(r.tafsirText,contains('لا يُستبدل'));
 });
}
