import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/audio_download_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/audio/audio_screen.dart';
import 'quran_audio_download_race_test.dart' as http;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  HttpOverrides? previous;
  final downloads = AudioDownloadService.instance;
  final requests = <Uri>[];
  StreamController<List<int>>? pending;

  Finder firstSurah() => find.byType(ListTile).first;
  Future<void> flush(WidgetTester tester) async {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> mount(WidgetTester tester,
      {Size size = const Size(360, 800),
      double scale = 1,
      GlobalKey? boundary}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child:
              Directionality(textDirection: TextDirection.rtl, child: child!),
        ),
        home: const AudioScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(firstSurah());
    await tester.pumpAndSettle();
  }

  Future<void> openActions(WidgetTester tester) async {
    await tester.longPress(firstSurah());
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('خيارات سورة الفاتحة'), findsOneWidget);
  }

  Future<void> capture(
      WidgetTester tester, GlobalKey boundary, String name) async {
    const dir = String.fromEnvironment('SURAH_ACTION_PIXELS_DIR');
    if (dir.isEmpty) return;
    await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  setUpAll(() async {
    previous = HttpOverrides.current;
    directory = Directory.systemTemp.createTempSync('surah_actions_');
    HttpOverrides.global = http.DynamicHttpOverrides();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => directory.path);
    for (final family in ['Amiri', 'Cairo']) {
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
      final loader = FontLoader('MaterialIcons')
        ..addFont(
            Future.value(ByteData.sublistView(File(icons).readAsBytesSync())));
      await loader.load();
    }
    await downloads.init();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    requests.clear();
    pending = null;
    http.DynamicHttpOverrides.activeHandler = (_, uri, request) async {
      requests.add(uri);
      final stream = pending;
      if (stream != null) {
        request.onAbort = () {
          if (!stream.isClosed) stream.close();
        };
        return http.TestHttpClientResponse(stream.stream, contentLength: 4096);
      }
      return http.TestHttpClientResponse(
          Stream.value(Uint8List.fromList(List<int>.filled(4096, 1))),
          contentLength: 4096);
    };
  });
  tearDown(() async {
    for (final r in SettingsService.availableReciters) {
      downloads.cancelDownload(r.id, 1);
      await downloads.deleteDownloadedSurah(r.id, 1);
    }
    if (pending != null && !pending!.isClosed) await pending!.close();
  });
  tearDownAll(() {
    HttpOverrides.global = previous;
    http.DynamicHttpOverrides.activeHandler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    directory.deleteSync(recursive: true);
  });

  testWidgets(
      'long press opens recording actions without starting playback or downloading; close is safe',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester);
    await openActions(tester);
    expect(find.text('تحميل السورة'), findsOneWidget);
    expect(find.text('تشغيل أو إيقاف التلاوة'), findsOneWidget);
    expect(find.text(SettingsService.instance.currentReciter.nameAr),
        findsWidgets);
    expect(requests, isEmpty);
    expect(find.byTooltip('إيقاف التلاوة'), findsNothing);
    expect(find.textContaining('حذف'), findsNothing);
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byTooltip('مؤقت النوم'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'screen-reader long-press action opens options and ordinary activation still dispatches playback',
      (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester);
    final node = tester.semantics.simulatedAccessibilityTraversal().firstWhere(
        (n) =>
            n.getSemanticsData().label.contains('الفاتحة') &&
            n.getSemanticsData().hasAction(SemanticsAction.longPress));
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(node.id, SemanticsAction.longPress);
    await tester.pumpAndSettle();
    expect(find.text('خيارات سورة الفاتحة'), findsOneWidget);
    expect(find.byTooltip('إيقاف التلاوة'), findsNothing);
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();
    final tapNode = tester.semantics
        .simulatedAccessibilityTraversal()
        .firstWhere((n) =>
            n.getSemanticsData().label.contains('الفاتحة') &&
            n.getSemanticsData().hasAction(SemanticsAction.tap));
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(tapNode.id, SemanticsAction.tap);
    await flush(tester);
    expect(find.byTooltip('إيقاف التلاوة'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('play action closes sheet and dispatches ordinary surah playback',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, size: const Size(800, 1200));
    await openActions(tester);
    await tester.tap(find.text('تشغيل أو إيقاف التلاوة'));
    await flush(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byTooltip('إيقاف التلاوة'), findsOneWidget);
    expect(requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'download completes after page disposal without using disposed context',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    pending = StreamController<List<int>>();
    await mount(tester);
    await openActions(tester);
    await tester.tap(find.text('تحميل السورة'));
    await flush(tester);
    expect(downloads.isDownloading('minshawi_murattal', 1), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      pending!.add(Uint8List.fromList(List<int>.filled(4096, 1)));
      await pending!.close();
    });
    for (var i = 0;
        i < 5 && !downloads.isDownloaded('minshawi_murattal', 1);
        i++) {
      await flush(tester);
    }
    expect(downloads.isDownloaded('minshawi_murattal', 1), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'context download uses selected reciter and completed status is not a destructive action',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await SettingsService.instance.setSelectedReciter('minshawi_mujawwad');
    await mount(tester);
    await openActions(tester);
    await tester.tap(find.text('تحميل السورة'));
    for (var i = 0;
        i < 5 && !downloads.isDownloaded('minshawi_mujawwad', 1);
        i++) {
      await flush(tester);
    }
    expect(downloads.isDownloaded('minshawi_mujawwad', 1), isTrue);
    expect(downloads.isDownloaded('minshawi_murattal', 1), isFalse);
    expect(requests.map((u) => u.toString()),
        [SettingsService.instance.getSurahAudioUrl(1, 'minshawi_mujawwad')]);
    await openActions(tester);
    final status =
        find.widgetWithText(ListTile, 'السورة محملة للاستماع دون إنترنت');
    expect(tester.widget<ListTile>(status).onTap, isNull);
    expect(find.text('تحميل السورة'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'in-progress recording can be cancelled through its long-press actions',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    pending = StreamController<List<int>>();
    await mount(tester);
    await openActions(tester);
    await tester.tap(find.text('تحميل السورة'));
    await flush(tester);
    expect(downloads.isDownloading('minshawi_murattal', 1), isTrue);
    await openActions(tester);
    final cancel = find.descendant(
        of: find.byType(BottomSheet), matching: find.text('إلغاء التحميل'));
    await tester.tap(cancel);
    await flush(tester);
    expect(downloads.isDownloading('minshawi_murattal', 1), isFalse);
    expect(downloads.isDownloaded('minshawi_murattal', 1), isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'action sheet fits real fonts at narrow and 2x sizes with reachable close and download',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [
      const Size(320, 640),
      const Size(360, 800),
      const Size(412, 915)
    ]) {
      for (final scale in [1.0, 2.0]) {
        final key = GlobalKey();
        await mount(tester, size: size, scale: scale, boundary: key);
        await openActions(tester);
        await tester.ensureVisible(find.text('إغلاق'));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.text('إغلاق')).bottom,
            lessThanOrEqualTo(size.height));
        expect(find.text('تحميل السورة'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(
            tester, key, 'actions_${size.width.toInt()}_${scale.toInt()}x');
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    }
  });
}
