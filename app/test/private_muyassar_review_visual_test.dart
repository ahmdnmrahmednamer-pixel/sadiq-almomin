import 'dart:io';import 'dart:convert';import 'dart:ui' as ui;
import 'package:flutter/material.dart';import 'package:flutter/rendering.dart';import 'package:flutter/services.dart';import 'package:flutter_test/flutter_test.dart';import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/settings_service.dart';import '../lib/core/services/quran_repository.dart';import '../lib/features/mushaf/widgets/tafsir_viewer_sheet.dart';
void main(){
 testWidgets('review variants visible on narrow readers',(t)async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async{final f=File(utf8.decode(m!.buffer.asUint8List()));return f.existsSync()?ByteData.sublistView(f.readAsBytesSync()):null;});
  SharedPreferences.setMockInitialValues({'default_tafsir_edition':'saadi'});
  await t.runAsync(()async{await SettingsService.instance.init(forceReload:true);for(final item in {'Amiri':'assets/fonts/Amiri-Regular.ttf','Kitab':'assets/fonts/Kitab-Regular.ttf','MaterialIcons':'/home/sandbox/flutter-product/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'}.entries){await(FontLoader(item.key)..addFont(Future.value(ByteData.sublistView(File(item.value).readAsBytesSync())))).load();}});
  t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  for(final spec in [<dynamic>['muyassar',96,6,320],['muyassar',57,9,320],['muyassar',4,170,320]]){
   t.view.physicalSize=Size((spec[3]as int).toDouble(),1100);final key=GlobalKey();late Widget child;
   SharedPreferences.setMockInitialValues({'default_tafsir_edition':spec[0]});
   await t.runAsync(()async{await SettingsService.instance.init(forceReload:true);});
   late dynamic s,a;await t.runAsync(()async{s=await QuranRepository.getSurah(spec[1]);a=await QuranRepository.getAyah(spec[1],spec[2]);});child=TafsirViewerSheet(key:ValueKey(spec.join(':')),surah:s,initialAyah:a);
   await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData(fontFamily:'Amiri'),home:Scaffold(body:Directionality(textDirection:TextDirection.rtl,child:child)))));
   await t.runAsync(()async{for(var i=0;i<100;i++){await Future<void>.delayed(const Duration(milliseconds:15));await t.pump();}});await t.pumpAndSettle();
   expect(t.takeException(),isNull);expect(find.textContaining('لم يُربط'),findsNothing);expect(find.textContaining('تعذر قراءة'),findsNothing);
   expect(find.textContaining('اختلاف النسختين'),findsWidgets);await t.ensureVisible(find.textContaining('اختلاف النسختين: النص الثاني').last);await t.pumpAndSettle();
   await t.pumpAndSettle();expect(t.takeException(),isNull);
   await t.runAsync(()async{final image=await(key.currentContext!.findRenderObject()as RenderRepaintBoundary).toImage();final bytes=await image.toByteData(format:ui.ImageByteFormat.png);File('/downloads/muyassar-review-${spec[0]}-${spec[1]}-${spec[2]}-${spec[3]}.png').writeAsBytesSync(bytes!.buffer.asUint8List());});
  }
 });
}
