import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/core/services/quran_search_service.dart';
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
  for (final mode in AppThemeMode.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('result text and actions contrast ${mode.name} $scale',
          (tester) async {
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final theme = AppTheme.of(mode);
        final boundary = GlobalKey();
        final failures = <String>[];
        double ratio(Color a, Color b) {
          final x = a.computeLuminance(), y = b.computeLuminance();
          return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
        }

        void check(Color fg, Color bg, String label, [double min = 4.5]) {
          final value = ratio(Color.alphaBlend(fg, bg), bg);
          if (value < min)
            failures.add('$label: ${value.toStringAsFixed(2)} < $min');
        }

        Color textColor(Finder finder) {
          final element = finder.first.evaluate().single;
          final widget = element.widget as Text;
          return widget.style?.color ??
              DefaultTextStyle.of(element).style.color!;
        }

        Future<void> capture(String state) async {
          final dir = Platform.environment['SEARCH_CONTRAST_PIXELS'];
          if (dir == null) return;
          await tester.runAsync(() async {
            Directory(dir).createSync(recursive: true);
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            File('$dir/$state-${mode.name}-$scale.png')
                .writeAsBytesSync(data!.buffer.asUint8List());
            image.dispose();
          });
        }

        Future<void> search(String query) async {
          await tester.enterText(find.byType(TextField), query);
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pump();
          await tester.pumpAndSettle();
        }

        // Load real Quran data before entering the fake-clock widget phase.
        await tester.runAsync(() async {
          await QuranRepository.loadSurahs();
          await QuranSearchService.instance.searchAyahs('الفلق');
        });
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
        await search('الفلق');
        expect(find.textContaining('نتائج السور ('), findsOneWidget);
        expect(find.textContaining('نتائج الآيات ('), findsOneWidget);
        final bg = theme.scaffoldBackgroundColor;
        final card = theme.cardTheme.color!;
        for (final prefix in ['نتائج السور (', 'نتائج الآيات (']) {
          check(textColor(find.textContaining(prefix)), bg, prefix);
        }
        final avatar = tester.widget<CircleAvatar>(find.ancestor(
            of: find.text('113'), matching: find.byType(CircleAvatar)));
        check(textColor(find.text('113')),
            Color.alphaBlend(avatar.backgroundColor!, card), 'surah number');
        final badge = find.byWidgetPredicate((w) =>
            w is Text &&
            (w.data?.startsWith('سورة ') ?? false) &&
            (w.data?.contains(' : آية ') ?? false));
        expect(badge, findsOneWidget);
        // Badge backgrounds are read from the actual rendered decoration.
        final badgeContainer = tester
            .widgetList<Container>(
                find.ancestor(of: badge, matching: find.byType(Container)))
            .firstWhere((w) =>
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color != null);
        final badgeBg = Color.alphaBlend(
            (badgeContainer.decoration as BoxDecoration).color!, card);
        check(textColor(badge), badgeBg, 'ayah badge');
        check(textColor(find.textContaining(' · جزء ')), card, 'ayah metadata');
        final verse = tester
            .widgetList<RichText>(find.byType(RichText))
            .singleWhere((w) => w.text.toPlainText().contains('﴿'));
        final root = verse.text as TextSpan;
        var highlights = 0;
        for (final span in root.children!.cast<TextSpan>()) {
          if (span.style?.backgroundColor != null) {
            highlights++;
            check(
                span.style!.color!,
                Color.alphaBlend(span.style!.backgroundColor!, card),
                'matched word');
          } else if (span.style?.color != null) {
            check(span.style!.color!, card, 'ayah marker');
          }
        }
        expect(highlights, greaterThan(0));
        check(root.style!.color!, card, 'ayah body');
        await capture('results-top');
        await tester.drag(find.byType(ListView), const Offset(0, -500));
        await tester.pumpAndSettle();
        for (final label in ['التفسير', 'المصحف']) {
          final finder = find.text(label);
          expect(finder, findsOneWidget);
          check(textColor(finder), card, 'result action $label');
          final button = tester.widget<TextButton>(find.ancestor(
              of: finder,
              matching: find.byWidgetPredicate((w) => w is TextButton)));
          expect(button.onPressed, isNotNull);
        }
        for (final tooltip in ['نسخ الآية', 'مشاركة الآية']) {
          final button = tester.widget<IconButton>(find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == tooltip));
          expect(button.onPressed, isNotNull);
          check((button.icon as Icon).color!, card, tooltip, 3);
        }
        await capture('results-actions');
        if (scale == 1.0) {
          final filter = tester.widget<PopupMenuButton<int?>>(
              find.byType(PopupMenuButton<int?>));
          filter.onSelected!(113);
          await tester.pumpAndSettle();
          final label = find.text('مصفى حسب السورة');
          expect(label, findsOneWidget);
          final chip = tester
              .widgetList<Container>(
                  find.ancestor(of: label, matching: find.byType(Container)))
              .firstWhere((w) =>
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).color != null);
          check(
              textColor(label),
              Color.alphaBlend((chip.decoration as BoxDecoration).color!, bg),
              'active surah filter');
          await capture('filtered');
        }
        await search('113:1');
        final title = find.byWidgetPredicate((w) =>
            w is Text &&
            (w.data?.startsWith('الفلق ') ?? false) &&
            (w.data?.endsWith('آية 1') ?? false));
        expect(title, findsOneWidget);
        final decorated = tester
            .widgetList<Container>(
                find.ancestor(of: title, matching: find.byType(Container)))
            .firstWhere((w) =>
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).gradient != null);
        final gradient =
            (decorated.decoration as BoxDecoration).gradient! as LinearGradient;
        final pageLabel = find.text('صفحة 604');
        final pageContainer = tester
            .widgetList<Container>(
                find.ancestor(of: pageLabel, matching: find.byType(Container)))
            .firstWhere((w) =>
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color != null);
        check(textColor(pageLabel),
            (pageContainer.decoration as BoxDecoration).color!, 'page badge');
        final openLabel = find.text('فتح في المصحف');
        final openButton = tester.widget<ElevatedButton>(find.ancestor(
            of: openLabel,
            matching: find.byWidgetPredicate((w) => w is ElevatedButton)));
        expect(openButton.onPressed, isNotNull);
        check(textColor(openLabel),
            openButton.style!.backgroundColor!.resolve({})!, 'open button');
        for (var step = 0; step <= 10; step++) {
          final tint = Color.lerp(
              gradient.colors.first, gradient.colors.last, step / 10)!;
          final background = Color.alphaBlend(tint, bg);
          check(textColor(title), background, 'reference title');
          check(textColor(find.text('مرجع مباشر: 113:1')), background,
              'reference metadata');
          check(
              textColor(find.text('التفسير')), background, 'reference action');
          check(textColor(find.textContaining('﴿')), background,
              'reference verse');
        }
        await capture('reference');
        await tester.drag(find.byType(ListView), const Offset(0, -500));
        await tester.pumpAndSettle();
        await capture('reference-actions');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(failures, isEmpty, reason: failures.join('\n'));
      });
    }
  }
}
