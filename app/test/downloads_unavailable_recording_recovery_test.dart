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
      'unavailable-current files stay discoverable with retired files and retryable',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('unavailable-hub-recovery-');
    final dir = Directory('${temp.path}/adhkar_audio')..createSync();
    final first = File('${dir.path}/adhan_sudais.mp3')
      ..writeAsBytesSync(List.filled(2048, 1));
    final second = File('${dir.path}/adhan_shuraim.mp3')
      ..writeAsBytesSync(List.filled(4096, 2));
    final retired = File('${dir.path}/adhan_hussary.mp3');
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
    final service = IslamicAudioService.instance;
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
      final path = Platform.environment['UNAVAILABLE_PIXELS'];
      if (path == null) return;
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    Future<void> openBulk() async {
      final button = find.widgetWithText(TextButton, 'حذف الكل');
      expect(button, findsOneWidget,
          reason: 'Unavailable indexed files must keep DeleteAll available');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.textContaining('وملفات التسجيل غير المتاحة للتشغيل'),
          findsOneWidget);
      expect(
          find.textContaining(
              'قد لا تتمكن من استعادة ملفات التسجيل غير المتاحة'),
          findsOneWidget);
      await capture('confirmation');
    }

    Future<void> confirm(bool success, String pixel) async {
      await openBulk();
      await tester.tap(find.text('نعم، حذف الكل'));
      await tester.pumpAndSettle();
      expect(
          find.text(success
              ? 'تم حذف جميع التنزيلات بنجاح'
              : 'تعذر حذف بعض الملفات. حاول مرة أخرى.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(pixel);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }

    try {
      expect(service.getDownloadedTracks(), isEmpty);
      expect(service.totalDownloadedBytes, 6144);
      expect(service.unavailableRecordingCount, 2);
      expect(service.retiredRecordingCount, 0);
      for (final id in ['adhan_sudais', 'adhan_shuraim']) {
        expect(service.isDownloaded(id), isFalse);
        expect(service.getLocalAudioPath(id), isNull);
        expect(IslamicAudioService.unavailableRecordingReason(id), isNotNull);
      }
      for (final scale in [1.0, 2.0]) {
        await mount(scale);
        expect(find.textContaining('إجمالي المحمل: 2 ملفات'), findsOneWidget);
        expect(find.text('لا توجد تنزيلات حالياً على الهاتف'), findsNothing);
        final notice =
            find.textContaining('ملفات تسجيل غير متاحة للتشغيل محفوظة: 2.');
        await tester.scrollUntilVisible(notice, 150,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        expect(
            find.bySemanticsLabel(
                RegExp('ملفات تسجيل غير متاحة للتشغيل محفوظة: 2')),
            findsWidgets);
        expect(find.byTooltip('استماع للذكر أوفلاين'), findsNothing);
        expect(find.byTooltip('حذف التنزيل'), findsNothing);
        await capture('notice-$scale');
        await openBulk();
        await tester.tap(find.text('إلغاء'));
        await tester.pumpAndSettle();
        expect(first.lengthSync(), 2048);
        expect(second.lengthSync(), 4096);
        expect(Process.runSync('chmod', ['0555', dir.path]).exitCode, 0);
        await confirm(false, 'failure-$scale');
        expect(find.widgetWithText(TextButton, 'حذف الكل'), findsOneWidget);
        expect(first.existsSync(), isTrue);
        expect(second.existsSync(), isTrue);
        expect(service.unavailableRecordingCount, 2);
        expect(Process.runSync('chmod', ['0755', dir.path]).exitCode, 0);
      }
      // Mixed cohorts must count once each without making held audio playable.
      retired.writeAsBytesSync([]);
      await tester.runAsync(() => service.scanDownloadsForTesting(dir));
      for (final scale in [1.0, 2.0]) {
        await mount(scale);
        expect(service.unavailableRecordingCount, 2);
        expect(service.retiredRecordingCount, 1);
        expect(service.totalDownloadedBytes, 6144);
        expect(service.getDownloadedTracks(), isEmpty);
        expect(find.textContaining('إجمالي المحمل: 3 ملفات'), findsOneWidget);
        expect(find.textContaining('ملفات تسجيل قديمة محفوظة: 1.'),
            findsOneWidget);
        final notice =
            find.textContaining('ملفات تسجيل غير متاحة للتشغيل محفوظة: 2.');
        await tester.scrollUntilVisible(notice, 150,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        await capture('mixed-notice-$scale');
        await openBulk();
        expect(find.textContaining('غير المتاحة أو القديمة بعد حذفها'),
            findsOneWidget);
        await capture('mixed-confirmation-$scale');
        await tester.tap(find.text('إلغاء'));
        await tester.pumpAndSettle();
        expect(retired.existsSync(), isTrue);
      }
      for (final scale in [1.0, 2.0]) {
        if (!first.existsSync()) {
          first.writeAsBytesSync(List.filled(2048, 1));
          second.writeAsBytesSync(List.filled(4096, 2));
          retired.writeAsBytesSync([]);
          await tester.runAsync(() => service.scanDownloadsForTesting(dir));
        }
        await mount(scale);
        await confirm(true, 'success-$scale');
        expect(first.existsSync(), isFalse);
        expect(second.existsSync(), isFalse);
        expect(retired.existsSync(), isFalse);
        expect(service.unavailableRecordingCount, 0);
        expect(service.retiredRecordingCount, 0);
        expect(find.text('لا توجد تنزيلات حالياً على الهاتف'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'حذف الكل'), findsNothing);
      }
    } finally {
      Process.runSync('chmod', ['0755', dir.path]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await service.deleteAllDownloadedTracks();
      semantics.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null);
      temp.deleteSync(recursive: true);
    }
  });
}
