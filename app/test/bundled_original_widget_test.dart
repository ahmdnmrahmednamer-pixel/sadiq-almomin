import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import '../lib/core/services/bundled_original_book.dart';
import '../lib/core/services/jadwal_source.dart';
import '../lib/core/services/quran_repository.dart';
import '../lib/features/mushaf/screens/quran_irab_screen.dart';
import 'bundled_original_book_test.dart' show DenyBookNetwork;
void main(){
 final root=Platform.environment['PRIVATE_CORPUS_PREPARATION'];
 testWidgets('installed Jadwal opens selected ayah without network or initial download',(t)async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async{
    final f=File(utf8.decode(m!.buffer.asUint8List()));return f.existsSync()?ByteData.sublistView(f.readAsBytesSync()):null;
  });
  addTearDown((){QuranRepository.resetCachesForTesting();TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null);});
  await t.runAsync(()async{
    await(FontLoader('Amiri')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/Amiri-Regular.ttf').readAsBytesSync())))).load();
    await(FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(File('/home/sandbox/flutter-product/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())))).load();
  });
  t.view.physicalSize=const Size(480,1100);t.view.devicePixelRatio=1;
  addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  final manifest=jsonDecode(File('$root/manifest.json').readAsStringSync());
  final row=(manifest['sources']as List).singleWhere((s)=>s['key']=='jadwal');
  final packed=BundledOriginalBook(assetPath:row['packedFile'],compressedSha256:row['packedSha256'],originalSha256:row['originalSha256'],originalBytes:row['originalBytes'],readAsset:(p)=>File('$root/$p').readAsBytes());
  final deny=DenyBookNetwork();
  final source=JadwalSource(dio:Dio()..httpClientAdapter=deny,bundledOriginal:packed,loadIndex:()async=>jsonDecode(File('/tmp/jadwal-preparation/jadwal_verse_index.json').readAsStringSync()),storageDirectory:()async=>throw StateError('No initial cache required'));
  final key=GlobalKey();
  await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData(fontFamily:'Amiri'),home:QuranIrabScreen(initialSurahId:40,initialAyah:10,source:source))));
  await t.runAsync(()async{for(var i=0;i<100;i++){await Future<void>.delayed(const Duration(milliseconds:20));await t.pump();}});
  await t.pumpAndSettle();
  expect(find.textContaining('النص مدمج مع التثبيت'),findsOneWidget);
  expect(find.text('تنزيل الكتاب كاملًا'),findsNothing);
  expect(find.textContaining('غير مطابقة للفهرس'),findsNothing);
  expect(find.text('ج24 ص226'),findsOneWidget);expect(deny.calls,0);expect(t.takeException(),isNull);
  if(Platform.environment['CAPTURE_PRIVATE_CORPUS']=='1'){
   await t.runAsync(()async{final image=await(key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();final bytes=await image.toByteData(format:ui.ImageByteFormat.png);await File('/tmp/private-installed-jadwal-40-10.png').writeAsBytes(bytes!.buffer.asUint8List());});
  }
 },skip:root==null);
}
