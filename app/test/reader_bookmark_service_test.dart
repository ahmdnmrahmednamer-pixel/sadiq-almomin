import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/reader_bookmark_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<ReaderBookmark> mark(ReaderBookmarkService s, {String doc='shamela:57',String kind='online-page',int page=15,double offset=0,String label='قراءة'}) => s.add(documentId:doc,locationKind:kind,page:page,scrollOffset:offset,label:label);
  test('multiple marks on same page persist independently across instances', () async {
    final a=await mark(ReaderBookmarkService(),offset:24,label:'حفظ');
    final b=await mark(ReaderBookmarkService(),offset:250,label:'قراءة');
    final list=await ReaderBookmarkService().list('shamela:57','online-page');
    expect(list.map((b)=>b.id),[a.id,b.id]);
    expect(list.map((b)=>b.scrollOffset),[24,250]);
    expect(list.map((b)=>b.label),['حفظ','قراءة']);
  });
  test('book and location-format boundaries cannot cross',() async {
    final s=ReaderBookmarkService();
    await mark(s);
    await mark(s,doc:'shamela:58');
    await mark(s,kind:'epub-spine');
    expect(await s.list('shamela:57','online-page'),hasLength(1));
    expect(await s.list('shamela:57','epub-spine'),hasLength(1));
    expect(await s.list('shamela:59','online-page'),isEmpty);
  });
  test('removing one mark keeps other marks on the same page',() async {
    final s=ReaderBookmarkService();
    final a=await mark(s);final b=await mark(s);
    await s.remove(a);
    expect((await s.list('shamela:57','online-page')).single.id,b.id);
  });
  test('concurrent writes from separate instances are serialized',() async {
    await Future.wait([for(var i=0;i<15;i++) mark(ReaderBookmarkService(),offset:i.toDouble())]);
    final marks=await ReaderBookmarkService().list('shamela:57','online-page');
    expect(marks,hasLength(15));expect(marks.map((b)=>b.id).toSet(),hasLength(15));
  });
  test('corrupt storage is not silently replaced when adding a mark',() async {
    SharedPreferences.setMockInitialValues({'reader_bookmarks_v1':'invalid json'});
    await expectLater(mark(ReaderBookmarkService()),throwsFormatException);
    expect((await SharedPreferences.getInstance()).getString('reader_bookmarks_v1'),'invalid json');
  });
  test('invalid coordinates do not persist',() async {
    final s=ReaderBookmarkService();
    await expectLater(mark(s,offset:double.nan),throwsArgumentError);
    await expectLater(mark(s,page:-1),throwsArgumentError);
    expect(await s.list('shamela:57','online-page'),isEmpty);
  });
}
