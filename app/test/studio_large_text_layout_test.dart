import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/adhkar_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/adhkar/adhkar_audio_screen.dart';

import 'package:almomin/features/audio/widgets/full_screen_studio_player.dart';
import 'package:almomin/features/audio/widgets/global_mini_player_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory isolated;
  late File stored;
  late List<int> originalBytes;
  setUpAll(() async {
    isolated = Directory.systemTemp.createTempSync('adhkar_safety_test_');
    final dir = Directory('${isolated.path}/adhkar_audio')..createSync();
    stored = File('${dir.path}/dua_khatm_abdulbasit.mp3');
    originalBytes = List.generate(2048, (i) => i % 251);
    stored.writeAsBytesSync(originalBytes);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => isolated.path);

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
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    isolated.deleteSync(recursive: true);
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'has_completed_onboarding': true, 'show_tutorial_screens': false});
    await SettingsService.instance.init(forceReload: true);
    await AdhkarService.instance.init(forceReload: true);
    IslamicAudioService.instance.disableNativePlayerForTesting = true;
    await IslamicAudioService.instance.stop();
    await IslamicAudioService.instance.init();
  });

  Future<void> mount(WidgetTester tester,
      {Widget child = const GlobalMiniPlayerBar(),
      double width = 320,
      double scale = 2,
      bool dark = false,
      bool settle = true}) async {
    tester.view.physicalSize = Size(width, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('separation-pixels'),
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            home: Scaffold(body: child),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!))));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> capture(WidgetTester tester, String name) async {
    const dir = String.fromEnvironment('STUDIO38_PIXELS_DIR');
    if (dir.isEmpty) return;
    final boundary =
        tester.renderObject(find.byKey(const ValueKey('separation-pixels')))
            as RenderRepaintBoundary;
    boundary.markNeedsPaint();
    await tester.pump();
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('normal studio stays within narrow large-text viewport',
      (tester) async {
    final service = IslamicAudioService.instance;
    final allowed = AdhkarAudioScreen.tracks.first;
    service.seedPlaybackSnapshotForTesting(
        queue: [allowed], currentIndex: 0, playing: false);
    for (final (width, scale) in [(320.0, 2.0), (360.0, 1.0)]) {
      for (final dark in [false, true]) {
        await tester.pumpWidget(const SizedBox());
        await mount(tester,
            child: const FullScreenStudioPlayer(),
            dark: dark,
            width: width,
            scale: scale);
        await capture(tester,
            'normal-studio-top-$dark-${width.toInt()}-${scale.toInt()}');
        expect(tester.takeException(), isNull);
        for (final tip in ['تصغير المشغل', 'قائمة التشغيل']) {
          final bounds = tester.getRect(find.byTooltip(tip));
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(width));
          expect(
              tester
                  .widget<IconButton>(find.widgetWithIcon(
                      IconButton,
                      tip == 'قائمة التشغيل'
                          ? Icons.queue_music_rounded
                          : Icons.keyboard_arrow_down_rounded))
                  .onPressed,
              isNotNull);
        }
        await tester.tap(find.byTooltip('قائمة التشغيل'));
        await tester.pumpAndSettle();
        expect(find.text('قائمة التشغيل الحالية'), findsOneWidget);
        await capture(tester,
            'normal-studio-queue-$dark-${width.toInt()}-${scale.toInt()}');
        expect(tester.takeException(), isNull);
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byTooltip('خلط المقاطع'));
        await tester.pumpAndSettle();
        await capture(tester,
            'normal-studio-controls-$dark-${width.toInt()}-${scale.toInt()}');
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('downloadable track toolbar remains usable at320 and2x',
      (tester) async {
    const track = IslamicAudioTrack(
        id: 'studio_layout_fixture',
        title: 'عنوان طويل لمقطع تجريبي',
        subtitle: 'اسم المتحدث للتجربة',
        type: IslamicAudioType.lesson,
        remoteUrl: 'https://example.invalid/audio.mp3',
        durationFormatted: '10:00');
    final service = IslamicAudioService.instance;
    service.seedPlaybackSnapshotForTesting(
        queue: [track], currentIndex: 0, playing: false);
    await mount(tester, child: const FullScreenStudioPlayer());
    await tester.ensureVisible(find.byTooltip('مشاركة التلاوة'));
    await tester.pumpAndSettle();
    await capture(tester, 'normal-studio-download-controls-320-2');
    expect(find.text('تحميل'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('speed and sleep sheets remain reachable at320 and2x',
      (tester) async {
    final service = IslamicAudioService.instance;
    final allowed = AdhkarAudioScreen.tracks.first;
    service.seedPlaybackSnapshotForTesting(
        queue: [allowed], currentIndex: 0, playing: false);
    await mount(tester, child: const FullScreenStudioPlayer());
    await tester.ensureVisible(find.text('1.0x'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.0x'));
    await tester.pumpAndSettle();
    expect(find.text('سرعة التلاوة والصوت'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('1.25x'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('مؤقت'));
    await tester.tap(find.text('مؤقت'));
    await tester.pumpAndSettle();
    await capture(tester, 'normal-studio-sleep-sheet-320-2');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('15 دقيقة'));
    await tester.pumpAndSettle();
    expect(service.sleepTimerMinutes, 15);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining(RegExp(r'^\d+د$')));
    await tester.tap(find.textContaining(RegExp(r'^\d+د$')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('إلغاء المؤقت'));
    await capture(tester, 'normal-studio-active-sleep-320-2');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('إلغاء المؤقت'));
    await tester.pumpAndSettle();
    expect(service.sleepTimerMinutes, isNull);
    await tester.ensureVisible(find.text('مؤقت'));
    await tester.tap(find.text('مؤقت'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('عند نهاية السورة/المقطع'));
    await capture(tester, 'normal-studio-sleep-end-320-2');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('عند نهاية السورة/المقطع'));
    await tester.pumpAndSettle();
    expect(service.sleepTimerMinutes, 999);
    service.cancelSleepTimer();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('actual studio sheet minimize action still closes the sheet',
      (tester) async {
    final service = IslamicAudioService.instance;
    service.seedPlaybackSnapshotForTesting(
        queue: [AdhkarAudioScreen.tracks.first],
        currentIndex: 0,
        playing: false);
    await mount(tester,
        child: Builder(
            builder: (context) => TextButton(
                onPressed: () => FullScreenStudioPlayer.show(context),
                child: const Text('open'))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenStudioPlayer), findsOneWidget);
    await tester.tap(find.byTooltip('تصغير المشغل'));
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenStudioPlayer), findsNothing);
    expect(service.currentTrack?.id, AdhkarAudioScreen.tracks.first.id);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
