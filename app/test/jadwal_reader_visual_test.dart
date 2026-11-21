import 'dart:io';import 'dart:convert';import 'dart:ui' as ui;
import 'package:flutter/material.dart';import 'package:flutter/rendering.dart';import 'package:flutter/services.dart';import 'package:flutter_test/flutter_test.dart';
import '../lib/features/mushaf/screens/quran_irab_screen.dart';
void main(){
 testWidgets('Jadwal reader renders supplement and ordinary entries',(t)async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async{final f=File(utf8.decode(m!.buffer.asUint8List()));return f.existsSync()?ByteData.sublistView(f.readAsBytesSync()):null;});
  await t.runAsync(()async{for(final item in {'Amiri':'assets/fonts/Amiri-Regular.ttf','MaterialIcons':'/home/sandbox/flutter-product/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'}.entries){await(FontLoader(item.key)..addFont(Future.value(ByteData.sublistView(await File(item.value).readAsBytes())))).load();}});
  t.view.devicePixelRatio=1;t.view.physicalSize=const Size(320,1400);addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  for(final s in [[35,3],[40,10],[2,34]]){
   final key=GlobalKey();
   await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData(fontFamily:'Amiri'),home:Directionality(textDirection:TextDirection.rtl,child:QuranIrabScreen(initialSurahId:s[0],initialAyah:s[1])))));
   await t.runAsync(()async{for(var i=0;i<120;i++){await Future<void>.delayed(const Duration(milliseconds:15));await t.pump();}});await t.pumpAndSettle();
   expect(t.takeException(),isNull);
   expect(find.textContaining('تعذر'),findsNothing);
   await t.runAsync(()async{final im=await(key.currentContext!.findRenderObject()as RenderRepaintBoundary).toImage();final by=await im.toByteData(format:ui.ImageByteFormat.png);File('/downloads/jadwal_reader_${s[0]}-${s[1]}-320.png').writeAsBytesSync(by!.buffer.asUint8List());});
  }
 });
}
