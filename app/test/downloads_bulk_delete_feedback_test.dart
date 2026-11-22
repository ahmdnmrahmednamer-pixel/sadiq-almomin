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
      'bulk delete reports every cohort failure and zero-byte retired failure honestly',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('bulk-delete-feedback-');
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
      final dir = Platform.environment['BULK_PIXELS'];
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

    Future<void> openBulk() async {
      final button = find.widgetWithText(TextButton, 'حذف الكل');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    }

    Future<void> dismissSnack() async {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }

    Future<void> confirmBulk(
        {required bool success, required String pixel}) async {
      await openBulk();
      await tester.tap(find.text('نعم، حذف الكل'));
      await tester.pumpAndSettle();
      final snack = find.byType(SnackBar);
      expect(snack, findsOneWidget);
      final text = tester
          .widget<Text>(
              find.descendant(of: snack, matching: find.byType(Text)).first)
          .data!;
      if (success) {
        expect(text, 'تم حذف جميع التنزيلات بنجاح');
        expect(tester.widget<SnackBar>(snack).backgroundColor,
            isNot(Colors.redAccent));
      } else {
        expect(text, 'تعذر حذف بعض الملفات. حاول مرة أخرى.');
        expect(text, isNot(contains('بنجاح')));
        expect(
            tester.widget<SnackBar>(snack).backgroundColor, Colors.redAccent);
        expect(find.bySemanticsLabel(text), findsWidgets);
      }
      expect(tester.takeException(), isNull);
      await capture(pixel);
      await dismissSnack();
    }

    void permission(int index, String mode) {
      expect(Process.runSync('chmod', [mode, dirs[index].path]).exitCode, 0);
    }

    Future<void> seedStory() async {
      files[1].writeAsBytesSync(List.filled(4096, 1));
      await tester
          .runAsync(() => StoriesService.instance.init(forceReload: true));
      await tester.pumpAndSettle();
    }

    try {
      for (final scale in [1.0, 2.0]) {
        await mount(scale);
        await capture('initial-$scale');
        await openBulk();
        await tester.tap(find.text('إلغاء'));
        await tester.pumpAndSettle();
        expect(files.every((f) => f.existsSync()), isTrue);
        expect(find.byType(SnackBar), findsNothing);
      }
      for (var i = 0; i < 3; i++) permission(i, '0555');
      for (final scale in [1.0, 2.0]) {
        await mount(scale);
        await confirmBulk(success: false, pixel: 'all-failed-$scale');
        expect(files.every((f) => f.existsSync()), isTrue);
        expect(AudioDownloadService.instance.totalStorageUsedBytes, 4096);
        expect(StoriesService.instance.totalDownloadedStoriesBytes, 4096);
        expect(IslamicAudioService.instance.totalDownloadedBytes, 4096);
      }
      // Quran fails first, but later story/adhkar deletions must still run.
      permission(1, '0755');
      permission(2, '0755');
      for (final scale in [1.0, 2.0]) {
        await mount(scale);
        await confirmBulk(success: false, pixel: 'quran-failed-$scale');
        expect(files[0].existsSync(), isTrue);
        expect(files[1].existsSync(), isFalse);
        expect(files[2].existsSync(), isFalse);
      }
      // Quran now succeeds while story deletion fails.
      permission(0, '0755');
      await seedStory();
      permission(1, '0555');
      for (final scale in [1.0, 2.0]) {
        await mount(scale);
        await confirmBulk(success: false, pixel: 'story-failed-$scale');
        expect(files[0].existsSync(), isFalse);
        expect(files[1].existsSync(), isTrue);
      }
      // A current adhkar file fails while the retained story succeeds.
      permission(1, '0755');
      files[2].writeAsBytesSync(List.filled(4096, 1));
      await tester.runAsync(
          () => IslamicAudioService.instance.scanDownloadsForTesting(dirs[2]));
      permission(2, '0555');
      for (final scale in [1.0, 2.0]) {
        await mount(scale);
        await confirmBulk(success: false, pixel: 'adhkar-failed-$scale');
        expect(files[1].existsSync(), isFalse);
        expect(files[2].existsSync(), isTrue);
      }
      // A hidden retired zero-byte file must not be mistaken for success.
      permission(2, '0755');
      files[2].deleteSync();
      final retired = File('${dirs[2].path}/adhan_hussary.mp3')
        ..writeAsBytesSync([]);
      await tester.runAsync(
          () => IslamicAudioService.instance.scanDownloadsForTesting(dirs[2]));
      permission(2, '0555');
      for (final scale in [1.0, 2.0]) {
        await seedStory();
        await mount(scale);
        await confirmBulk(success: false, pixel: 'retired-zero-failed-$scale');
        expect(retired.existsSync(), isTrue);
        expect(IslamicAudioService.instance.totalDownloadedBytes, 0);
        expect(IslamicAudioService.instance.getDownloadedTracks(), isEmpty);
        expect(files[1].existsSync(), isFalse);
      }
      permission(2, '0755');
      for (final scale in [1.0, 2.0]) {
        await seedStory();
        await mount(scale);
        await confirmBulk(success: true, pixel: 'success-$scale');
        expect(retired.existsSync(), isFalse);
        expect(
            AudioDownloadService.instance.getDownloadedSurahsList(), isEmpty);
        expect(StoriesService.instance.getDownloadedStories(), isEmpty);
        expect(IslamicAudioService.instance.getDownloadedTracks(), isEmpty);
      }
    } finally {
      for (var i = 0; i < 3; i++) permission(i, '0755');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await AudioDownloadService.instance.deleteAllDownloads();
      await StoriesService.instance.deleteAllDownloadedStories();
      await IslamicAudioService.instance.deleteAllDownloadedTracks();
      semantics.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null);
      temp.deleteSync(recursive: true);
    }
  });
}
