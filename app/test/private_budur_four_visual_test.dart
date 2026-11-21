import 'dart:io';import 'dart:convert';import 'dart:ui' as ui;
import 'package:flutter/material.dart';import 'package:flutter/rendering.dart';import 'package:flutter/services.dart';import 'package:flutter_test/flutter_test.dart';import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/settings_service.dart';import '../lib/core/services/quran_repository.dart';import '../lib/features/mushaf/screens/qiraat_mushaf_screen.dart';import '../lib/features/mushaf/screens/quran_irab_screen.dart';
class DenyReaderHttp extends HttpOverrides{int calls=0;@override HttpClient createHttpClient(SecurityContext?c){calls++;throw StateError('No network in default reader acceptance');}}
void main(){testWidgets('default installed readers and four exact context labels at320pixels',(t)async{
 final deny=DenyReaderHttp();HttpOverrides.global=deny;addTearDown(()=>HttpOverrides.global=null);
 TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async{final f=File(utf8.decode(m!.buffer.asUint8List()));return f.existsSync()?ByteData.sublistView(f.readAsBytesSync()):null;});
 SharedPreferences.setMockInitialValues({});QuranRepository.resetCachesForTesting();
 await t.runAsync(()async{await SettingsService.instance.init(forceReload:true);for(final item in {'Amiri':'assets/fonts/Amiri-Regular.ttf','MaterialIcons':'/home/sandbox/flutter-product/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'}.entries){await(FontLoader(item.key)..addFont(Future.value(ByteData.sublistView(File(item.value).readAsBytesSync())))).load();}await QuranRepository.loadSurahs();for(final s in [5,41,78,100,35]){await QuranRepository.getAyahsForSurah(s);}});
 t.view.devicePixelRatio=1;t.view.physicalSize=const Size(320,1100);addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
 for(final spec in [('budur',5,109),('budur',41,47),('budur',78,1),('budur',100,9),('jadwal',35,3)]){
  final key=GlobalKey();final child=spec.$1=='budur'?QiraatMushafScreen(key:ValueKey(spec),initialSurah:spec.$2,initialAyah:spec.$3):QuranIrabScreen(key:ValueKey(spec),initialSurahId:spec.$2,initialAyah:spec.$3);
  await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData(fontFamily:'Amiri'),home:child)));
  await t.runAsync(()async{for(var i=0;i<60;i++){await Future<void>.delayed(const Duration(milliseconds:30));await t.pump();}});await t.pumpAndSettle();expect(t.takeException(),isNull);expect(find.byType(CircularProgressIndicator),findsNothing);
  if(spec.$1=='budur'){expect(find.textContaining('سياق مشترك'),findsOneWidget);await t.ensureVisible(find.textContaining('سياق مشترك'));}else{expect(find.textContaining('النص مدمج مع التثبيت'),findsOneWidget);expect(find.text('تنزيل الكتاب كاملًا'),findsNothing);expect(find.textContaining('الصفحة غير متوفرة'),findsNothing);expect(find.textContaining('المقطع مشترك للآيات 3 إلى 4'),findsOneWidget);await t.ensureVisible(find.textContaining('المقطع مشترك للآيات 3 إلى 4'));}
  await t.pumpAndSettle();expect(deny.calls,0);
  await t.runAsync(()async{final image=await(key.currentContext!.findRenderObject()as RenderRepaintBoundary).toImage();final bytes=await image.toByteData(format:ui.ImageByteFormat.png);File('/tmp/offline-corpus-preparation/default-installed-${spec.$1}-${spec.$2}-${spec.$3}-320.png').writeAsBytesSync(bytes!.buffer.asUint8List());});
 }
});}
