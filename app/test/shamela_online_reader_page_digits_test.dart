import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/library/shamela_book_reader_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _families = ['0123456789', '٠١٢٣٤٥٦٧٨٩', '۰۱۲۳۴۵۶۷۸۹'];
const _rangeError = 'يرجى إدخال رقم صفحة صحيح';

class _Pages implements HttpClientAdapter {
  final requests = <int>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<dynamic>? cancel) async {
    final page = int.parse(options.uri.pathSegments.last);
    requests.add(page);
    return ResponseBody.fromString(
        '<html><title>كتاب تجريبي ج 1 ص $page</title>'
        '<div class="nass"><p>نص تجريبي للصفحة $page</p></div></html>',
        200,
        headers: {
          Headers.contentTypeHeader: ['text/html']
        });
  }

  @override
  void close({bool force = false}) {}
}

class _Harness {
  final _Pages pages;
  final Directory root;
  _Harness(this.pages, this.root);
}

Future<void> _idle(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 10));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 3)));
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pump();
      return;
    }
  }
  fail('Synthetic online reader did not finish bounded local fixture I/O');
}

Future<_Harness> _pump(WidgetTester tester,
    {AppThemeMode mode = AppThemeMode.light,
    double scale = 1,
    GlobalKey? boundary}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('online-reader-digits193-')))!;
  final pages = _Pages();
  final dio = Dio(BaseOptions(baseUrl: 'https://shamela.ws'))
    ..httpClientAdapter = pages;
  addTearDown(() async {
    dio.close(force: true);
    await directory.delete(recursive: true);
  });
  await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.of(mode),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: ShamelaBookReaderScreen(
            bookId: 193,
            bookTitle: 'كتاب تجريبي لإدخال رقم الصفحة',
            author: 'مؤلف تجريبي',
            initialPage: 3,
            dio: dio,
            rootDir: directory),
      )));
  await _idle(tester);
  expect(find.text('نص تجريبي للصفحة 3'), findsOneWidget);
  expect(pages.requests, [3]);
  return _Harness(pages, directory);
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

TextEditingValue _format(WidgetTester tester, TextEditingValue oldValue,
        TextEditingValue newValue) =>
    tester.widget<TextField>(find.byType(TextField)).inputFormatters!.fold(
        newValue,
        (value, formatter) => formatter.formatEditUpdate(oldValue, value));

void _expectVisibleField(WidgetTester tester) {
  final editable = tester
      .state<EditableTextState>(find.descendant(
          of: find.byType(TextField), matching: find.byType(EditableText)))
      .renderEditable;
  final text = TextPainter(
    text: editable.text,
    textDirection: editable.textDirection,
    textScaler: editable.textScaler,
  )..layout();
  try {
    expect(editable.size.width, greaterThanOrEqualTo(text.width + 1),
        reason:
            'The whole page number must be visible, not just retained in its controller');
    expect(editable.size.height, greaterThanOrEqualTo(text.height - 1),
        reason: 'The page number must not be vertically clipped');
  } finally {
    text.dispose();
  }
}

Future<void> _selected(WidgetTester tester, _Harness harness, int page) async {
  await _idle(tester);
  expect(harness.pages.requests, [3, page]);
  expect(find.text('نص تجريبي للصفحة $page'), findsOneWidget);
  expect(_fieldText(tester), '$page');
  _expectVisibleField(tester);
  expect(find.text(_rangeError), findsNothing);
  final prefs = await SharedPreferences.getInstance();
  expect(prefs.getInt('shamela_last_page_193'), page);
  final raw = await tester.runAsync(() =>
      File('${harness.root.path}/shamela_cache/193/page_$page.json')
          .readAsString());
  final cache = jsonDecode(raw!) as Map<String, dynamic>;
  expect(cache['bookId'], 193);
  expect(cache['pageId'], page);
  expect(cache['paragraphs'], ['نص تجريبي للصفحة $page']);
  expect(tester.takeException(), isNull);
}

Future<void> _capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  const directory = String.fromEnvironment('SCREENSHOT_DIR');
  if (directory.isEmpty) return;
  // Wait for Material control-state animations before recording final pixels.
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary)
        .toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

String _digits(String ascii, String family) =>
    ascii.split('').map((char) => family[int.parse(char)]).join();

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

  for (final family in _families) {
    for (final page in [1, 12, 240, 100000]) {
      final input = _digits('$page', family);
      testWidgets('IME online jump $input requests page $page', (tester) async {
        final harness = await _pump(tester);
        await tester.enterText(find.byType(TextField), input);
        expect(_fieldText(tester), input);
        await tester.testTextInput.receiveAction(TextInputAction.go);
        await _selected(tester, harness, page);
      });
    }
    for (final ascii in ['0', '999999999999999999999999999999']) {
      final input = _digits(ascii, family);
      testWidgets('invalid online page $input does not request or save',
          (tester) async {
        final harness = await _pump(tester);
        await tester.enterText(find.byType(TextField), input);
        await tester.testTextInput.receiveAction(TextInputAction.go);
        await _idle(tester);
        expect(harness.pages.requests, [3]);
        expect(find.text('نص تجريبي للصفحة 3'), findsOneWidget);
        expect(find.text(_rangeError), findsOneWidget);
        expect(
            (await SharedPreferences.getInstance())
                .getInt('shamela_last_page_193'),
            3);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('online formatter preserves ten digits $family',
        (tester) async {
      await _pump(tester);
      final value = TextEditingValue(
          text: family,
          selection: TextSelection.collapsed(offset: family.length));
      expect(_format(tester, TextEditingValue.empty, value), value);
      expect(tester.takeException(), isNull);
    });
    testWidgets('online digit caret and composing range $family',
        (tester) async {
      await _pump(tester);
      final value = TextEditingValue(
          text: _digits('123', family),
          selection: const TextSelection.collapsed(offset: 2),
          composing: const TextRange(start: 1, end: 2));
      expect(
          _format(
              tester,
              const TextEditingValue(
                  text: '13', selection: TextSelection.collapsed(offset: 1)),
              value),
          value);
      expect(tester.takeException(), isNull);
    });
  }
  for (final input in ['١2', '1۲', '۱٢']) {
    testWidgets('online mixed-script jump button $input', (tester) async {
      final harness = await _pump(tester);
      await tester.enterText(find.byType(TextField), input);
      expect(_fieldText(tester), input);
      await tester.tap(find.byTooltip('انتقال'));
      await _selected(tester, harness, 12);
    });
  }
  testWidgets('online empty input keeps current page and feedback',
      (tester) async {
    final harness = await _pump(tester);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.byTooltip('انتقال'));
    await _idle(tester);
    expect(harness.pages.requests, [3]);
    expect(find.text('نص تجريبي للصفحة 3'), findsOneWidget);
    expect(find.text(_rangeError), findsOneWidget);
    expect(
        (await SharedPreferences.getInstance()).getInt('shamela_last_page_193'),
        3);
    expect(tester.takeException(), isNull);
  });
  for (final pair in [(' a1.-2 ', '12'), ('x١٫۲y', '١۲')]) {
    testWidgets('online non-digit filtering ${pair.$1}', (tester) async {
      await _pump(tester);
      final result = _format(
          tester,
          TextEditingValue.empty,
          TextEditingValue(
              text: pair.$1,
              selection: TextSelection.collapsed(offset: pair.$1.length)));
      expect(result.text, pair.$2);
      expect(result.selection, TextSelection.collapsed(offset: pair.$2.length));
      expect(tester.takeException(), isNull);
    });
  }
  for (final mode in AppThemeMode.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('online semantic jump ${mode.name} $scale', (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final boundary = GlobalKey();
          final harness =
              await _pump(tester, mode: mode, scale: scale, boundary: boundary);
          await tester.enterText(find.byType(TextField), '١٠٠٠٠٠');
          await tester.pump();
          final entered = _fieldText(tester);
          await _capture(tester, boundary, '${mode.name}-$scale-input');
          _expectVisibleField(tester);
          final node = tester.getSemantics(find.byTooltip('انتقال'));
          expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isTrue);
          tester
              .renderObject<RenderBox>(find.byType(Scaffold))
              .owner!
              .semanticsOwner!
              .performAction(node.id, ui.SemanticsAction.tap);
          await _idle(tester);
          await _capture(tester, boundary, '${mode.name}-$scale-selected');
          expect(entered, '١٠٠٠٠٠');
          await _selected(tester, harness, 100000);
          final field = tester.getRect(find.byType(TextField));
          expect(field.left, greaterThanOrEqualTo(0));
          expect(field.right, lessThanOrEqualTo(390));
          expect(field.top, greaterThanOrEqualTo(0));
          expect(field.bottom, lessThanOrEqualTo(844));
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}
