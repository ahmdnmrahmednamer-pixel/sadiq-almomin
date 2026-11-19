import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/features/library/shamela_book_reader_screen.dart';

class PageAdapter implements HttpClientAdapter {
  final bool offline;
  final bool missingContent;
  PageAdapter({this.offline = false, this.missingContent = false});
  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? s, Future<dynamic>? c) async {
    if (offline)
      throw DioException.connectionError(
          requestOptions: o, reason: 'test offline');
    return ResponseBody.fromString(
        missingContent
            ? '<html><title>Unavailable</title></html>'
            : '<html><title>كتاب اختبار ج 2 ص 17</title><nav>MENU_EXCLUDED</nav><div class="nass">FIRST_DIRECT<p>SECOND_PARAGRAPH</p><div>THIRD_BLOCK<br>FOURTH_LINE</div><p>FIFTH_FOOTNOTE</p><script>ACTIVE_EXCLUDED</script></div></html>',
        200,
        headers: {
          Headers.contentTypeHeader: ['text/html']
        });
  }

  @override
  void close({bool force = false}) {}
}

Future<void> finishIo(WidgetTester t) async {
  for (var i = 0; i < 30; i++) {
    await t.pump(const Duration(milliseconds: 30));
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  }
  await t.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets(
      'Online DOM content stays in source order and cached page reopens offline',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final dir = await t.runAsync(
        () => Directory.systemTemp.createTemp('shamela-online-test-'));
    addTearDown(() => dir!.delete(recursive: true));
    Future<void> open(bool offline) async {
      final dio = Dio(BaseOptions(baseUrl: 'https://shamela.ws'))
        ..httpClientAdapter = PageAdapter(offline: offline);
      await t.pumpWidget(MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: ShamelaBookReaderScreen(
              key: UniqueKey(),
              bookId: 42,
              bookTitle: 'كتاب اختبار',
              initialPage: 1,
              dio: dio,
              rootDir: dir)));
      await finishIo(t);
    }

    await open(false);
    final files = await t.runAsync(() => dir!
        .list(recursive: true)
        .where((e) => e is File)
        .cast<File>()
        .toList());
    expect(files, isNotEmpty);
    final raw = await t.runAsync(() => files!.single.readAsString());
    final cache = jsonDecode(raw!) as Map<String, dynamic>;
    final text = (cache['paragraphs'] as List).join('\n');
    final tokens = [
      'FIRST_DIRECT',
      'SECOND_PARAGRAPH',
      'THIRD_BLOCK',
      'FOURTH_LINE',
      'FIFTH_FOOTNOTE'
    ];
    for (var i = 0; i < tokens.length; i++) {
      expect(text, contains(tokens[i]));
      if (i > 0)
        expect(
            text.indexOf(tokens[i]), greaterThan(text.indexOf(tokens[i - 1])));
    }
    expect(text, isNot(contains('MENU_EXCLUDED')));
    expect(text, isNot(contains('ACTIVE_EXCLUDED')));
    expect(cache['part'], '2');
    expect(cache['pageInPart'], '17');
    expect(cache['bookId'], 42);
    await open(true);
    expect(find.textContaining('FIRST_DIRECT'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('Missing source content is not saved as a successful page',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final dir = await t
        .runAsync(() => Directory.systemTemp.createTemp('shamela-empty-test-'));
    addTearDown(() => dir!.delete(recursive: true));
    final dio = Dio(BaseOptions(baseUrl: 'https://shamela.ws'))
      ..httpClientAdapter = PageAdapter(missingContent: true);
    await t.pumpWidget(MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: ShamelaBookReaderScreen(
            bookId: 42,
            bookTitle: 'اختبار',
            initialPage: 1,
            dio: dio,
            rootDir: dir)));
    await finishIo(t);
    final files = await t.runAsync(
        () => dir!.list(recursive: true).where((e) => e is File).toList());
    expect(files, isEmpty);
    expect(t.takeException(), isNull);
  });
  testWidgets('Wrong-book cached page is rejected while offline', (t) async {
    SharedPreferences.setMockInitialValues({});
    final dir = await t.runAsync(
        () => Directory.systemTemp.createTemp('shamela-mismatch-test-'));
    addTearDown(() => dir!.delete(recursive: true));
    await t.runAsync(() async {
      final folder = Directory('${dir!.path}/shamela_cache/42');
      await folder.create(recursive: true);
      await File('${folder.path}/page_1.json').writeAsString(jsonEncode({
        'bookId': 43,
        'pageId': 1,
        'paragraphs': ['WRONG_BOOK_SENTINEL']
      }));
    });
    final dio = Dio(BaseOptions(baseUrl: 'https://shamela.ws'))
      ..httpClientAdapter = PageAdapter(offline: true);
    await t.pumpWidget(MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: ShamelaBookReaderScreen(
            bookId: 42,
            bookTitle: 'اختبار',
            initialPage: 1,
            dio: dio,
            rootDir: dir)));
    await finishIo(t);
    expect(find.textContaining('WRONG_BOOK_SENTINEL'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
