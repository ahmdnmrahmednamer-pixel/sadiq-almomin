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
import 'package:almomin/features/stories/stories_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'story card rows keep daily metadata and play actions within narrow large-text layout',
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
    final semantics = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    Future<void> capture(String name) async {
      final dir = Platform.environment['STORY_LAYOUT_PIXELS'];
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
      for (final width in [360.0, 412.0]) {
        for (final scale in [1.0, 2.0]) {
          tester.view.physicalSize = Size(width, 950);
          await tester.pumpWidget(RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(fontFamily: 'Cairo'),
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!),
                  home: const StoriesScreen())));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final marker = find.text('قصة اليوم المختارة');
          await tester.ensureVisible(marker);
          await tester.pumpAndSettle();
          expect(marker, findsOneWidget);
          expect(tester.renderObject<RenderParagraph>(marker).didExceedMaxLines,
              isFalse);
          await capture('header-$width-$scale');
          final play = find.widgetWithText(ElevatedButton, 'استمع الآن');
          await tester.ensureVisible(play);
          await tester.pumpAndSettle();
          expect(play, findsOneWidget);
          final node = tester.getSemantics(play);
          expect(node.label, contains('استمع الآن'));
          expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isTrue);
          expect(tester.getRect(play).left, greaterThanOrEqualTo(0));
          expect(tester.getRect(play).right, lessThanOrEqualTo(width));
          final narration = find.text(
              'صوت: ${StoriesService.instance.getStoryOfTheDay().narrator}');
          expect(narration, findsOneWidget);
          expect(
              tester.renderObject<RenderParagraph>(narration).didExceedMaxLines,
              isFalse);
          expect(tester.getRect(narration).left, greaterThanOrEqualTo(0));
          expect(tester.getRect(narration).right, lessThanOrEqualTo(width));
          await capture('actions-$width-$scale');
          expect(tester.takeException(), isNull);
          final favorite = find.byTooltip('حفظ في المفضلة').first;
          await tester.ensureVisible(favorite);
          await tester.pumpAndSettle();
          await tester.tap(favorite);
          await tester.pumpAndSettle();
          expect(StoriesService.instance.isFavorite('adam'), isTrue);
          await tester.tap(favorite);
          await tester.pumpAndSettle();
          expect(StoriesService.instance.isFavorite('adam'), isFalse);
          final storyPlay =
              find.widgetWithText(ElevatedButton, 'استماع للقصة').first;
          await tester.ensureVisible(storyPlay);
          await tester.pumpAndSettle();
          expect(tester.getRect(storyPlay).left, greaterThanOrEqualTo(0));
          expect(tester.getRect(storyPlay).right, lessThanOrEqualTo(width));
          expect(
              tester
                  .getSemantics(storyPlay)
                  .getSemanticsData()
                  .hasAction(ui.SemanticsAction.tap),
              isTrue);
          await capture('list-actions-$width-$scale');
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
