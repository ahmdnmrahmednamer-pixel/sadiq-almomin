import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/core/services/quran_search_service.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/features/search/quran_search_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Cairo', 'Amiri']) {
      final loader = FontLoader(family);
      for (final weight in ['Regular', 'Bold']) {
        final file = File('assets/fonts/$family-$weight.ttf');
        if (file.existsSync()) {
          loader.addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
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
  const hint =
      'تأكد من كتابة الكلمة بصورة صحيحة أو جرب البحث بكلمة واحدة أو بدون (ال) التعريف.';
  const query = 'كلمةاختبارلاوجودلها';
  for (final mode in AppThemeMode.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('empty state contrast ${mode.name} $scale', (tester) async {
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          SharedPreferences.setMockInitialValues({});
          QuranSearchService.resetCacheForTesting();
          await tester.runAsync(() async {
            await QuranRepository.loadSurahs();
            await QuranSearchService.instance.searchAyahs(query);
          });
          final theme = AppTheme.of(mode);
          final boundary = GlobalKey();
          await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: Directionality(
                    textDirection: TextDirection.rtl, child: child!),
              ),
              home: const QuranSearchScreen(),
            ),
          ));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), query);
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          final state =
              find.byKey(const ValueKey('search_no_results_scroll_view'));
          expect(state, findsOneWidget);
          final help = find.descendant(of: state, matching: find.text(hint));
          final icon = find.descendant(
              of: state, matching: find.byIcon(Icons.search_off));
          final title =
              find.descendant(of: state, matching: find.textContaining(query));
          expect(help, findsOneWidget);
          expect(icon, findsOneWidget);
          expect(title, findsOneWidget);
          expect(tester.widget<Text>(help).style!.fontSize, 13);
          expect(tester.widget<Text>(help).maxLines, isNull);
          expect(tester.getSemantics(help).label, hint);
          final rich =
              find.descendant(of: help, matching: find.byType(RichText));
          final paragraph = tester.renderObject<RenderParagraph>(rich);
          expect(paragraph.textScaler.scale(13), 13 * scale);
          expect(tester.widget<Icon>(icon).size, 64);
          final failures = <String>[];
          double ratio(Color fg, Color bg) {
            final a = Color.alphaBlend(fg, bg).computeLuminance();
            final b = bg.computeLuminance();
            return ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05);
          }

          final helpColor = tester.widget<Text>(help).style!.color!;
          final iconColor = tester.widget<Icon>(icon).color!;
          final background = theme.scaffoldBackgroundColor;
          final helpRatio = ratio(helpColor, background);
          final iconRatio = ratio(iconColor, background);
          if (helpRatio < 4.5) failures.add('Hint contrast $helpRatio < 4.5');
          if (iconRatio < 3) failures.add('Icon contrast $iconRatio < 3');
          final h = tester.getRect(help), i = tester.getRect(icon);
          expect(h.left, greaterThanOrEqualTo(0));
          expect(h.right, lessThanOrEqualTo(360));
          expect(h.bottom, lessThanOrEqualTo(900));
          expect(i.bottom, lessThanOrEqualTo(h.top));
          final dir = Platform.environment['SEARCH_EMPTY_PIXELS'];
          if (dir != null) {
            await tester.runAsync(() async {
              Directory(dir).createSync(recursive: true);
              final image = await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              File('$dir/${mode.name}-$scale.png')
                  .writeAsBytesSync(bytes!.buffer.asUint8List());
              File('$dir/${mode.name}-$scale.metrics.txt').writeAsStringSync(
                  'hint=$helpRatio icon=$iconRatio\nhintRect=$h\niconRect=$i\n');
              image.dispose();
            });
          }
          final error = tester.takeException();
          if (error != null) failures.add('$error');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(failures, isEmpty, reason: failures.join('\n'));
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}
