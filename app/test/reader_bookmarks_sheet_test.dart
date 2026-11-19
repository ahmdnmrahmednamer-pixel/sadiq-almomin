import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/reader_bookmark_service.dart';
import '../lib/features/library/widgets/reader_bookmarks_sheet.dart';

void main(){
  testWidgets('bookmarks sheet creates distinct marks and returns the chosen location',(t)async{
    SharedPreferences.setMockInitialValues({});
    ReaderBookmark? selected;
    await t.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()async{
      selected=await showReaderBookmarks(context,documentId:'shamela:57',locationKind:'epub-spine',page:4,scrollOffset:123,pageLabel:'الصفحة 5');
    },child:const Text('العلامات'))))));
    await t.tap(find.text('العلامات'));await t.pumpAndSettle();
    expect(find.text('لا توجد علامات'),findsOneWidget);
    for(final label in ['حفظ','مراجعة']){
      await t.tap(find.text('إضافة الموضع الحالي'));await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField),label);
      await t.tap(find.text('حفظ').last);await t.pumpAndSettle();
    }
    final marks=await ReaderBookmarkService().list('shamela:57','epub-spine');
    expect(marks,hasLength(2));expect(marks.map((b)=>b.label),['حفظ','مراجعة']);
    await t.tap(find.text('مراجعة'));await t.pumpAndSettle();
    expect(selected!.page,4);expect(selected!.scrollOffset,123);
    expect(selected!.label,'مراجعة');expect(t.takeException(),isNull);
  });
}
