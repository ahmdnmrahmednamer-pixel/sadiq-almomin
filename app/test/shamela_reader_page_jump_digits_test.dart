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

const _rangeError = 'يرجى إدخال رقم صفحة بين 1 و 24';
const _families = ['0123456789', '٠١٢٣٤٥٦٧٨٩', '۰۱۲۳۴۵۶۷۸۹'];
final _book = OfflineShamelaBook(
  id: 192,
  title: 'كتاب تجريبي لإدخال رقم الصفحة',
  author: 'مؤلف تجريبي',
  sourceUrl: '',
  downloadedAt: DateTime(2026, 11, 22),
  metadata: const {},
  pages: List.generate(
      24,
      (i) => OfflineShamelaPage(
          id: '$i',
          path: '$i.xhtml',
          title: 'عنوان الصفحة ${i + 1}',
          text: 'نص تجريبي للصفحة ${i + 1}')),
  toc: const [],
);

class _Service extends ShamelaEpubService {
  final writes = <int>[];
  @override
  Future<int?> getLastPosition(int bookId) async => 2;
  @override
  Future<void> saveLastPosition(int bookId, int index) async =>
      writes.add(index);
}

Future<void> _pump(WidgetTester tester, _Service service,
    {AppThemeMode mode = AppThemeMode.light,
    double scale = 1,
    GlobalKey? boundary}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.of(mode),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: ShamelaOfflineReaderScreen(
            book: _book, epubService: service, initialIndex: 2),
      )));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

TextEditingValue _format(
    WidgetTester tester, TextEditingValue oldValue, TextEditingValue newValue) {
  final formatters =
      tester.widget<TextField>(find.byType(TextField)).inputFormatters!;
  return formatters.fold(newValue,
      (value, formatter) => formatter.formatEditUpdate(oldValue, value));
}

Future<void> _capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  const directory = String.fromEnvironment('SCREENSHOT_DIR');
  if (directory.isEmpty) return;
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
    for (final page in [1, 12, 24]) {
      final input = _digits('$page', family);
      testWidgets('IME page jump accepts $input to page $page', (tester) async {
        final service = _Service();
        await _pump(tester, service);
        await tester.enterText(find.byType(TextField), input);
        expect(_fieldText(tester), input);
        await tester.testTextInput.receiveAction(TextInputAction.go);
        await tester.pumpAndSettle();
        expect(service.writes, [page - 1]);
        expect(find.text('نص تجريبي للصفحة $page'), findsOneWidget);
        expect(_fieldText(tester), '$page');
        expect(find.text(_rangeError), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
    for (final ascii in ['0', '25', '999999999999999999999999999999']) {
      final input = _digits(ascii, family);
      testWidgets('invalid page $input keeps current page without saving',
          (tester) async {
        final service = _Service();
        await _pump(tester, service);
        await tester.enterText(find.byType(TextField), input);
        await tester.testTextInput.receiveAction(TextInputAction.go);
        await tester.pumpAndSettle();
        expect(service.writes, isEmpty);
        expect(find.text('نص تجريبي للصفحة 3'), findsOneWidget);
        expect(find.text(_rangeError), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('formatter preserves all ten digits $family', (tester) async {
      await _pump(tester, _Service());
      final value = TextEditingValue(
          text: family,
          selection: TextSelection.collapsed(offset: family.length));
      expect(_format(tester, TextEditingValue.empty, value), value);
      expect(tester.takeException(), isNull);
    });
    testWidgets('formatter keeps digit caret and composing range $family',
        (tester) async {
      await _pump(tester, _Service());
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
    testWidgets('mixed-script digits $input work through jump button',
        (tester) async {
      final service = _Service();
      await _pump(tester, service);
      await tester.enterText(find.byType(TextField), input);
      expect(_fieldText(tester), input);
      await tester.tap(find.byTooltip('انتقال'));
      await tester.pumpAndSettle();
      expect(service.writes, [11]);
      expect(find.text('نص تجريبي للصفحة 12'), findsOneWidget);
      expect(find.text(_rangeError), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('empty input retains existing range feedback and page',
      (tester) async {
    final service = _Service();
    await _pump(tester, service);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.byTooltip('انتقال'));
    await tester.pumpAndSettle();
    expect(service.writes, isEmpty);
    expect(find.text('نص تجريبي للصفحة 3'), findsOneWidget);
    expect(find.text(_rangeError), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final pair in [(' a1.-2 ', '12'), ('x١٫۲y', '١۲')]) {
    testWidgets('formatter retains existing non-digit filtering ${pair.$1}',
        (tester) async {
      await _pump(tester, _Service());
      final value = TextEditingValue(
          text: pair.$1,
          selection: TextSelection.collapsed(offset: pair.$1.length));
      final result = _format(tester, TextEditingValue.empty, value);
      expect(result.text, pair.$2);
      expect(result.selection, TextSelection.collapsed(offset: pair.$2.length));
      expect(tester.takeException(), isNull);
    });
  }

  for (final mode in AppThemeMode.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('localized jump semantic action ${mode.name} $scale',
          (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final service = _Service();
          final boundary = GlobalKey();
          await _pump(tester, service,
              mode: mode, scale: scale, boundary: boundary);
          await tester.enterText(find.byType(TextField), '١٢');
          await tester.pump();
          final entered = _fieldText(tester);
          await _capture(tester, boundary, '${mode.name}-$scale-input');
          final node = tester.getSemantics(find.byTooltip('انتقال'));
          expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isTrue);
          tester
              .renderObject<RenderBox>(find.byType(Scaffold))
              .owner!
              .semanticsOwner!
              .performAction(node.id, ui.SemanticsAction.tap);
          await tester.pumpAndSettle();
          await _capture(tester, boundary, '${mode.name}-$scale-selected');
          expect(entered, '١٢');
          expect(service.writes, [11]);
          expect(find.text('نص تجريبي للصفحة 12'), findsOneWidget);
          expect(_fieldText(tester), '12');
          expect(find.text(_rangeError), findsNothing);
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
