import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/quran_search_service.dart';
import 'package:almomin/features/search/quran_search_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Cairo')
          ..addFont(rootBundle.load('assets/fonts/Cairo-Regular.ttf')))
        .load();
    final icons = Platform.environment['MATERIAL_ICONS_FONT'];
    if (icons != null)
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
  });
  test('explicit history clear survives preference reload and repeated clear',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = QuranSearchService.instance;
    expect(await service.getSearchHistory(), hasLength(5));
    await service.addToHistory('بحث محفوظ');
    await service.clearHistory();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(await service.getSearchHistory(), isEmpty);
    await service.clearHistory();
    await prefs.reload();
    expect(await service.getSearchHistory(), isEmpty);
    await service.addToHistory('بحث جديد');
    expect(await service.getSearchHistory(), ['بحث جديد']);
    await service.removeFromHistory('بحث جديد');
    await prefs.reload();
    expect(await service.getSearchHistory(), isEmpty);
  });
  test(
      'clear untouched history stays empty and new entries keep dedup order and cap',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = QuranSearchService.instance;
    await service.clearHistory();
    await (await SharedPreferences.getInstance()).reload();
    expect(await service.getSearchHistory(), isEmpty);
    for (var i = 0; i < 25; i++) {
      await service.addToHistory('query $i');
    }
    await service.addToHistory('query 10');
    final history = await service.getSearchHistory();
    expect(history, hasLength(20));
    expect(history.first, 'query 10');
    expect(history.toSet(), hasLength(20));
    expect(history, isNot(contains('query 0')));
    await service.addToHistory(' ');
    await service.addToHistory('x');
    expect(await service.getSearchHistory(), history);
  });
  testWidgets(
      'cleared history stays hidden after reopening while suggestions remain',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'quran_search_history_v1': <String>['بحث محفوظ']
    });
    tester.view.physicalSize = const Size(412, 950);
    tester.view.devicePixelRatio = 1;
    final boundary = GlobalKey();
    Future<void> open() async {
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Cairo'),
              home: const QuranSearchScreen())));
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      final dir = Platform.environment['SEARCH_HISTORY_PIXELS'];
      if (dir == null) return;
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    try {
      await open();
      expect(find.text('سجل البحث الأخير'), findsOneWidget);
      expect(find.text('بحث محفوظ'), findsOneWidget);
      await capture('saved');
      await tester.tap(find.text('مسح السجل'));
      await tester.pumpAndSettle();
      expect(find.text('سجل البحث الأخير'), findsNothing);
      expect(find.text('عمليات بحث مقترحة'), findsOneWidget);
      await capture('cleared');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await (await SharedPreferences.getInstance()).reload();
      await open();
      await capture('reopened');
      expect(find.text('سجل البحث الأخير'), findsNothing);
      expect(find.byType(InputChip), findsNothing);
      expect(find.text('عمليات بحث مقترحة'), findsOneWidget);
      expect(find.byType(ActionChip), findsNWidgets(8));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
