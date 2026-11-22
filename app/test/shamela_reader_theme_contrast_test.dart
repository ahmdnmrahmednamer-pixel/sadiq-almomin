import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:almomin/core/services/shamela_epub_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/library/shamela_offline_reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _book = OfflineShamelaBook(
  id: 190,
  title: 'كتاب تجريبي للألوان',
  author: 'مؤلف تجريبي',
  sourceUrl: '',
  downloadedAt: DateTime(2026, 11, 22),
  metadata: const {},
  pages: List.generate(
      3,
      (i) => OfflineShamelaPage(
            id: '$i',
            path: '$i.xhtml',
            title: 'عنوان الصفحة ${i + 1}',
            text: 'نص تجريبي للقراءة في الصفحة ${i + 1}',
          )),
  toc: const [
    ShamelaTocEntry(
        label: 'القسم الثاني',
        contentSrc: '1.xhtml',
        depth: 0,
        spineIndex: 1,
        children: [])
  ],
);

class _Service extends ShamelaEpubService {
  final writes = <int>[];
  Completer<int?>? restoring;
  @override
  Future<int?> getLastPosition(int bookId) =>
      restoring?.future ?? Future.value(1);
  @override
  Future<void> saveLastPosition(int bookId, int index) async =>
      writes.add(index);
}

Future<void> _pump(WidgetTester tester, _Service service, ThemeData theme,
    {double scale = 1,
    int? initialIndex = 1,
    GlobalKey? boundary,
    bool settle = true}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: ShamelaOfflineReaderScreen(
            book: _book, epubService: service, initialIndex: initialIndex),
      )));
  if (settle) await tester.pumpAndSettle();
}

// Inspect the effective rendered foreground, not the nullable Text style.
Color _foreground(WidgetTester tester, Finder finder) =>
    tester.renderObject<RenderParagraph>(finder).text.style!.color!;

// Composite actual ancestor fills, including the translucent offline badge.
// The exercised reader has solid fills and zero-elevation custom buttons.
Color _background(WidgetTester tester, Finder finder) {
  var result = Colors.transparent;
  tester.element(finder).visitAncestorElements((element) {
    final widget = element.widget;
    Color? fill;
    if (widget is Container) {
      fill = widget.color;
      final decoration = widget.decoration;
      if (decoration is BoxDecoration) fill ??= decoration.color;
    } else if (widget is Material) {
      fill = widget.color;
    } else if (widget is Scaffold) {
      fill =
          widget.backgroundColor ?? Theme.of(element).scaffoldBackgroundColor;
    }
    if (fill != null) result = Color.alphaBlend(result, fill);
    return result.a < 1;
  });
  expect(result.a, 1, reason: 'An opaque rendered ancestor is required');
  return result;
}

double _ratio(Color foreground, Color background) {
  final a = Color.alphaBlend(foreground, background).computeLuminance();
  final b = background.computeLuminance();
  return (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
}

Map<String, Object> _measure(WidgetTester tester, String label, Finder finder,
    {Color? foreground, double minimum = 4.5}) {
  final fg = foreground ?? _foreground(tester, finder);
  final bg = _background(tester, finder);
  return {
    'label': label,
    'foreground': fg.toARGB32(),
    'background': bg.toARGB32(),
    'ratio': _ratio(fg, bg),
    'minimum': minimum
  };
}

Future<void> _capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  const directory = String.fromEnvironment('SCREENSHOT_DIR');
  if (directory.isEmpty) return;
  await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary)
        .toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _record(
    WidgetTester tester, String name, List<Map<String, Object>> rows) async {
  const directory = String.fromEnvironment('SCREENSHOT_DIR');
  if (directory.isNotEmpty) {
    await tester.runAsync(() => File('$directory/$name.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(rows)));
  }
  final failures = rows
      .where((row) => (row['ratio'] as double) < (row['minimum'] as double))
      .toList();
  expect(failures, isEmpty, reason: jsonEncode(rows));
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
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final mode in AppThemeMode.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('reader rendered text and controls ${mode.name} $scale',
          (tester) async {
        final boundary = GlobalKey();
        final service = _Service();
        await _pump(tester, service, AppTheme.of(mode),
            scale: scale, boundary: boundary);
        final rows = <Map<String, Object>>[];
        for (final text in [
          'الصفحة 2 من 3',
          'أوفلاين',
          'السابق',
          'ص:',
          'عنوان الصفحة 2',
          'التالي'
        ]) {
          rows.add(_measure(tester, text, find.text(text)));
          final rect = tester.getRect(find.text(text));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(390));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(844));
        }
        for (final icon in [
          Icons.menu_book_rounded,
          Icons.subdirectory_arrow_left_rounded
        ]) {
          final finder = find.byIcon(icon);
          rows.add(_measure(tester, 'icon ${icon.codePoint}', finder,
              foreground: tester.widget<Icon>(finder).color!, minimum: 3));
        }
        expect(service.writes, isEmpty);
        await _capture(tester, boundary, '${mode.name}-$scale-reader');
        await tester.tap(find.byTooltip('الفهرس'));
        await tester.pumpAndSettle();
        expect(
            tester
                .widget<ListTile>(find.ancestor(
                    of: find.text('القسم الثاني'),
                    matching: find.byType(ListTile)))
                .selected,
            isTrue);
        rows.add(_measure(tester, 'selected TOC', find.text('القسم الثاني')));
        await _capture(tester, boundary, '${mode.name}-$scale-toc');
        expect(tester.takeException(), isNull);
        await _record(tester, '${mode.name}-$scale', rows);
      });
    }

    testWidgets('reader boundary and semantic navigation ${mode.name}',
        (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final service = _Service();
        await _pump(tester, service, AppTheme.of(mode), initialIndex: 0);
        expect(
            tester
                .widget<OutlinedButton>(find.byType(OutlinedButton))
                .onPressed,
            isNull);
        expect(
            tester
                .getSemantics(find.bySemanticsLabel('السابق'))
                .getSemanticsData()
                .hasAction(ui.SemanticsAction.tap),
            isFalse);
        final next = tester.getSemantics(find.bySemanticsLabel('التالي'));
        tester
            .renderObject<RenderBox>(find.byType(Scaffold))
            .owner!
            .semanticsOwner!
            .performAction(next.id, ui.SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(service.writes, [1]);
        expect(find.text('نص تجريبي للقراءة في الصفحة 2'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '3');
        await tester.testTextInput.receiveAction(TextInputAction.go);
        await tester.pumpAndSettle();
        expect(service.writes, [1, 2]);
        expect(
            tester
                .widget<ElevatedButton>(find.byType(ElevatedButton))
                .onPressed,
            isNull);
        expect(
            tester
                .getSemantics(find.bySemanticsLabel('التالي'))
                .getSemanticsData()
                .hasAction(ui.SemanticsAction.tap),
            isFalse);
        await tester.tap(find.byTooltip('الفهرس'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('القسم الثاني'));
        await tester.pumpAndSettle();
        expect(service.writes, [1, 2, 1]);
        expect(find.text('نص تجريبي للقراءة في الصفحة 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('restoration indicator contrast ${mode.name}', (tester) async {
      final service = _Service()..restoring = Completer<int?>();
      await _pump(tester, service, AppTheme.of(mode),
          initialIndex: null, settle: false);
      final finder = find.byType(CircularProgressIndicator);
      final color = tester.widget<CircularProgressIndicator>(finder).color!;
      final ratio = _ratio(color, _background(tester, finder));
      // Dispose before checking the result to leave no pending animation.
      await tester.pumpWidget(const SizedBox.shrink());
      service.restoring!.complete(1);
      await tester.pumpAndSettle();
      expect(ratio, greaterThanOrEqualTo(3));
      expect(service.writes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final dark in [false, true]) {
    testWidgets('section title works without custom theme extension dark=$dark',
        (tester) async {
      await _pump(
          tester, _Service(), dark ? ThemeData.dark() : ThemeData.light());
      final finder = find.text('عنوان الصفحة 2');
      expect(_ratio(_foreground(tester, finder), _background(tester, finder)),
          greaterThanOrEqualTo(4.5));
      expect(tester.takeException(), isNull);
    });
  }
}
