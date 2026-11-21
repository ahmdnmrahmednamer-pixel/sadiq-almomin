import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/features/search/quran_search_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('clear retires an already scheduled search debounce at $scale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader('Cairo')
            ..addFont(Future.value(ByteData.sublistView(
                File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync()))))
          .load();
      const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
      if (icons.isNotEmpty)
        await (FontLoader('MaterialIcons')
              ..addFont(Future.value(
                  ByteData.sublistView(File(icons).readAsBytesSync()))))
            .load();
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Cairo'),
              builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(c)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: const QuranSearchScreen(initialQuery: 'الرحمن'))));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      final input = find.byType(TextField);
      await tester.enterText(input, 'الصمد');
      await tester.tap(find.byTooltip('إغلاق أو مسح'));
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      expect(find.text('سجل البحث الأخير'), findsOneWidget,
          reason:
              'Clearing must keep history visible, not restart the retired typed query');
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      const directory = String.fromEnvironment('SEARCH_SESSION_PIXELS');
      if (directory.isNotEmpty)
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$directory/cleared-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
