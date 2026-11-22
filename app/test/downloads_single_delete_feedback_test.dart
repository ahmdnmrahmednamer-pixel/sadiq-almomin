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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'single delete cancellation failure and success report the real result for every download type',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('single-delete-feedback-');
    final dirs = ['quran_audio', 'prophet_stories', 'adhkar_audio']
        .map((s) => Directory('${temp.path}/$s')..createSync())
        .toList();
    final track = IslamicAudioService.allTracks
        .firstWhere((t) => t.id == 'adhkar_morning');
    final names = [
      'minshawi_murattal_001.mp3',
      'adam.mp3',
      IslamicAudioService.downloadFileNameForTrack(track.id)
    ];
    final files = [
      for (var i = 0; i < 3; i++)
        File('${dirs[i].path}/${names[i]}')
          ..writeAsBytesSync(List.filled(4096, 1))
    ];
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
    tester.view.physicalSize = const Size(412, 950);
    tester.view.devicePixelRatio = 1;
    Future<void> mount(double scale) async {
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Cairo'),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: const DownloadsManagerScreen())));
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      final dir = Platform.environment['DELETE_PIXELS'];
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

    Future<void> openDelete(int index) async {
      final button = find.byTooltip('حذف التنزيل').at(index);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    }

    try {
      for (final scale in [1.0, 2.0]) {
        await mount(scale);
        await capture('initial-$scale');
        // The order on screen is story, Quran, adhkar.
        for (final (index, fileIndex) in [(0, 1), (1, 0), (2, 2)]) {
          await openDelete(index);
          await tester.tap(find.text('إلغاء'));
          await tester.pumpAndSettle();
          expect(files[fileIndex].existsSync(), isTrue);
          expect(find.byType(SnackBar), findsNothing);
          final result =
              Process.runSync('chmod', ['0555', dirs[fileIndex].path]);
          expect(result.exitCode, 0);
          await openDelete(index);
          await tester.tap(find.text('حذف'));
          await tester.pumpAndSettle();
          expect(files[fileIndex].existsSync(), isTrue,
              reason: 'Read-only parent must retain the failed-delete fixture');
          final snack = find.byType(SnackBar);
          expect(snack, findsOneWidget);
          final message = tester
              .widget<Text>(
                  find.descendant(of: snack, matching: find.byType(Text)).first)
              .data!;
          expect(message, contains('تعذر حذف'),
              reason: 'Do not report success when service returns false');
          expect(message, isNot(contains('بنجاح')));
          expect(find.bySemanticsLabel(RegExp('تعذر حذف')), findsWidgets);
          expect(tester.takeException(), isNull);
          await capture('failure-$fileIndex-$scale');
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          expect(
              (Process.runSync('chmod', ['0755', dirs[fileIndex].path]))
                  .exitCode,
              0);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
      await mount(1);
      for (final fileIndex in [1, 0, 2]) {
        await openDelete(0);
        await tester.tap(find.text('حذف'));
        await tester.pumpAndSettle();
        expect(files[fileIndex].existsSync(), isFalse);
        expect(find.textContaining('بنجاح'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }
      expect(AudioDownloadService.instance.getDownloadedSurahsList(), isEmpty);
      expect(StoriesService.instance.getDownloadedStories(), isEmpty);
      expect(IslamicAudioService.instance.getDownloadedTracks(), isEmpty);
    } finally {
      for (final dir in dirs) Process.runSync('chmod', ['0755', dir.path]);
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
