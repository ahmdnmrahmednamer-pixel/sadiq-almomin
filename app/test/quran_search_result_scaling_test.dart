import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/core/services/quran_search_service.dart';
import 'package:almomin/features/search/quran_search_screen.dart';

class GentleNonlinearScaler extends TextScaler {
  const GentleNonlinearScaler();
  @override
  double scale(double fontSize) =>
      fontSize <= 16 ? fontSize * 1.8 : fontSize + 12.8;
  @override
  double get textScaleFactor => 1.8;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Cairo', 'Amiri']) {
      final loader = FontLoader(family);
      for (final weight in ['Regular', 'Bold']) {
        final file = File('assets/fonts/$family-$weight.ttf');
        if (file.existsSync())
          loader.addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())));
      }
      await loader.load();
    }
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty) {
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
    }
  });
  final cases = [
    for (final mode in AppThemeMode.values)
      for (final scale in [1.0, 2.0])
        (
          name: '${mode.name}-$scale',
          mode: mode,
          scaler: TextScaler.linear(scale)
        ),
    (
      name: 'dark-nonlinear',
      mode: AppThemeMode.dark,
      scaler: const GentleNonlinearScaler()
    ),
  ];
  for (final item in cases) {
    testWidgets(
        'Quran results use host scaler and keep long verse scrollable ${item.name}',
        (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final rows = <String, String>{};
      await tester.runAsync(() async {
        for (final query in ['الفلق', 'تداينتم']) {
          final results = await QuranSearchService.instance.searchAyahs(query);
          expect(results, hasLength(1));
          rows[query] = results.single.ayah.cleanTextUthmani;
        }
        await SharedPreferences.getInstance();
      });
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.of(item.mode),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: item.scaler),
              child: Directionality(
                  textDirection: TextDirection.rtl, child: child!),
            ),
            home: const QuranSearchScreen(),
          )));
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        final dir = Platform.environment['SEARCH_SCALE_PIXELS'];
        if (dir == null) return;
        await tester.runAsync(() async {
          Directory(dir).createSync(recursive: true);
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/$name-${item.name}.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      String normalized(String text) =>
          text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final failures = <String>[];
      for (final query in ['الفلق', 'تداينتم']) {
        await tester.enterText(find.byType(TextField), query);
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        // Compare both source versions from the same top-of-results viewport.
        final scroll = tester.state<ScrollableState>(find.descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable)));
        scroll.position.jumpTo(0);
        await tester.pumpAndSettle();
        final verse = find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText().contains('﴿'));
        expect(verse, findsOneWidget);
        final rich = tester.widget<RichText>(verse);
        final paragraph = tester.renderObject<RenderParagraph>(verse);
        final font = (rich.text as TextSpan).style!.fontSize!;
        expect(normalized(rich.text.toPlainText()),
            contains(normalized(rows[query]!)));
        expect(paragraph.maxLines, isNull);
        final expected = item.scaler.scale(font);
        final actual = paragraph.textScaler.scale(font);
        if ((actual - expected).abs() > .0001)
          failures.add('$query: expected $expected, actual $actual');
        await capture(query == 'الفلق' ? 'short' : 'long-top');
        final copy = find.byWidgetPredicate(
            (w) => w is IconButton && w.tooltip == 'نسخ الآية');
        expect(copy, findsOneWidget);
        await tester.ensureVisible(copy);
        await tester.pumpAndSettle();
        final viewport = tester.getRect(find.byType(ListView));
        final action = tester.getRect(copy);
        expect(action.top, greaterThanOrEqualTo(viewport.top - .5));
        expect(action.bottom, lessThanOrEqualTo(viewport.bottom + .5));
        expect(tester.widget<IconButton>(copy).onPressed, isNotNull);
        if (query == 'تداينتم') await capture('long-actions');
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }
}
