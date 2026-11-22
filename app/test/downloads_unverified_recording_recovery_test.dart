import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/audio_download_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/stories_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/audio/downloads_manager_screen.dart';

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
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty) {
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
    }
  });

  for (final mode in AppThemeMode.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'unverified pinned files stay discoverable and semantically deletable ${mode.name} ${scale}x',
          (tester) async {
        final root =
            Directory.systemTemp.createTempSync('unverified-download-ui-');
        final dir = Directory('${root.path}/adhkar_audio')..createSync();
        final track = IslamicAudioService.allTracks
            .firstWhere((t) => t.remoteGitBlobSha1 != null);
        final stored = File(
            '${dir.path}/${IslamicAudioService.downloadFileNameForTrack(track.id)}')
          ..writeAsBytesSync(List.filled(2048, 0));
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => root.path);
        SharedPreferences.setMockInitialValues(
            {'app_language': 'ar', 'notif_master_enabled': false});
        await SettingsService.instance.init(forceReload: true);
        final service = IslamicAudioService.instance;
        service.disableNativePlayerForTesting = true;
        await tester.runAsync(() async {
          await AudioDownloadService.instance.init();
          await StoriesService.instance.init(forceReload: true);
          await service.init();
          await service.scanDownloadsForTesting(dir);
        });
        final semantics = tester.ensureSemantics();
        final boundary = GlobalKey();
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1;
        Future<void> capture(String section) async {
          const output = String.fromEnvironment('INTEGRITY_PIXELS');
          if (output.isEmpty) return;
          await tester.runAsync(() async {
            Directory(output).createSync(recursive: true);
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$output/${mode.name}-${scale}x-$section.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        try {
          await tester.pumpWidget(RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.of(mode),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: Directionality(
                        textDirection: TextDirection.rtl, child: child!)),
                home: const DownloadsManagerScreen(),
              )));
          await tester.pumpAndSettle();
          expect(service.isDownloaded(track.id), isFalse);
          expect(service.getLocalAudioPath(track.id), isNull);
          expect(service.totalDownloadedBytes, 2048);
          expect(service.unverifiedRecordingCount, 1);
          expect(find.textContaining('إجمالي المحمل: 1 ملفات'), findsOneWidget);
          expect(find.text('لا توجد تنزيلات حالياً على الهاتف'), findsNothing);
          await capture('summary');
          final notice =
              find.textContaining('ملفات صوت لم تجتز فحص المطابقة: 1.');
          await tester.scrollUntilVisible(notice, 160,
              scrollable: find.byType(Scrollable).first);
          await tester.pumpAndSettle();
          expect(
              find.bySemanticsLabel(
                  RegExp('ملفات صوت لم تجتز فحص المطابقة: 1')),
              findsWidgets);
          expect(find.byTooltip('استماع للذكر أوفلاين'), findsNothing);
          await capture('notice');
          final bulk = find.widgetWithText(TextButton, 'حذف الكل');
          await tester.ensureVisible(bulk);
          await tester.pumpAndSettle();
          final node = tester.getSemantics(bulk);
          expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isTrue);
          tester.binding.pipelineOwner.semanticsOwner!
              .performAction(node.id, ui.SemanticsAction.tap);
          await tester.pumpAndSettle();
          expect(find.textContaining('وملفات الصوت التي لم تجتز فحص المطابقة'),
              findsOneWidget);
          await capture('confirmation');
          final dialogScroll = find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(Scrollable));
          expect(dialogScroll, findsOneWidget,
              reason:
                  'Long confirmation text must remain scrollable at large fonts');
          await tester.drag(dialogScroll, const Offset(0, -1800));
          await tester.pumpAndSettle();
          final scrollState = tester.state<ScrollableState>(dialogScroll);
          expect(scrollState.position.extentAfter, closeTo(0, 0.1));
          await capture('confirmation-end');
          await tester.tap(find.text('إلغاء'));
          await tester.pumpAndSettle();
          expect(stored.existsSync(), isTrue);
          await tester.tap(bulk);
          await tester.pumpAndSettle();
          await tester.tap(find.text('نعم، حذف الكل'));
          await tester.pumpAndSettle();
          expect(stored.existsSync(), isFalse);
          expect(service.unverifiedRecordingCount, 0);
          expect(service.totalDownloadedBytes, 0);
          expect(
              find.text('لا توجد تنزيلات حالياً على الهاتف'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pump(const Duration(seconds: 5));
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await service.deleteAllDownloadedTracks();
          semantics.dispose();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          messenger.setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'), null);
          if (root.existsSync()) root.deleteSync(recursive: true);
        }
      });
    }
  }
}
