import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/services/bundled_tafsir_source.dart';
import 'package:almomin/features/mushaf/widgets/tafsir_book_sections_sheet.dart';
void main(){
 final fixture={'bookId':3,'sections':[{'id':'intro','title':'مقدمة','pages':[{'id':1,'text':'نص المقدمة الأول','textFormat':'plain'},{'id':2,'text':'نص المقدمة الثاني','textFormat':'plain'}]},{'id':'principles','title':'أصول التفسير','pages':[{'id':3,'text':'نص الأصول','textFormat':'plain'}]}]};
 BundledTafsirSource sourceFor(dynamic data,{bool validHash=true}){
  final bytes=utf8.encode(jsonEncode(data));final packed=base64Encode(GZipEncoder().encode(bytes));final manifest={'edition':'fixture','book':{'id':3},'surahs':{},'bookSections':{'parts':1,'sha256':validHash?sha256.convert(bytes).toString():'wrong'}};
  return BundledTafsirSource(readAsset:(p)async=>p.endsWith('manifest.json')?jsonEncode(manifest):packed);
 }
 test('sections retain source order and are not ayah attributions',()async{
  final sections=await sourceFor(fixture).bookSections('fixture');expect(sections.map((s)=>s.id),['intro','principles']);expect(sections.first.pages.map((p)=>p.sourceId),[1,2]);expect(sections.first.pages.first.text,'نص المقدمة الأول');expect(sections.expand((s)=>s.pages).every((p)=>p.verseIds.isEmpty),isTrue);
 });
 test('checksum, identity, duplicate section/page and empty text fail closed',()async{
  Future<void> fails(void Function(dynamic)change,{bool validHash=true})async{final d=jsonDecode(jsonEncode(fixture));change(d);await expectLater(sourceFor(d,validHash:validHash).bookSections('fixture'),throwsFormatException);}
  await fails((d){},validHash:false);await fails((d)=>d['bookId']=99);await fails((d)=>d['sections'][1]['id']='intro');await fails((d)=>d['sections'][1]['pages'][0]['id']=1);await fails((d)=>d['sections'][0]['pages']=[]);await fails((d)=>d['sections'][0]['pages'][0]['text']='');
 });
 test('old manifest without sections remains compatible',()async{
  final source=BundledTafsirSource(readAsset:(p)async=>jsonEncode({'edition':'fixture','book':{'id':3},'surahs':{}}));expect(await source.bookSections('fixture'),isEmpty);
 });
 testWidgets('page boundaries and section changes reset position',(t)async{
  final sections=await sourceFor(fixture).bookSections('fixture');await t.pumpWidget(MaterialApp(home:Scaffold(body:TafsirBookSectionsSheet(bookName:'كتاب الاختبار',loadSections:()async=>sections))));await t.pumpAndSettle();expect(find.text('نص المقدمة الأول'),findsOneWidget);expect(find.text('1 من 2'),findsOneWidget);
  await t.tap(find.text('التالي'));await t.pumpAndSettle();expect(find.text('نص المقدمة الثاني'),findsOneWidget);await t.tap(find.byType(DropdownButtonFormField<int>));await t.pumpAndSettle();await t.tap(find.text('أصول التفسير').last);await t.pumpAndSettle();expect(find.text('نص الأصول'),findsOneWidget);expect(find.text('1 من 1'),findsOneWidget);expect(t.takeException(),isNull);
 });
 testWidgets('retry handles immediate and synchronous failures without fallback',(t)async{
  var calls=0;await t.pumpWidget(MaterialApp(home:Scaffold(body:TafsirBookSectionsSheet(bookName:'كتاب الاختبار',loadSections:(){calls++;if(calls==1)return Future.error(const FormatException('async'));throw const FormatException('sync');}))));await t.pumpAndSettle();expect(find.text('تعذر قراءة أقسام الكتاب. لا يعرض نص بديل.'),findsOneWidget);await t.tap(find.text('إعادة المحاولة'));await t.pumpAndSettle();expect(calls,2);expect(t.takeException(),isNull);
 });
 testWidgets('narrow reader permits larger text and keeps navigation visible',(t)async{
  t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);final sections=await sourceFor(fixture).bookSections('fixture');await t.pumpWidget(MaterialApp(builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:const TextScaler.linear(2)),child:w!),home:Scaffold(body:TafsirBookSectionsSheet(bookName:'كتاب الاختبار',loadSections:()async=>sections))));await t.pumpAndSettle();expect(find.text('التالي'),findsOneWidget);expect(t.takeException(),isNull);
 });
}
