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

class _ReferenceNonlinearScaler extends TextScaler {
  const _ReferenceNonlinearScaler();

  @override
  double scale(double fontSize) => fontSize * (fontSize <= 12 ? 2.2 : 1.4);

  @override
  double get textScaleFactor => 1.4;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Cairo', 'Amiri']) {
      final loader = FontLoader(family);
      final regular = File('assets/fonts/$family-Regular.ttf');
      expect(regular.existsSync(), isTrue);
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
    expect((await QuranRepository.getAyah(2, 1))?.ayahNumber, 1);
    expect((await QuranRepository.getAyah(2, 255))?.ayahNumber, 255);
    await QuranSearchService.instance.searchAyahs('2:1');
  });
  for (final mode in AppThemeMode.values) {
    for (final scale
        in (mode == AppThemeMode.dark ? [1.0, 2.0, 2.2] : [1.0, 2.0])) {
      final textScaler = scale == 2.2
          ? const _ReferenceNonlinearScaler()
          : TextScaler.linear(scale);
      testWidgets('reference actions keep readable words ${mode.name} $scale',
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
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: Directionality(
                    textDirection: TextDirection.rtl, child: child!),
              ),
              home: const QuranSearchScreen(),
            )));
        await tester.pumpAndSettle();
        final failures = <String>[];
        for (final reference in ['2:1', '2:255']) {
          await tester.enterText(find.byType(TextField), reference);
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('فتح في المصحف'));
          await tester.pumpAndSettle();
          final error = tester.takeException();
          if (error != null) failures.add('$reference: $error');
          final open = find.widgetWithText(ElevatedButton, 'فتح في المصحف');
          final tafsir = find.widgetWithText(OutlinedButton, 'التفسير');
          expect(open, findsOneWidget);
          expect(tafsir, findsOneWidget);
          expect(tester.widget<ElevatedButton>(open).onPressed, isNotNull);
          expect(tester.widget<OutlinedButton>(tafsir).onPressed, isNotNull);
          for (final button in [open, tafsir]) {
            final data = tester.getSemantics(button).getSemanticsData();
            expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
          }
          final openData = tester.getSemantics(open).getSemanticsData();
          expect(openData.label, contains('فتح في المصحف'));
          expect(tester.getSemantics(tafsir).label, contains('التفسير'));
          for (final label in ['فتح في المصحف', 'التفسير']) {
            final paragraph =
                tester.renderObject<RenderParagraph>(find.text(label));
            expect(paragraph.textScaler.scale(12), closeTo(12 * scale, .001));
            expect(paragraph.maxLines, isNull);
            expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
            for (final word in label.split(' ')) {
              final start = label.indexOf(word);
              final boxes = paragraph.getBoxesForSelection(TextSelection(
                  baseOffset: start, extentOffset: start + word.length));
              if (boxes.length != 1)
                failures.add(
                    '$reference: $word split across ${boxes.length} boxes');
            }
          }
          final openRect = tester.getRect(open);
          final tafsirRect = tester.getRect(tafsir);
          final viewport = tester.getRect(find.byType(ListView));
          for (final rect in [openRect, tafsirRect]) {
            if (rect.left < viewport.left + 16 ||
                rect.right > viewport.right - 16 ||
                rect.top < viewport.top - .5 ||
                rect.bottom > viewport.bottom + .5)
              failures.add('$reference: action outside padded viewport: $rect');
          }
          if (scale == 1) {
            expect(openRect.center.dy, closeTo(tafsirRect.center.dy, .5));
            expect(openRect.width, closeTo(tafsirRect.width, .5));
            expect(openRect.left, greaterThan(tafsirRect.left));
          } else if (tafsirRect.top < openRect.bottom) {
            failures.add('$reference: actions did not stack at 2x');
          }
          final dir = Platform.environment['SEARCH_REFERENCE_PIXELS'];
          if (dir != null) {
            await tester.runAsync(() async {
              Directory(dir).createSync(recursive: true);
              final image = await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              File('$dir/reference-${reference.replaceAll(':', '-')}-${mode.name}-$scale.png')
                  .writeAsBytesSync(bytes!.buffer.asUint8List());
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
