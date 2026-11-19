import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../lib/features/library/shamela_book_reader_screen.dart';
import 'shamela_online_reader_test.dart' show finishIo;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/shamela_epub_service.dart';
import '../lib/core/services/reader_bookmark_service.dart';
import '../lib/features/library/shamela_offline_reader_screen.dart';

class FixtureService extends ShamelaEpubService {
  @override Future<int?> getLastPosition(int bookId) async => null;
  @override Future<void> saveLastPosition(int bookId,int spineIndex) async {}
}
class LongPageAdapter implements HttpClientAdapter {
 @override Future<ResponseBody> fetch(RequestOptions o,Stream<Uint8List>? s,Future<dynamic>? c) async => ResponseBody.fromString('<html><title>كتاب اختبار</title><div class="nass">${List.filled(200,'<p>نص اختبار طويل لموضع القراءة.</p>').join()}</div></html>',200,headers:{Headers.contentTypeHeader:['text/html']});
 @override void close({bool force=false}){}
}
void main(){
 testWidgets('offline reader returns to a selected page and exact scroll position',(t)async{
  SharedPreferences.setMockInitialValues({});
  final marks=ReaderBookmarkService();
  await marks.add(documentId:'shamela:57',locationKind:'epub-spine',page:0,scrollOffset:310,label:'موضع أ');
  await marks.add(documentId:'shamela:57',locationKind:'epub-spine',page:1,scrollOffset:510,label:'موضع ب');
  final book=OfflineShamelaBook(id:57,title:'كتاب تجريبي',author:'',sourceUrl:'',downloadedAt:DateTime(2026),metadata:{},toc:[],pages:[for(var p=0;p<2;p++) OfflineShamelaPage(id:'p$p',path:'p$p.xhtml',title:'صفحة ${p+1}',text:List.filled(200,'نص اختبار للانتقال إلى موضع القراءة داخل الصفحة.').join('\n'))]);
  await t.pumpWidget(MaterialApp(home:ShamelaOfflineReaderScreen(book:book,epubService:FixtureService())));
  await t.pumpAndSettle();
  Future<void> choose(String label)async{
   await t.tap(find.byTooltip('العلامات المرجعية'));await t.pumpAndSettle();
   await t.tap(find.text(label));await t.pumpAndSettle();
  }
  await choose('موضع ب');
  final body=t.widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first);
  expect(body.controller!.offset,closeTo(510,1));
  expect(find.textContaining('الصفحة 2 من 2'),findsWidgets);
  await choose('موضع أ');
  expect(t.widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first).controller!.offset,closeTo(310,1));
  expect(find.textContaining('الصفحة 1 من 2'),findsWidgets);
  await choose('موضع أ');
  expect(t.widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first).controller!.offset,closeTo(310,1));
  expect(t.takeException(),isNull);
 });
 testWidgets('online reader restores saved online page and offset',(t)async{
  SharedPreferences.setMockInitialValues({});
  final marks=ReaderBookmarkService();
  await marks.add(documentId:'shamela:57',locationKind:'online-page',page:2,scrollOffset:400,label:'قراءة لاحقة');
  final dir=await t.runAsync(()=>Directory.systemTemp.createTemp('bookmark-online-'));
  addTearDown(()=>t.runAsync(()=>dir!.delete(recursive:true)));
  await t.pumpWidget(MaterialApp(home:ShamelaBookReaderScreen(bookId:57,bookTitle:'كتاب اختبار',initialPage:1,dio:Dio(BaseOptions(baseUrl:'https://shamela.ws'))..httpClientAdapter=LongPageAdapter(),rootDir:dir)));
  await finishIo(t);
  await t.tap(find.byTooltip('العلامات المرجعية'));await finishIo(t);await t.pumpAndSettle();
  await t.tap(find.text('قراءة لاحقة'));await finishIo(t);await t.pumpAndSettle();
  final scroll=t.widget<ListView>(find.byType(ListView).first);
  expect(scroll.controller!.offset,closeTo(400,1));
  expect(t.takeException(),isNull);
 });
 testWidgets('offline reader and marks at 2x text scale remain usable',(t)async{
  final font=Platform.environment['READING_TEST_FONT'] ?? (File('/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf').existsSync()?'/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf':null);
  final icons=Platform.environment['READING_TEST_ICON_FONT'] ?? (File('/home/sandbox/flutter-sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').existsSync()?'/home/sandbox/flutter-sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf':null);
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize=const Size(360,800);t.view.devicePixelRatio=1;
  addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  if(font!=null && icons!=null) await t.runAsync(()async{
   for(final entry in {'ArabicTest':font,'Amiri':font,'MaterialIcons':icons}.entries){
    await (FontLoader(entry.key)..addFont(Future.value(ByteData.sublistView(await File(entry.value).readAsBytes())))).load();
   }
  });
  await ReaderBookmarkService().add(documentId:'shamela:57',locationKind:'epub-spine',page:0,scrollOffset:120,label:'مراجعة الحفظ');
  final book=OfflineShamelaBook(id:57,title:'كتاب اختبار',author:'',sourceUrl:'',downloadedAt:DateTime(2026),metadata:{},toc:[],pages:[OfflineShamelaPage(id:'p',path:'p.xhtml',title:'صفحة اختبار',text:List.filled(60,'نص تجريبي لاختبار وضوح القارئ والعلامات المرجعية.').join(' '))]);
  final key=GlobalKey();
  await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData(fontFamily:'ArabicTest'),builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(2)),child:child!),home:ShamelaOfflineReaderScreen(book:book,epubService:FixtureService()))));
  await t.pumpAndSettle();expect(t.takeException(),isNull);
  Future<void> capture(String name)async{if(font==null||icons==null)return;await t.runAsync(()async{final image=await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);await File('/tmp/$name.png').writeAsBytes(data!.buffer.asUint8List());});}
  await capture('next-bookmark-reader-large');
  await t.tap(find.byTooltip('العلامات المرجعية'));await t.pumpAndSettle();expect(t.takeException(),isNull);
  await capture('next-bookmark-sheet-large');
  expect(find.text('مراجعة الحفظ'),findsOneWidget);
 });

}
