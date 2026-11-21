import 'dart:io';import 'dart:ui' as ui;
import 'package:flutter/material.dart';import 'package:flutter/rendering.dart';import 'package:flutter/semantics.dart';import 'package:flutter/services.dart';import 'package:flutter_test/flutter_test.dart';import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/settings_service.dart';import '../lib/features/library/screens/approved_sources_screen.dart';
void main(){
 testWidgets('Sources screen render and semantics dump at 320',(t)async{
  SharedPreferences.setMockInitialValues({});
  await t.runAsync(()async{await SettingsService.instance.init(forceReload:true);for(final item in {'Amiri':'assets/fonts/Amiri-Regular.ttf','MaterialIcons':'/home/sandbox/flutter-product/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'}.entries){await(FontLoader(item.key)..addFont(Future.value(ByteData.sublistView(File(item.value).readAsBytesSync())))).load();}});
  t.view.physicalSize=const Size(320,1500);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  final h=t.ensureSemantics();final key=GlobalKey();
  await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData(fontFamily:'Amiri'),home:const ApprovedSourcesScreen())));
  await t.pumpAndSettle();expect(t.takeException(),isNull);
  File('/downloads/sources_semantics_320.txt').writeAsStringSync(t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!.toStringDeep(childOrder:DebugSemanticsDumpOrder.traversalOrder));
  await t.runAsync(()async{final image=await(key.currentContext!.findRenderObject()as RenderRepaintBoundary).toImage();final b=await image.toByteData(format:ui.ImageByteFormat.png);File('/downloads/sources_screen_320.png').writeAsBytesSync(b!.buffer.asUint8List());});
  h.dispose();
 });
}
