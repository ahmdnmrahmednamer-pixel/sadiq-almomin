import 'dart:io';import 'dart:convert';import 'dart:ui' as ui;
import 'package:flutter/material.dart';import 'package:flutter/rendering.dart';import 'package:flutter/services.dart';import 'package:flutter_test/flutter_test.dart';import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/settings_service.dart';import '../lib/core/services/quran_repository.dart';import '../lib/features/library/screens/approved_sources_screen.dart';import '../lib/features/settings/widgets/sections/settings_prayer_and_fiqh_section.dart';import '../lib/features/mushaf/screens/quran_asbab_nuzul_screen.dart';
void main(){
 testWidgets('changed screens render',(t)async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async{final f=File(utf8.decode(m!.buffer.asUint8List()));return f.existsSync()?ByteData.sublistView(f.readAsBytesSync()):null;});
  SharedPreferences.setMockInitialValues({});
  await t.runAsync(()async{await SettingsService.instance.init(forceReload:true);for(final item in {'Amiri':'assets/fonts/Amiri-Regular.ttf','Kitab':'assets/fonts/Kitab-Regular.ttf','MaterialIcons':'/home/sandbox/flutter-product/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'}.entries){await(FontLoader(item.key)..addFont(Future.value(ByteData.sublistView(File(item.value).readAsBytesSync())))).load();}});
  t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  for(final spec in [['sources',const ApprovedSourcesScreen(),1.0,360.0,1500.0],['settings_large',const SingleChildScrollView(child:SettingsPrayerAndFiqhSection()),2.0,480.0,1500.0]]){
   t.view.physicalSize=Size(spec[3] as double,spec[4] as double);final key=GlobalKey();
   await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData(fontFamily:'Amiri'),home:MediaQuery(data:MediaQueryData(textScaler:TextScaler.linear(spec[2] as double)),child:Directionality(textDirection:TextDirection.rtl,child:Scaffold(body:spec[1] as Widget))))));
   await t.runAsync(()async{for(var i=0;i<40;i++){await Future<void>.delayed(const Duration(milliseconds:15));await t.pump();}});
   expect(t.takeException(),isNull);
   await t.runAsync(()async{final image=await(key.currentContext!.findRenderObject()as RenderRepaintBoundary).toImage();final bytes=await image.toByteData(format:ui.ImageByteFormat.png);File('/downloads/changed_${spec[0]}.png').writeAsBytesSync(bytes!.buffer.asUint8List());});
  }
 });
}
