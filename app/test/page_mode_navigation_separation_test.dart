import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:almomin/core/gestures/ayah_gesture_recognizer.dart';
import 'package:flutter/services.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/mushaf/page_mode_mushaf_screen.dart';

final _boundary = GlobalKey();
Future<void> _capture(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('PAGE_NAV_PIXEL_DIR');
  if (directory.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(directory).createSync(recursive: true);
      File('$directory/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const iconsPath = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (iconsPath.isNotEmpty) {
      final bytes = File(iconsPath).readAsBytesSync();
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
    for (final family in ['Cairo', 'Roboto', 'Amiri']) {
      final path = family == 'Amiri'
          ? 'assets/fonts/Amiri-Regular.ttf'
          : 'assets/fonts/Cairo-Regular.ttf';
      final bytes = File(path).readAsBytesSync();
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  });
  for (final width in [360.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('page navigation reserves body space at $width and $scale',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        SharedPreferences.setMockInitialValues({});
        await SettingsService.instance.init(forceReload: true);
        await tester.runAsync(() async {
          await QuranRepository.loadSurahs();
          await QuranRepository.getAyahsForPage(293);
          await QuranRepository.getPageMetadata(293);
        });
        await tester.pumpWidget(RepaintBoundary(
            key: _boundary,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightTheme,
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: Directionality(
                        textDirection: TextDirection.rtl, child: child!)),
                home: const PageModeMushafScreen(initialPage: 293))));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final nav = find.text('صفحة ٢٩٣ من ٦٠٤');
        expect(nav, findsOneWidget);
        final previous = find.byTooltip('الصفحة السابقة');
        final next = find.byTooltip('الصفحة التالية');
        final navigationTop = [
          tester.getRect(previous).top,
          tester.getRect(next).top,
          tester.getRect(nav).top
        ].reduce((a, b) => a < b ? a : b);
        final scroll = find.descendant(
            of: find.byType(PageView),
            matching: find.byType(SingleChildScrollView));
        final ornament = find.text('﴿ ٢٩٣ ﴾');
        expect(scroll, findsOneWidget);
        expect(ornament, findsOneWidget);
        expect(tester.getRect(scroll).bottom, lessThanOrEqualTo(navigationTop),
            reason:
                'Visible text viewport must end above page navigation, not behind it');
        expect(
            tester.getRect(ornament).bottom, lessThanOrEqualTo(navigationTop),
            reason: 'Page ornament must not sit behind page navigation');
        await tester.drag(scroll, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.getRect(scroll).bottom, lessThanOrEqualTo(navigationTop));
        expect(tester.takeException(), isNull);
        await tester.drag(scroll, const Offset(0, -5000));
        await tester.pumpAndSettle();
        final paragraphFinder = find.descendant(
            of: find.byType(PageView),
            matching: find.byWidgetPredicate((widget) =>
                widget is RichText &&
                widget.text is TextSpan &&
                ((widget.text as TextSpan).children?.any((span) =>
                        span is TextSpan &&
                        span.recognizer is AyahGestureRecognizer) ??
                    false)));
        expect(paragraphFinder, findsWidgets);
        final paragraph =
            tester.renderObject<RenderParagraph>(paragraphFinder.last);
        final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
        final lastBoxes = paragraph.getBoxesForSelection(TextSelection(
            baseOffset: text.length - 3, extentOffset: text.length));
        expect(lastBoxes, isNotEmpty);
        final viewport = tester.getRect(scroll);
        for (final box in lastBoxes) {
          final rect = box.toRect().shift(paragraph.localToGlobal(Offset.zero));
          expect(rect.top, greaterThanOrEqualTo(viewport.top - 0.5));
          expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + 0.5),
              reason: 'Last verse number must be reachable above navigation');
        }
        await _capture(tester, '${width}_${scale}_last');
        final shownHeight = tester.getSize(find.byType(PageView)).height;
        await tester.tap(ornament);
        await tester.pumpAndSettle();
        expect(nav, findsNothing);
        await _capture(tester, '${width}_${scale}_hidden');
        expect(tester.getSize(find.byType(PageView)).height,
            greaterThan(shownHeight));
        await tester.tap(find.text('الجزء ١٥'));
        await tester.pumpAndSettle();
        expect(nav, findsOneWidget);
        expect(tester.getSize(find.byType(PageView)).height, shownHeight);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
