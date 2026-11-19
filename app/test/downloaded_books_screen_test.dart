import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../lib/features/library/islamic_library_screen.dart';
import '../lib/core/services/shamela_epub_service.dart';
import '../lib/features/library/downloaded_books_screen.dart';
import '../lib/features/library/shamela_offline_reader_screen.dart';
import 'shamela_epub_service_test.dart' show DownloadFixture;

final savedBook = OfflineShamelaBook(
  id: 555,
  title: 'كتاب تجريبي طويل الاسم لاختبار عرض الكتب المحمّلة',
  author: 'مؤلف تجريبي',
  sourceUrl: 'https://old.shamela.ws/index.php/book/555',
  downloadedAt: DateTime(2026, 11, 19),
  metadata: const {},
  pages: const [
    OfflineShamelaPage(id: 'one', path: 'one.xhtml', title: 'الأول', text: 'نص تجريبي للصفحة الأولى'),
    OfflineShamelaPage(id: 'two', path: 'two.xhtml', title: 'الثاني', text: 'نص تجريبي للصفحة الثانية'),
  ],
  toc: const [],
);
class ListService extends ShamelaEpubService {
  ListService(this.result);
  final Future<List<OfflineShamelaBook>> Function() result;
  @override Future<List<OfflineShamelaBook>> listSavedBooks() => result();
}
Future<void> finishIo(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 30));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  }
  await t.pumpAndSettle();
}
void main() {
  setUpAll(() async {
    final loader = FontLoader('Amiri')..addFont(rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('loading and empty states expose a clear Shamela entry', (t) async {
    final c = Completer<List<OfflineShamelaBook>>();
    await t.pumpWidget(MaterialApp(home: DownloadedBooksScreen(epubService: ListService(() => c.future))));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    c.complete([]);
    await t.pumpAndSettle();
    expect(find.text('لا توجد كتب محمّلة'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'المكتبة الشاملة'), findsOneWidget);
  });
  testWidgets('storage error is distinct from an empty library and retry works', (t) async {
    var failed = true;
    final s = ListService(() async { if (failed) throw const FileSystemException(); return []; });
    await t.pumpWidget(MaterialApp(home: DownloadedBooksScreen(epubService: s)));
    await t.pumpAndSettle();
    expect(find.text('تعذر فتح قائمة الكتب المحمّلة'), findsOneWidget);
    expect(find.text('لا توجد كتب محمّلة'), findsNothing);
    failed = false;
    await t.tap(find.text('إعادة المحاولة'));
    await t.pumpAndSettle();
    expect(find.text('لا توجد كتب محمّلة'), findsOneWidget);
  });
  testWidgets('saved book opens locally at its saved position with no network', (t) async {
    final dir = await t.runAsync(() => Directory.systemTemp.createTemp('reader-entry-'));
    addTearDown(() => dir!.delete(recursive: true));
    await t.runAsync(() async {
      final target = File('${dir!.path}/shamela/555/book.json');
      await target.parent.create(recursive: true);
      await target.writeAsString(jsonEncode(savedBook.toJson()));
    });
    final adapter = DownloadFixture()..offline = true;
    final service = ShamelaEpubService(rootDir: dir, dio: Dio()..httpClientAdapter = adapter);
    await service.saveLastPosition(555, 1);
    await t.pumpWidget(MaterialApp(home: DownloadedBooksScreen(epubService: service)));
    await finishIo(t);
    expect(find.text(savedBook.title), findsOneWidget);
    await t.tap(find.text(savedBook.title));
    await finishIo(t);
    expect(find.byType(ShamelaOfflineReaderScreen), findsOneWidget);
    expect(find.textContaining('نص تجريبي للصفحة الثانية'), findsWidgets);
    expect(adapter.calls, 0);
  });
  testWidgets('independent library and drawer entries reach local reader', (t) async {
    final service = ListService(() async => []);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const IslamicLibraryScreen()),
      GoRoute(path: '/downloaded-books', builder: (_, __) => DownloadedBooksScreen(epubService: service)),
    ]);
    addTearDown(router.dispose);
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('قارئ الكتب'));
    await t.tap(find.text('قارئ الكتب'));
    await t.pumpAndSettle();
    expect(find.byType(DownloadedBooksScreen), findsOneWidget);
    router.pop();
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('open navigation menu'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'قارئ الكتب');
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(Drawer), matching: find.byWidgetPredicate((w) => w is Text && w.data == 'قارئ الكتب')));
    await t.pumpAndSettle();
    expect(find.byType(DownloadedBooksScreen), findsOneWidget);
  });
  testWidgets('Arabic search, full titles and 2x phone layout', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await t.pumpWidget(RepaintBoundary(key: boundary, child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Amiri'),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)), child: child!),
      home: DownloadedBooksScreen(epubService: ListService(() async => [savedBook])),
    )));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    const path = String.fromEnvironment('SCREENSHOT_DIR');
    if (path.isNotEmpty) {
      await t.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$path/downloaded-reader-2x.png').writeAsBytes(data!.buffer.asUint8List());
      });
    }
    await t.enterText(find.byType(TextField), 'مُؤَلِّف');
    await t.pumpAndSettle();
    expect(find.text(savedBook.title), findsOneWidget);
    await t.enterText(find.byType(TextField), 'غير موجود');
    await t.pumpAndSettle();
    expect(find.text('لا توجد نتائج'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
