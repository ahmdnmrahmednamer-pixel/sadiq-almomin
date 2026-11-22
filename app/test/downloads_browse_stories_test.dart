import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/audio_download_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/stories_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/audio/downloads_manager_screen.dart';
import 'package:almomin/features/stories/stories_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'empty hub Browse Stories opens stories and preserves back stack from root and nested entry',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('single-delete-feedback-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => temp.path);
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    for (final font in ['Cairo', 'Amiri']) {
      await (FontLoader(font)
            ..addFont(rootBundle.load('assets/fonts/$font-Regular.ttf')))
          .load();
    }
    final iconPath = Platform.environment['MATERIAL_ICONS_FONT'];
    if (iconPath != null)
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(iconPath).readAsBytesSync()))))
          .load();
    await tester.runAsync(() async {
      await AudioDownloadService.instance.init();
      await StoriesService.instance.init(forceReload: true);
      await IslamicAudioService.instance.init();
    });
    final boundary = GlobalKey();
    final nav = GlobalKey<NavigatorState>();
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(412, 950);
    tester.view.devicePixelRatio = 1;
    Future<void> capture(String name) async {
      final dir = Platform.environment['STORIES_NAV_PIXELS'];
      if (dir == null) return;
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    try {
      for (final nested in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                  navigatorKey: nav,
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(fontFamily: 'Cairo'),
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!),
                  home: nested
                      ? const Scaffold(body: Text('previous-sentinel'))
                      : const DownloadsManagerScreen())));
          await tester.pumpAndSettle();
          if (nested) {
            nav.currentState!.push(MaterialPageRoute<void>(
                builder: (_) => const DownloadsManagerScreen()));
            await tester.pumpAndSettle();
          }
          final browse =
              find.widgetWithText(OutlinedButton, 'تصفح قصص الأنبياء');
          await tester.ensureVisible(browse);
          await tester.pumpAndSettle();
          await capture('empty-$nested-$scale');
          final node = tester.getSemantics(browse);
          expect(node.label, contains('تصفح قصص الأنبياء'));
          expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isTrue);
          await tester.tap(browse);
          await tester.pumpAndSettle();
          expect(find.byType(StoriesScreen), findsOneWidget,
              reason: 'Browse Stories must open stories from any hub entry');
          expect(find.text('سلسلة قصص الأنبياء كاملة'), findsOneWidget);
          expect(find.byType(DownloadsManagerScreen), findsNothing);
          expect(nav.currentState!.canPop(), isTrue);
          await capture('stories-$nested-$scale');
          nav.currentState!.pop();
          await tester.pumpAndSettle();
          expect(find.byType(DownloadsManagerScreen), findsOneWidget);
          expect(find.byType(StoriesScreen), findsNothing);
          expect(
              find.text('لا توجد تنزيلات حالياً على الهاتف'), findsOneWidget);
          if (nested) {
            nav.currentState!.pop();
            await tester.pumpAndSettle();
            expect(find.text('previous-sentinel'), findsOneWidget);
          } else
            expect(nav.currentState!.canPop(), isFalse);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      semantics.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null);
      temp.deleteSync(recursive: true);
    }
  });
}
