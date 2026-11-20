import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/services/reader_bookmark_service.dart';
import 'package:almomin/features/library/widgets/reader_bookmarks_sheet.dart';

class RecoveryBookmarkService extends ReaderBookmarkService {
  bool failAdd = false, failRemove = false, failList = false;
  Completer<void>? addGate;
  final marks = <ReaderBookmark>[];
  @override
  Future<List<ReaderBookmark>> list(String doc, String kind) async {
    if (failList) throw StateError('synthetic read failure');
    return List.of(marks);
  }

  @override
  Future<ReaderBookmark> add(
      {required String documentId,
      required String locationKind,
      required int page,
      required double scrollOffset,
      required String label}) async {
    final gate = addGate;
    addGate = null;
    if (gate != null) await gate.future;
    if (failAdd) throw StateError('synthetic write failure');
    final mark = ReaderBookmark(
        id: 'mark-${marks.length}',
        documentId: documentId,
        locationKind: locationKind,
        page: page,
        scrollOffset: scrollOffset,
        label: label,
        createdAt: DateTime.utc(2026));
    marks.add(mark);
    return mark;
  }

  @override
  Future<void> remove(ReaderBookmark mark) async {
    if (failRemove) throw StateError('synthetic remove failure');
    marks.remove(mark);
  }
}

void main() {
  Future<void> open(WidgetTester t, RecoveryBookmarkService s) async {
    await t.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showReaderBookmarks(context,
                        documentId: 'book',
                        locationKind: 'online-page',
                        page: 1,
                        scrollOffset: 0,
                        pageLabel: 'Page 1',
                        service: s),
                    child: const Text('open'))))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  Future<void> save(WidgetTester t) async {
    await t.tap(find.text('إضافة الموضع الحالي'));
    await t.pumpAndSettle();
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
  }

  testWidgets(
      'transient add error allows another add without closing the sheet',
      (t) async {
    final s = RecoveryBookmarkService()..failAdd = true;
    await open(t, s);
    await save(t);
    expect(find.text('تعذر حفظ العلامة. حاول مرة أخرى.'), findsOneWidget);
    expect(
        t
            .widget<Semantics>(find
                .ancestor(
                    of: find.text('تعذر حفظ العلامة. حاول مرة أخرى.'),
                    matching: find.byType(Semantics))
                .first)
            .properties
            .liveRegion,
        isTrue);
    s.failAdd = false;
    expect(
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    await save(t);
    expect(s.marks, hasLength(1));
    expect(find.textContaining('تعذر حفظ'), findsNothing);
  });
  testWidgets(
      'initial read error offers working in-sheet retry without false empty state',
      (t) async {
    final s = RecoveryBookmarkService()..failList = true;
    await open(t, s);
    expect(find.textContaining('تعذر قراءة العلامات'), findsOneWidget);
    expect(find.text('لا توجد علامات'), findsNothing);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    s.failList = false;
    await t.tap(find.text('إعادة المحاولة'));
    await t.pumpAndSettle();
    expect(find.textContaining('تعذر قراءة'), findsNothing);
    expect(find.text('لا توجد علامات'), findsOneWidget);
    expect(
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
  });
  testWidgets('failed removal preserves row and allows retry and later add',
      (t) async {
    final s = RecoveryBookmarkService();
    await s.add(
        documentId: 'book',
        locationKind: 'online-page',
        page: 1,
        scrollOffset: 0,
        label: 'keep');
    s.failRemove = true;
    await open(t, s);
    await t.tap(find.byTooltip('حذف keep'));
    await t.pumpAndSettle();
    expect(find.text('keep'), findsOneWidget);
    expect(find.text('تعذر حذف العلامة.'), findsOneWidget);
    expect(
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    s.failRemove = false;
    await t.tap(find.byTooltip('حذف keep'));
    await t.pumpAndSettle();
    expect(find.text('keep'), findsNothing);
    await save(t);
    expect(s.marks, hasLength(1));
  });
  testWidgets('pending save disables duplicate actions and settles normally',
      (t) async {
    final s = RecoveryBookmarkService();
    final gate = Completer<void>();
    s.addGate = gate;
    await open(t, s);
    await save(t);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    gate.complete();
    await t.pumpAndSettle();
    expect(s.marks, hasLength(1));
    expect(
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
  });
  testWidgets('dismissal during pending save does not update disposed state',
      (t) async {
    final s = RecoveryBookmarkService();
    final gate = Completer<void>();
    s.addGate = gate;
    await open(t, s);
    await save(t);
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    gate.complete();
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  final font = Platform.environment['READING_TEST_FONT'];
  final icons = Platform.environment['READING_TEST_ICON_FONT'];
  for (final size in [const Size(360, 800), const Size(320, 640)]) {
    final scale = size.width == 360 ? 2.0 : 3.0;
    testWidgets(
        'font-enabled recovery remains reachable ${size.width.toInt()} at ${scale}x',
        (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.runAsync(() async {
        for (final entry
            in {'ArabicTest': font!, 'MaterialIcons': icons!}.entries) {
          await (FontLoader(entry.key)
                ..addFont(Future.value(ByteData.sublistView(
                    await File(entry.value).readAsBytes()))))
              .load();
        }
      });
      final key = GlobalKey();
      final s = RecoveryBookmarkService();
      await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'ArabicTest'),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Builder(
                  builder: (context) => Scaffold(
                      body: TextButton(
                          onPressed: () => showReaderBookmarks(context,
                              documentId: 'book',
                              locationKind: 'online-page',
                              page: 1,
                              scrollOffset: 0,
                              pageLabel: 'Page 1',
                              service: s),
                          child: const Text('open')))))));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      final button = t.getRect(find.byType(FilledButton));
      final label = t.getRect(find.text('إضافة الموضع الحالي'));
      expect(label.top - button.top, greaterThanOrEqualTo(12));
      expect(button.bottom - label.bottom, greaterThanOrEqualTo(12));
      Future<void> capture(String state) async {
        final dir = Platform.environment['BOOKMARK_SCREENSHOT_DIR'];
        if (dir == null) return;
        await t.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
                  '$dir/bookmark-sheet-${size.width.toInt()}-${scale}x-$state.png')
              .writeAsBytes(data!.buffer.asUint8List());
        });
      }

      await capture('normal');
      s.failList = true;
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      // Reopen via the same visual host to exercise wrapped error and recovery.
      await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'ArabicTest'),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Builder(
                  builder: (context) => Scaffold(
                      body: TextButton(
                          onPressed: () => showReaderBookmarks(context,
                              documentId: 'book',
                              locationKind: 'online-page',
                              page: 1,
                              scrollOffset: 0,
                              pageLabel: 'Page 1',
                              service: s),
                          child: const Text('open')))))));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await capture('read-error-top');
      await t.ensureVisible(find.widgetWithText(TextButton, 'إعادة المحاولة'));
      await t.pumpAndSettle();
      final retry =
          t.getRect(find.widgetWithText(TextButton, 'إعادة المحاولة'));
      expect(retry.bottom, lessThanOrEqualTo(size.height));
      await capture('read-error');
      s.failList = false;
      await t.tap(find.text('إعادة المحاولة'));
      await t.pumpAndSettle();
      expect(find.textContaining('تعذر قراءة'), findsNothing);
      expect(t.takeException(), isNull);
    }, skip: font == null || icons == null);
  }
}
