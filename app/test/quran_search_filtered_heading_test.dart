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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Cairo', 'Amiri']) {
      final loader = FontLoader(family);
      final regular = File('assets/fonts/$family-Regular.ttf');
      expect(regular.existsSync(), isTrue,
          reason: 'Required registered app font');
      loader.addFont(
          Future.value(ByteData.sublistView(regular.readAsBytesSync())));
      final bold = File('assets/fonts/$family-Bold.ttf');
      if (bold.existsSync())
        loader.addFont(
            Future.value(ByteData.sublistView(bold.readAsBytesSync())));
      await loader.load();
    }
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty) {
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
    }
    for (final sample in [
      (query: 'الفلق', id: 113, count: 1),
      (query: 'الله', id: 2, count: 100)
    ]) {
      final results = await QuranSearchService.instance
          .searchAyahs(sample.query, surahFilter: sample.id);
      expect(results, hasLength(sample.count));
      expect(results.every((r) => r.surah.id == sample.id), isTrue);
    }
  });
  for (final mode in AppThemeMode.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'filtered heading fits and preserves meaning ${mode.name} $scale',
          (tester) async {
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final semantics = tester.ensureSemantics();
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.of(mode),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: Directionality(
                    textDirection: TextDirection.rtl, child: child!),
              ),
              home: const QuranSearchScreen(),
            )));
        await tester.pumpAndSettle();
        final failures = <String>[];
        for (final sample in [
          (query: 'الفلق', id: 113, count: 1),
          (query: 'الله', id: 2, count: 100)
        ]) {
          final filter = tester.widget<PopupMenuButton<int?>>(
              find.byType(PopupMenuButton<int?>));
          filter.onSelected!(sample.id);
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), sample.query);
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          final scroll = tester.state<ScrollableState>(find.descendant(
              of: find.byType(ListView), matching: find.byType(Scrollable)));
          scroll.position.jumpTo(0);
          await tester.pumpAndSettle();
          final error = tester.takeException();
          if (error != null) failures.add('${sample.count}: $error');
          final heading = find.text('نتائج الآيات (${sample.count})');
          final badge = find.text('مصفى حسب السورة');
          expect(heading, findsOneWidget);
          expect(badge, findsOneWidget);
          expect(
              tester
                  .widget<PopupMenuButton<int?>>(
                      find.byType(PopupMenuButton<int?>))
                  .initialValue,
              sample.id);
          expect(tester.getSemantics(heading).label,
              contains('نتائج الآيات (${sample.count})'));
          expect(tester.getSemantics(badge).label, contains('مصفى حسب السورة'));
          final viewport = tester.getRect(find.byType(ListView));
          for (final target in [heading, badge]) {
            final rect = tester.getRect(target);
            if (rect.left < viewport.left + 16 - .5 ||
                rect.right > viewport.right - 16 + .5)
              failures
                  .add('${sample.count}: label exceeds padded viewport: $rect');
            final paragraph = tester.renderObject<RenderParagraph>(target);
            expect(paragraph.maxLines, isNull);
            expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
          }
          if (scale == 2 &&
              tester.getRect(badge).top < tester.getRect(heading).bottom)
            failures.add(
                '${sample.count}: active filter did not wrap below the heading');
          final dir = Platform.environment['SEARCH_HEADING_PIXELS'];
          if (dir != null) {
            await tester.runAsync(() async {
              Directory(dir).createSync(recursive: true);
              final image = await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
              final data =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              File('$dir/count-${sample.count}-${mode.name}-$scale.png')
                  .writeAsBytesSync(data!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        semantics.dispose();
        expect(tester.takeException(), isNull);
        expect(failures, isEmpty, reason: failures.join('\n'));
      });
    }
  }
}
