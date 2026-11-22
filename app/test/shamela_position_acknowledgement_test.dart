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
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _key = 'flutter.shamela_last_spine_pos_191';
const _error = 'تعذر حفظ موضع القراءة';

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData({_key: 0});
  bool reject = false, writeBeforeReject = false;
  bool throwSync = false, throwAsync = false;
  Completer<bool>? gate;
  final entered = Completer<void>();
  final writes = <(String, String, Object)>[];
  @override
  Future<bool> setValue(String type, String key, Object value) {
    writes.add((type, key, value));
    if (!entered.isCompleted) entered.complete();
    if (throwSync) throw StateError('synthetic synchronous provider failure');
    if (throwAsync) {
      return Future<bool>.error(
          StateError('synthetic asynchronous provider failure'));
    }
    Future<bool> complete(bool acknowledged) async {
      if (acknowledged || writeBeforeReject) {
        await super.setValue(type, key, value);
      }
      return acknowledged;
    }

    return gate != null ? gate!.future.then(complete) : complete(!reject);
  }
}

final _book = OfflineShamelaBook(
  id: 191,
  title: 'كتاب تجريبي لتأكيد الطلب',
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
          text: 'نص تجريبي للصفحة ${i + 1}')),
  toc: const [],
);

Future<void> _pump(WidgetTester tester, ShamelaEpubService service,
    {AppThemeMode mode = AppThemeMode.light, GlobalKey? boundary}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.of(mode),
        home: ShamelaOfflineReaderScreen(
            book: _book, epubService: service, initialIndex: 0),
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
  late _Store store;
  late ShamelaEpubService service;
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    service = ShamelaEpubService();
  });
  tearDown(() {
    if (store.gate != null && !store.gate!.isCompleted)
      store.gate!.complete(false);
  });

  test('acknowledged zero index retains existing key and provider value',
      () async {
    await service.saveLastPosition(191, 0);
    expect(store.writes, [('Int', _key, 0)]);
    expect((await store.getAll())[_key], 0);
    expect(await service.getLastPosition(191), 0);
  });
  test('acknowledged positions preserve separate book keys', () async {
    await service.saveLastPosition(191, 2);
    await service.saveLastPosition(192, 1);
    expect(store.writes,
        [('Int', _key, 2), ('Int', 'flutter.shamela_last_spine_pos_192', 1)]);
    expect(await service.getLastPosition(191), 2);
    expect(await service.getLastPosition(192), 1);
  });
  test('false acknowledgement is an error with an existing provider position',
      () async {
    store.reject = true;
    await expectLater(service.saveLastPosition(191, 1), throwsStateError);
    expect((await store.getAll())[_key], 0);
    expect(store.writes, [('Int', _key, 1)]);
  });
  test('false acknowledgement is an error on first use', () async {
    await store.remove(_key);
    store.reject = true;
    await expectLater(service.saveLastPosition(191, 1), throwsStateError);
    expect((await store.getAll()).containsKey(_key), isFalse);
    expect(store.writes, [('Int', _key, 1)]);
  });
  test('false after a provider write remains unconfirmed without rollback',
      () async {
    store.reject = store.writeBeforeReject = true;
    await expectLater(service.saveLastPosition(191, 1), throwsStateError);
    expect((await store.getAll())[_key], 1);
    expect(store.writes, [('Int', _key, 1)]);
  });
  for (final synchronous in [false, true]) {
    test('existing thrown provider errors still propagate sync=$synchronous',
        () async {
      store.throwSync = synchronous;
      store.throwAsync = !synchronous;
      await expectLater(service.saveLastPosition(191, 1), throwsStateError);
      expect((await store.getAll())[_key], 0);
      expect(store.writes, hasLength(1));
    });
  }
  test('pending false acknowledgement does not complete early', () async {
    store.gate = Completer<bool>();
    final future = service.saveLastPosition(191, 1);
    var finished = false;
    future.then((_) => finished = true, onError: (_) => finished = true);
    final expectation = expectLater(future, throwsStateError);
    await store.entered.future;
    expect(finished, isFalse);
    store.gate!.complete(false);
    await expectation;
    expect((await store.getAll())[_key], 0);
  });
  test('pending true acknowledgement still waits and completes normally',
      () async {
    store.gate = Completer<bool>();
    final future = service.saveLastPosition(191, 1);
    var finished = false;
    future.then((_) => finished = true);
    await store.entered.future;
    expect(finished, isFalse);
    store.gate!.complete(true);
    await future;
    expect((await store.getAll())[_key], 1);
    expect(store.writes, hasLength(1));
  });

  for (final mode in AppThemeMode.values) {
    testWidgets(
        'real service false result reaches reader and recovers ${mode.name}',
        (tester) async {
      final boundary = GlobalKey();
      store.reject = true;
      await _pump(tester, service, mode: mode, boundary: boundary);
      await _next(tester);
      await _capture(tester, boundary, '${mode.name}-unconfirmed');
      expect(find.text(_error), findsOneWidget);
      expect(find.text('نص تجريبي للصفحة 2'), findsOneWidget);
      expect((await store.getAll())[_key], 0);
      expect(store.writes, [('Int', _key, 1)]);
      store.reject = false;
      await _next(tester);
      expect(find.text(_error), findsNothing);
      expect(find.text('نص تجريبي للصفحة 3'), findsOneWidget);
      expect((await store.getAll())[_key], 2);
      expect(store.writes, [('Int', _key, 1), ('Int', _key, 2)]);
      await _capture(tester, boundary, '${mode.name}-acknowledged');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('provider write followed by false still gives reader feedback',
      (tester) async {
    store.reject = store.writeBeforeReject = true;
    await _pump(tester, service);
    await _next(tester);
    expect(find.text(_error), findsOneWidget);
    expect(find.text('نص تجريبي للصفحة 2'), findsOneWidget);
    expect((await store.getAll())[_key], 1);
    expect(store.writes, hasLength(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('real service thrown error retains existing reader containment',
      (tester) async {
    store.throwAsync = true;
    await _pump(tester, service);
    await _next(tester);
    expect(find.text(_error), findsOneWidget);
    expect(find.text('نص تجريبي للصفحة 2'), findsOneWidget);
    expect(store.writes, hasLength(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('pending real-service false after disposal is contained',
      (tester) async {
    store.gate = Completer<bool>();
    await _pump(tester, service);
    await _next(tester);
    expect(store.writes, hasLength(1));
    expect(find.text(_error), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    store.gate!.complete(false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
