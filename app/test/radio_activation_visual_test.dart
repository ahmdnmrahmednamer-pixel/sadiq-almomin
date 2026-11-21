import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/widgets/app_navigation_drawer.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/radio/curated_radio_screen.dart';
import 'curated_radio_defects_test.dart' show HeldPlayer;
void main(){
 testWidgets('enabled drawer entry reaches replacement and renders RTL pixels',(t)async{
 SharedPreferences.setMockInitialValues({});await SettingsService.instance.init();
 final routerPath=Platform.environment['RADIO_ROUTER_UNDER_CHECK'] ?? 'lib/app/router.dart';
 final productionRoute=File(routerPath).readAsStringSync();
 expect(productionRoute,contains("path: '/islamic-radio', builder: (context, state) => const CuratedRadioScreen()"));
 expect(productionRoute, isNot(contains("path: '/islamic-radio', builder: (context, state) => const IslamicRadioScreen()")));
 await t.runAsync(()async{
 for(final e in {'Amiri':'assets/fonts/Amiri-Regular.ttf','MaterialIcons':'${Platform.environment['FLUTTER_ROOT'] ?? Platform.resolvedExecutable.split('/bin/cache/dart-sdk/').first}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'}.entries){await (FontLoader(e.key)..addFont(Future.value(ByteData.sublistView(File(e.value).readAsBytesSync())))).load();}
 });
 t.view.devicePixelRatio=1;t.view.physicalSize=const Size(390,900);
 addTearDown(t.view.resetDevicePixelRatio);addTearDown(t.view.resetPhysicalSize);
 final boundary=GlobalKey();final fake=HeldPlayer();
 final router=GoRouter(routes:[GoRoute(path:'/',builder:(_,__)=>const Scaffold(drawer:AppNavigationDrawer(),body:Text('الرئيسية'))),GoRoute(path:'/islamic-radio',builder:(_,__)=>CuratedRadioScreen(playerFactory:()=>fake)),GoRoute(path:'/curated-radio',builder:(_,__)=>CuratedRadioScreen(playerFactory:()=>fake))]);
 addTearDown(router.dispose);
 await t.pumpWidget(RepaintBoundary(key:boundary,child:MaterialApp.router(debugShowCheckedModeBanner:false,theme:ThemeData(fontFamily:'Amiri'),routerConfig:router,builder:(_,child)=>Directionality(textDirection:TextDirection.rtl,child:child!))));await t.pumpAndSettle();
 t.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();await t.pumpAndSettle();
 await t.scrollUntilVisible(find.text('الإذاعة'),200,scrollable:find.byType(Scrollable).last);await t.pumpAndSettle();
 Future<void> capture(String name)async{await t.runAsync(()async{final image=await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();final bytes=await image.toByteData(format:ui.ImageByteFormat.png);File('${Platform.environment['RADIO_PIXEL_DIR'] ?? Directory.systemTemp.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());});}
 await t.drag(find.byType(Scrollable).last,const Offset(0,180));await t.pumpAndSettle();
 await capture('radio-enabled-drawer');
 await t.tap(find.text('الإذاعة'));await t.pumpAndSettle();expect(find.byType(CuratedRadioScreen),findsOneWidget);expect(find.text('المفضلة'),findsOneWidget);
 await capture('radio-enabled-categories');
 final category=find.byKey(const Key('curated_radio_cat_c2'));
 if(category.evaluate().isNotEmpty){await t.tap(category);await t.pumpAndSettle();await capture('radio-enabled-stations');}
 expect(t.takeException(),isNull);
 });
}
