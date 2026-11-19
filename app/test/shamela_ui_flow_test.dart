import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/shamela_epub_service.dart';
import '../lib/core/services/shamela_library_service.dart';
import '../lib/features/library/shamela_library_screen.dart';
import 'shamela_epub_service_test.dart' show DownloadFixture;
import 'shamela_library_service_test.dart' show FixtureAdapter;

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
      'Search, source-filter, download, open, advance, and relist saved book through UI',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final dir = await t
        .runAsync(() => Directory.systemTemp.createTemp('shamela-ui-flow-'));
    addTearDown(() => dir!.delete(recursive: true));
    final adapter = DownloadFixture();
    final service = ShamelaEpubService(
        dio: Dio()..httpClientAdapter = adapter, rootDir: dir);
    final search =
        ShamelaLibraryService(dio: Dio()..httpClientAdapter = FixtureAdapter());
    await t.pumpWidget(MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: ShamelaLibraryScreen(
            libraryService: search, epubService: service)));
    await finishIo(t);
    await t.enterText(find.byType(TextField).first, 'صحيح');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await finishIo(t);
    expect(find.text('صحيح ابن خزيمة'), findsOneWidget);
    final download = find.text('تنزيل أوفلاين');
    await t.ensureVisible(download);
    await t.tap(download);
    await finishIo(t);
    expect(find.byTooltip('الفهرس'), findsOneWidget);
    expect(find.textContaining('بِسْمِ اللَّهِ'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    adapter.offline = true;
    final networkCalls = adapter.calls;
    await t.tap(find.text('التالي'));
    await t.pumpAndSettle();
    expect(find.textContaining('الصفحة الثانية'), findsWidgets);
    expect(adapter.calls, networkCalls);
    await t.pageBack();
    await finishIo(t);
    await t.tap(find.text('كتبي المحفوظة'));
    await finishIo(t);
    expect(find.text('صحيح ابن خزيمة'), findsOneWidget);
    final exists = await t
        .runAsync(() => File('${dir!.path}/shamela/1446/book.epub').exists());
    expect(exists, true);
    expect(t.takeException(), isNull);
  });
}
