import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/shamela_epub_service.dart';
import '../lib/features/library/shamela_library_screen.dart';

final fontPath = Platform.environment['SHAMELA_TEST_ARABIC_FONT'];
final iconPath = Platform.environment['SHAMELA_TEST_ICON_FONT'];
Future<void> fonts() async {
  for (final entry in {
    'ArabicTest': fontPath!,
    'Amiri': fontPath!,
    'MaterialIcons': iconPath!
  }.entries) {
    final loader = FontLoader(entry.key)
      ..addFont(Future.value(
          ByteData.sublistView(await File(entry.value).readAsBytes())));
    if (entry.key != 'MaterialIcons') {
      loader.addFont(Future.value(ByteData.sublistView(
          await File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
              .readAsBytes())));
    }
    await loader.load();
  }
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/$name.png').writeAsBytes(data!.buffer.asUint8List());
  });
}

class SavedFixtureService extends ShamelaEpubService {
  final OfflineShamelaBook saved;
  SavedFixtureService(this.saved);
  @override
  Future<List<OfflineShamelaBook>> listSavedBooks() async => [saved];
  @override
  Future<int?> getLastPosition(int id) async => 0;
  @override
  Future<void> saveLastPosition(int id, int index) async {}
}

class EmptySavedService extends ShamelaEpubService {
  @override
  Future<List<OfflineShamelaBook>> listSavedBooks() async => [];
}

void main() {
  testWidgets('Shamela search layout at phone width with real Arabic font',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final semanticsHandle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(fonts);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
                fontFamily: 'ArabicTest',
                splashFactory: NoSplash.splashFactory),
            home: ShamelaLibraryScreen(epubService: EmptySavedService()))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'shamela-search-initial');
    semanticsHandle.dispose();
  }, skip: fontPath == null || iconPath == null);
  testWidgets('Shamela search layout at 2x accessibility text scale',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final semanticsHandle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(fonts);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
                fontFamily: 'ArabicTest',
                splashFactory: NoSplash.splashFactory),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!),
            home: ShamelaLibraryScreen(epubService: EmptySavedService()))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final label in [
      'تجاهل التشكيل والهمزات',
      'جميع الحقول',
      'العناوين فقط',
      'المؤلفون فقط'
    ]) {
      final option = find.text(label);
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      final rect = tester.getRect(option);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(find.bySemanticsLabel(RegExp(label)), findsWidgets);
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    Focus.of(tester.element(find.text('بحث الشاملة'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tabBar.controller!.index, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tabBar.controller!.index, 0);
    await capture(tester, key, 'shamela-search-large-text');
    semanticsHandle.dispose();
  }, skip: fontPath == null || iconPath == null);
  testWidgets('Saved books entry opens full offline reader and advances page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final semanticsHandle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(fonts);
    final key = GlobalKey();
    final diskService = ShamelaEpubService(
        rootDir: Directory(Platform.environment['SHAMELA_OFFLINE_ROOT']!));
    final saved = await tester.runAsync(() => diskService.loadSavedBook(1446));
    final service = SavedFixtureService(saved!);
    await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
                fontFamily: 'ArabicTest',
                splashFactory: NoSplash.splashFactory),
            home: ShamelaLibraryScreen(epubService: service))));
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('كتبي المحفوظة'));
    await tester.pumpAndSettle();
    expect(find.text('صحيح ابن خزيمة'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'shamela-saved-books');
    await tester.tap(find.text('صحيح ابن خزيمة'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('الفهرس'), findsOneWidget);

    expect(find.bySemanticsLabel('الفهرس'), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('التالي')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('السابق')), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'shamela-offline-reader');
    semanticsHandle.dispose();
  },
      skip: fontPath == null ||
          iconPath == null ||
          Platform.environment['SHAMELA_OFFLINE_ROOT'] == null);
  testWidgets('Offline reader at 2x accessibility text scale', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final semanticsHandle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(fonts);
    final key = GlobalKey();
    final diskService = ShamelaEpubService(
        rootDir: Directory(Platform.environment['SHAMELA_OFFLINE_ROOT']!));
    final saved = await tester.runAsync(() => diskService.loadSavedBook(1446));
    final service = SavedFixtureService(saved!);
    await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
                fontFamily: 'ArabicTest',
                splashFactory: NoSplash.splashFactory),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!),
            home: ShamelaLibraryScreen(epubService: service))));
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('كتبي المحفوظة'));
    await tester.pumpAndSettle();
    expect(find.text('صحيح ابن خزيمة'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'shamela-saved-books-large-text');
    final searchTab = find.text('بحث الشاملة');
    expect(find.bySemanticsLabel(RegExp('بحث الشاملة')), findsWidgets);
    await tester.ensureVisible(searchTab);
    await tester.tap(searchTab);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsWidgets);
    final savedTab = find.text('كتبي المحفوظة');
    await tester.ensureVisible(savedTab);
    await tester.tap(savedTab);
    await tester.pumpAndSettle();
    await tester.tap(find.text('صحيح ابن خزيمة'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('الفهرس'), findsOneWidget);

    expect(find.bySemanticsLabel('الفهرس'), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('التالي')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('السابق')), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'shamela-offline-reader-large-text');
    semanticsHandle.dispose();
  },
      skip: fontPath == null ||
          iconPath == null ||
          Platform.environment['SHAMELA_OFFLINE_ROOT'] == null);
}
