import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/quran_repository.dart';
import '../lib/core/services/tafsir_service.dart';
import '../lib/core/services/quran_linguistics_service.dart';
import '../lib/core/services/settings_service.dart';
import '../lib/core/models/ayah.dart';
import '../lib/features/mushaf/widgets/tafsir_viewer_sheet.dart';
import 'reader_accessibility_integration_test.dart' show surah;
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUp(()async{
  SharedPreferences.setMockInitialValues({'default_tafsir_edition':'qurtubi'});await SettingsService.instance.init(forceReload:true);QuranRepository.resetCachesForTesting();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async{
   final p=utf8.decode(m!.buffer.asUint8List());
   final rows=[{'id':1,'surah_id':1,'ayah_number':1,'juz':1,'page':1,'text_uthmani':'نص تجريبي','tafseer':'VERBATIM_LOCAL_TEXT'}];
   Object? value;if(p=='assets/data/surahs/1.json')value=rows;if(p=='assets/data/quran_ayahs.json')value={'1':rows};
   return value==null?null:ByteData.sublistView(utf8.encode(jsonEncode(value)));
  });
 });
 tearDown((){QuranRepository.resetCachesForTesting();TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null);});
 test('bundled Muyassar is returned verbatim only as Muyassar',()async{
  final a=await TafsirService.getTafsir(surahId:1,ayahNumber:1);expect(a.tafsirText,'VERBATIM_LOCAL_TEXT');
  for(final e in TafsirService.availableEditions.where((e)=>e.id!='muyassar')){
   final b=await TafsirService.getTafsir(surahId:1,ayahNumber:1,editionId:e.id);expect(b.tafsirText,isNot(contains('VERBATIM_LOCAL_TEXT')));expect(b.tafsirText,contains('لم يُربط'));
  }
 });
 test('removed linguistics never supplies guessed grammar or another verse cause',()async{
  final d=await QuranLinguisticsService.getDetails(surahId:1,ayahNumber:1);expect(d.grammar.words,isEmpty);expect(d.wordMeanings,isEmpty);expect(d.grammar.rhetoricSummary,isEmpty);expect(d.asbabNuzul.source,contains('لم'));expect(d.asbabNuzul.narration,contains('لا يعني'));
 });
 testWidgets('tafsir sheet starts from stored preferred edition',(t)async{
  await SettingsService.instance.setDefaultTafsirEdition('qurtubi');
  final ayah=Ayah.fromRow({'id':1,'surah_id':1,'ayah_number':1,'juz':1,'page':1,'text_uthmani':'نص تجريبي'});
  final key=GlobalKey();
  final font=Platform.environment['READING_TEST_FONT'];
  if(font!=null)await t.runAsync(()async{
   for(final family in ['ArabicTest','Amiri','UthmanicHafs','NotoNaskhArabic'])await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(await File(font).readAsBytes())))).load();
   final icons=Platform.environment['READING_TEST_ICON_FONT'];if(icons!=null)await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(await File(icons).readAsBytes())))).load();
  });
  await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData(fontFamily:'ArabicTest'),home:Scaffold(body:TafsirViewerSheet(surah:surah,initialAyah:ayah)))));for(var i=0;i<10;i++){await t.pump(const Duration(milliseconds:50));await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:10)));}await t.pumpAndSettle();expect(find.text('الجامع لأحكام القرآن (القرطبي)'),findsWidgets);expect(find.text('VERBATIM_LOCAL_TEXT'),findsNothing);expect(t.takeException(),isNull);
  if(font!=null)await t.runAsync(()async{final image=await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();final bytes=await image.toByteData(format:ui.ImageByteFormat.png);await File('/tmp/tafsir-preferred-source-safe.png').writeAsBytes(bytes!.buffer.asUint8List());});
 });
}
