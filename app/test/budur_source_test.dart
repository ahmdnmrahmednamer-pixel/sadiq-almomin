import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/budur_source.dart';
import '../lib/core/services/quran_repository.dart';
import '../lib/core/services/settings_service.dart';
import '../lib/core/models/ayah.dart';
import '../lib/core/models/surah.dart';
import '../lib/features/mushaf/screens/qiraat_mushaf_screen.dart';
const chapter=Surah(id:1,nameAr:'اختبار',nameSimple:'اختبار',revelationPlace:'makkah',revelationOrder:1,ayahCount:2,hasBasmala:false,pageStart:1,pageEnd:1);
// Synthetic content. Never religious text and never shipped as a source.
const fixture='سورة اختبار\n" لفظ تجريبي فريد " SOURCE_A\ncontinuation with source note\nالجزء: 1 ¦ الصفحة: 15\n" كلمة " SOURCE_B\nالجزء: 1 ¦ الصفحة: 16\nتصويبات للشيخ\n" لفظ تجريبي فريد " EXCLUDED';
List<Map<String,dynamic>> get rows=>[{'id':1,'surah_id':1,'ayah_number':1,'juz':1,'page':1,'text_uthmani':'لفظ تجريبي فريد كلمة'},{'id':2,'surah_id':1,'ayah_number':2,'juz':1,'page':1,'text_uthmani':'لفظ مختلف كلمة'}];
class FakeBudur extends BudurSource {@override Future<String> load()async=>fixture;}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('source passages keep continuation and page, exclude corrections, refuse repeated-word attribution',(){
  final p=BudurSource.passages(fixture,chapter,rows.map(Ayah.fromRow).toList());
  expect(p.length,2);expect(p.first.ayahs,[1]);expect(p.first.text,contains('continuation with source note'));expect(p.first.firstPage,15);expect(p.last.ayahs,isEmpty);expect(p.any((p)=>p.text.contains('EXCLUDED')),isFalse);
 });
 test('wrong surah never inherits passage',(){
  expect(BudurSource.passages(fixture.replaceFirst('سورة اختبار','سورة أخرى'),chapter,rows.map(Ayah.fromRow).toList()),isEmpty);
 });
 testWidgets('source reader loads surah and selects exact verse passages',(t)async{
  SharedPreferences.setMockInitialValues({});await SettingsService.instance.init(forceReload:true);QuranRepository.resetCachesForTesting();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async{
   final path=utf8.decode(m!.buffer.asUint8List());Object? value;
   if(path=='assets/data/surahs/1.json')value=rows;
   if(path=='assets/data/surahs.json')value=[{'id':1,'name_ar':'اختبار','revelation_place':'makkah','revelation_order':1,'ayah_count':2,'page_start':1,'page_end':1}];
   return value==null?null:ByteData.sublistView(utf8.encode(jsonEncode(value)));
  });
  addTearDown((){QuranRepository.resetCachesForTesting();TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null);});
  final font=Platform.environment['READING_TEST_FONT'];
  if(font!=null)await t.runAsync(()async{
   await (FontLoader('ArabicTest')..addFont(Future.value(ByteData.sublistView(await File(font).readAsBytes())))).load();
   final latin=Platform.environment['READING_TEST_LATIN_FONT'];if(latin!=null)await (FontLoader('LatinTest')..addFont(Future.value(ByteData.sublistView(await File(latin).readAsBytes())))).load();
   final icons=Platform.environment['READING_TEST_ICON_FONT'];if(icons!=null)await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(await File(icons).readAsBytes())))).load();
  });
  t.view.physicalSize=const Size(600,1200);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  final key=GlobalKey();
  await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData(fontFamily:'ArabicTest',fontFamilyFallback:['LatinTest']),home:QiraatMushafScreen(source:FakeBudur()))));await t.pumpAndSettle();
  expect(find.textContaining('SOURCE_A'),findsOneWidget);expect(find.textContaining('SOURCE_B'),findsOneWidget);
  await t.tap(find.byType(DropdownButtonFormField<int>).last);await t.pumpAndSettle();await t.tap(find.text('1').last);await t.pumpAndSettle();
  expect(find.textContaining('SOURCE_A'),findsOneWidget);expect(find.textContaining('SOURCE_B'),findsNothing);expect(t.takeException(),isNull);
  if(font!=null)await t.runAsync(()async{final image=await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();final bytes=await image.toByteData(format:ui.ImageByteFormat.png);await File('/tmp/budur-reader-visual.png').writeAsBytes(bytes!.buffer.asUint8List());});
 });
}
