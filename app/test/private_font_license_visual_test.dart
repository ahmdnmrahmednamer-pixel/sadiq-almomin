import 'dart:io';import 'dart:convert';import 'dart:ui' as ui;
import 'package:flutter/material.dart';import 'package:flutter/rendering.dart';import 'package:flutter/services.dart';import 'package:flutter_test/flutter_test.dart';import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/settings_service.dart';import '../lib/core/services/source_font_support.dart';import '../lib/features/settings/widgets/settings_about_modal.dart';
void main(){testWidgets('font license has an accessible in-app route at320pixels',(t)async{
 TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async{final f=File(utf8.decode(m!.buffer.asUint8List()));return f.existsSync()?ByteData.sublistView(f.readAsBytesSync()):null;});
 SharedPreferences.setMockInitialValues({});registerSourceFontLicense();
 await t.runAsync(()async{await SettingsService.instance.init();for(final item in {'Amiri':'assets/fonts/Amiri-Regular.ttf','MaterialIcons':'/home/sandbox/flutter-product/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'}.entries){await(FontLoader(item.key)..addFont(Future.value(ByteData.sublistView(File(item.value).readAsBytesSync())))).load();}});
 t.view.devicePixelRatio=1;t.view.physicalSize=const Size(320,1000);addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);final key=GlobalKey();
 await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData(fontFamily:'Amiri'),home:Scaffold(body:Builder(builder:(c)=>TextButton(onPressed:()=>showSettingsAboutModal(c),child:const Text('عن التطبيق')))))));
 await t.tap(find.text('عن التطبيق'));await t.pumpAndSettle();expect(find.byKey(const ValueKey('settings_about_licenses_button')),findsOneWidget);
 await t.tap(find.byKey(const ValueKey('settings_about_licenses_button')));await t.runAsync(()async{for(var n=0;n<20;n++){await Future<void>.delayed(const Duration(milliseconds:20));await t.pump();}});await t.pumpAndSettle();expect(find.text('Kitab'),findsOneWidget);await t.tap(find.text('Kitab'));await t.pumpAndSettle();expect(find.textContaining('SIL OPEN FONT LICENSE'),findsWidgets);expect(t.takeException(),isNull);
 await t.runAsync(()async{final image=await(key.currentContext!.findRenderObject()as RenderRepaintBoundary).toImage();final bytes=await image.toByteData(format:ui.ImageByteFormat.png);File('/tmp/offline-corpus-preparation/private-kitab-license-320.png').writeAsBytesSync(bytes!.buffer.asUint8List());});
});}
