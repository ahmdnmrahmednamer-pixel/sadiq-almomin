import 'dart:async';
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

const _error = 'تعذر حفظ موضع القراءة';
final _book = OfflineShamelaBook(
  id: 189,
  title: 'كتاب تجريبي للقراءة المحلية',
  author: 'مؤلف تجريبي',
  sourceUrl: '',
  downloadedAt: DateTime(2026, 11, 22),
  metadata: const {},
  pages: const [
    OfflineShamelaPage(
        id: 'one',
        path: 'one.xhtml',
        title: 'الأولى',
        text: 'نص تجريبي للصفحة الأولى'),
    OfflineShamelaPage(
        id: 'two',
        path: 'two.xhtml',
        title: 'الثانية',
        text: 'نص تجريبي للصفحة الثانية'),
    OfflineShamelaPage(
        id: 'three',
        path: 'three.xhtml',
        title: 'الثالثة',
        text: 'نص تجريبي للصفحة الثالثة'),
  ],
  toc: const [
    ShamelaTocEntry(
        label: 'القسم الثالث',
        contentSrc: 'three.xhtml',
        depth: 0,
        spineIndex: 2,
        children: []),
  ],
);

class _PositionService extends ShamelaEpubService {
  Future<void> Function(int)? save;
  int? restored = 0;
  final writes = <int>[];
  @override
  Future<int?> getLastPosition(int bookId) async => restored;
  @override
  Future<void> saveLastPosition(int bookId, int spineIndex) {
    writes.add(spineIndex);
    return save?.call(spineIndex) ?? Future<void>.value();
  }
}

Future<void> _pump(WidgetTester tester, _PositionService service,
    {int? initialIndex = 0,
    AppThemeMode mode = AppThemeMode.light,
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
          child: child!,
        ),
        home: ShamelaOfflineReaderScreen(
            book: _book, epubService: service, initialIndex: initialIndex),
      )));
  await tester.pumpAndSettle();
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ElevatedButton, 'التالي'));
  await tester.pumpAndSettle();
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
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('successful navigation and restore keep the existing contract',
      (tester) async {
    final service = _PositionService()..restored = 1;
    await _pump(tester, service, initialIndex: null);
    expect(find.text('نص تجريبي للصفحة الثانية'), findsOneWidget);
    await _next(tester);
    expect(service.writes, [2]);
    expect(find.text('نص تجريبي للصفحة الثالثة'), findsOneWidget);
    expect(find.text(_error), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final synchronous in [false, true]) {
    testWidgets('save failure is contained and visible sync=$synchronous',
        (tester) async {
      final service = _PositionService()
        ..save = (_) {
          if (synchronous) throw StateError('synthetic write failure');
          return Future<void>.error(StateError('synthetic write failure'));
        };
      await _pump(tester, service);
      await _next(tester);
      expect(find.text(_error), findsOneWidget);
      expect(find.text('نص تجريبي للصفحة الثانية'), findsOneWidget);
      expect(service.writes, [1]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('previous-page write failure does not undo navigation',
      (tester) async {
    final service = _PositionService()
      ..save = (_) async {
        throw StateError('synthetic previous write failure');
      };
    await _pump(tester, service, initialIndex: 1);
    await tester.tap(find.widgetWithText(OutlinedButton, 'السابق'));
    await tester.pumpAndSettle();
    expect(service.writes, [0]);
    expect(find.text(_error), findsOneWidget);
    expect(find.text('نص تجريبي للصفحة الأولى'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('jump write failure keeps the chosen valid page visible',
      (tester) async {
    final service = _PositionService()
      ..save = (_) async {
        throw StateError('synthetic jump write failure');
      };
    await _pump(tester, service);
    await tester.enterText(find.byType(TextField), '3');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(service.writes, [2]);
    expect(find.text(_error), findsOneWidget);
    expect(find.text('نص تجريبي للصفحة الثالثة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TOC write failure keeps the chosen section readable',
      (tester) async {
    final service = _PositionService()
      ..save = (_) async {
        throw StateError('synthetic TOC write failure');
      };
    await _pump(tester, service);
    await tester.tap(find.byTooltip('الفهرس'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('القسم الثالث'));
    await tester.pumpAndSettle();
    expect(service.writes, [2]);
    expect(find.text(_error), findsOneWidget);
    expect(find.text('نص تجريبي للصفحة الثالثة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending failure is shown only after that save fails',
      (tester) async {
    final pending = Completer<void>();
    final service = _PositionService()..save = (_) => pending.future;
    await _pump(tester, service);
    await _next(tester);
    expect(find.text(_error), findsNothing);
    pending.completeError(StateError('synthetic delayed failure'));
    await tester.pumpAndSettle();
    expect(find.text(_error), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('older failed save cannot report over a newer successful save',
      (tester) async {
    final pending = Completer<void>();
    final service = _PositionService()
      ..save = (index) => index == 1 ? pending.future : Future<void>.value();
    await _pump(tester, service);
    await _next(tester);
    await _next(tester);
    pending.completeError(StateError('synthetic stale failure'));
    await tester.pumpAndSettle();
    expect(find.text(_error), findsNothing);
    expect(service.writes, [1, 2]);
    expect(find.text('نص تجريبي للصفحة الثالثة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'revisiting a page does not make its older failed request current',
      (tester) async {
    final pending = Completer<void>();
    var first = true;
    final service = _PositionService()
      ..save = (_) {
        if (first) {
          first = false;
          return pending.future;
        }
        return Future<void>.value();
      };
    await _pump(tester, service);
    await _next(tester);
    await _next(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'السابق'));
    await tester.pumpAndSettle();
    pending.completeError(StateError('synthetic older same-page failure'));
    await tester.pumpAndSettle();
    expect(find.text(_error), findsNothing);
    expect(service.writes, [1, 2, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('latest failure is retained while an older save succeeds',
      (tester) async {
    final older = Completer<void>();
    final latest = Completer<void>();
    final service = _PositionService()
      ..save = (index) => index == 1 ? older.future : latest.future;
    await _pump(tester, service);
    await _next(tester);
    await _next(tester);
    latest.completeError(StateError('synthetic latest failure'));
    await tester.pumpAndSettle();
    expect(find.text(_error), findsOneWidget);
    older.complete();
    await tester.pumpAndSettle();
    expect(find.text(_error), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('later successful completion clears the old failure feedback',
      (tester) async {
    var fail = true;
    final service = _PositionService()
      ..save = (_) async {
        if (fail) throw StateError('synthetic recoverable failure');
      };
    await _pump(tester, service);
    await _next(tester);
    expect(find.text(_error), findsOneWidget);
    fail = false;
    await _next(tester);
    expect(find.text(_error), findsNothing);
    expect(service.writes, [1, 2]);
    expect(find.text('نص تجريبي للصفحة الثالثة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late failure after disposal is caught without UI work',
      (tester) async {
    final pending = Completer<void>();
    final service = _PositionService()..save = (_) => pending.future;
    await _pump(tester, service);
    await _next(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.completeError(StateError('synthetic disposed failure'));
    await tester.pumpAndSettle();
    expect(find.text(_error), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen-reader next action remains available after a failure',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final service = _PositionService()
        ..save = (_) async {
          throw StateError('synthetic semantic save failure');
        };
      await _pump(tester, service);
      await _next(tester);
      final node = tester.getSemantics(find.bySemanticsLabel('التالي'));
      tester
          .renderObject<RenderBox>(find.byType(Scaffold))
          .owner!
          .semanticsOwner!
          .performAction(node.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(service.writes, [1, 2]);
      expect(find.text(_error), findsOneWidget);
      expect(find.text('نص تجريبي للصفحة الثالثة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  for (final mode in AppThemeMode.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('visible accessible save error ${mode.name} $scale',
          (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final boundary = GlobalKey();
          final service = _PositionService()
            ..save = (_) async {
              throw StateError('synthetic visual save failure');
            };
          await _pump(tester, service,
              mode: mode, scale: scale, boundary: boundary);
          final prefix = 'reader-${mode.name}-$scale';
          await _capture(tester, boundary, '$prefix-normal');
          await _next(tester);
          final error = find.text(_error);
          expect(error, findsOneWidget);
          expect(
              tester
                  .getSemantics(error)
                  .getSemanticsData()
                  .flagsCollection
                  .isLiveRegion,
              isTrue);
          expect(tester.getSemantics(error).label, _error);
          final theme = AppTheme.of(mode);
          final fg = theme.colorScheme.error.computeLuminance();
          final bg = theme.scaffoldBackgroundColor.computeLuminance();
          final contrast = (fg > bg ? fg + 0.05 : bg + 0.05) /
              (fg > bg ? bg + 0.05 : fg + 0.05);
          expect(contrast, greaterThanOrEqualTo(4.5));
          final errorRect = tester.getRect(error);
          final previous =
              tester.getRect(find.widgetWithText(OutlinedButton, 'السابق'));
          final next =
              tester.getRect(find.widgetWithText(ElevatedButton, 'التالي'));
          expect(errorRect.overlaps(previous), isFalse);
          expect(errorRect.overlaps(next), isFalse);
          expect(errorRect.left, greaterThanOrEqualTo(0));
          expect(errorRect.right, lessThanOrEqualTo(390));
          expect(errorRect.top, greaterThanOrEqualTo(0));
          expect(errorRect.bottom, lessThanOrEqualTo(844));
          await _capture(tester, boundary, '$prefix-error');
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}
