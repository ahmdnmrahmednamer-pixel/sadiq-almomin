import 'dart:io';import 'dart:convert';import 'dart:ui' as ui;
import 'package:flutter/material.dart';import 'package:flutter/rendering.dart';import 'package:flutter/services.dart';import 'package:flutter_test/flutter_test.dart';import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/settings_service.dart';import '../lib/core/services/quran_repository.dart';import '../lib/features/mushaf/widgets/tafsir_viewer_sheet.dart';import '../lib/features/mushaf/screens/quran_asbab_nuzul_screen.dart';
void main(){
 testWidgets('private span-adapted readers retain actual source and shared-context labels at320and480',(t)async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async{final f=File(utf8.decode(m!.buffer.asUint8List()));return f.existsSync()?ByteData.sublistView(f.readAsBytesSync()):null;});
  SharedPreferences.setMockInitialValues({'default_tafsir_edition':'saadi'});
  await t.runAsync(()async{await SettingsService.instance.init(forceReload:true);for(final item in {'Amiri':'assets/fonts/Amiri-Regular.ttf','Kitab':'assets/fonts/Kitab-Regular.ttf','MaterialIcons':'/home/sandbox/flutter-product/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'}.entries){await(FontLoader(item.key)..addFont(Future.value(ByteData.sublistView(File(item.value).readAsBytesSync())))).load();}});
  t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  for(final spec in [<dynamic>['saadi',26,134,320]]){
   t.view.physicalSize=Size((spec[3]as int).toDouble(),1100);final key=GlobalKey();final sem=t.ensureSemantics();late Widget child;
   SharedPreferences.setMockInitialValues({'default_tafsir_edition':spec[0]});
   await t.runAsync(()async{await SettingsService.instance.init(forceReload:true);});
   late dynamic s,a;await t.runAsync(()async{s=await QuranRepository.getSurah(spec[1]);a=await QuranRepository.getAyah(spec[1],spec[2]);});child=TafsirViewerSheet(key:ValueKey(spec.join(':')),surah:s,initialAyah:a);
   await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData(fontFamily:'Amiri'),home:Scaffold(body:Directionality(textDirection:TextDirection.rtl,child:child)))));
   await t.runAsync(()async{for(var i=0;i<100;i++){await Future<void>.delayed(const Duration(milliseconds:15));await t.pump();}});await t.pumpAndSettle();
   expect(t.takeException(),isNull);expect(find.textContaining('لم يُربط'),findsNothing);expect(find.textContaining('تعذر قراءة'),findsNothing);
   expect(find.textContaining('لا يرد لهذه الآية'),findsOneWidget);
   await t.pumpAndSettle();expect(t.takeException(),isNull);
   
   final out=StringBuffer();void walk(SemanticsNode n,int d){final dt=n.getSemanticsData();final l=dt.label.replaceAll('\n',' ');final a=<String>[];if(dt.hasAction(SemanticsAction.tap))a.add('tap');if(dt.hasAction(SemanticsAction.scrollDown)||dt.hasAction(SemanticsAction.scrollUp))a.add('scroll');if(dt.hasFlag(SemanticsFlag.isButton))a.add('button');if(dt.hasFlag(SemanticsFlag.isHeader))a.add('header');if(l.isNotEmpty||dt.tooltip.isNotEmpty||a.isNotEmpty)out.writeln('${'  '*d}[${a.join(',')}] ${l} ${dt.tooltip}');n.visitChildren((c){walk(c,d+1);return true;});}
   walk(t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!,0);File('/downloads/saadi_reader_semantics_tree_320.txt').writeAsStringSync(out.toString());final tree=out.toString();final m='نص الآية رقم 134: ';final at=tree.indexOf(m);expect(at,greaterThan(-1));final rest=tree.substring(at+m.length).split('\n').first.trim();expect('وَعُیُونٍ'.allMatches(rest).length,1,reason:'ayah text exposed once, got: '+rest);expect(tree.contains('[header] مقطع المصدر'),isTrue);expect(tree.contains('استمع للآية'),isTrue);expect(tree.contains('الآية التالية'),isTrue);final notice=(jsonDecode(File('assets/data/tafsir_saadi_roots_manifest.json').readAsStringSync())as Map)['sourceWarnings']['26:134']as String;expect(tree.contains(notice),isTrue,reason:'full notice must be in one semantics node label');expect(tree.contains('[tap,button] التفسير تفسير السعدي (تيسير الكريم الرحمن) \n'),isTrue);expect(tree.contains('[tap,button] رقم الآية آية 134 \n'),isTrue);expect(tree.contains('الاختيار الحالي'),isFalse);sem.dispose();
  }
 });
}
