import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/router.dart';
import 'package:almomin/core/services/adhkar_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/adhkar/adhkar_audio_screen.dart';
import 'package:almomin/features/adhkar/adhkar_screen.dart';
import 'package:almomin/features/adhkar/adhkar_hub_screen.dart';
import 'package:almomin/features/adhkar/widgets/sharawi_post_prayer_card.dart';

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
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'has_completed_onboarding': true, 'show_tutorial_screens': false});
    await SettingsService.instance.init(forceReload: true);
    await AdhkarService.instance.init(forceReload: true);
    IslamicAudioService.instance.disableNativePlayerForTesting = true;
    await IslamicAudioService.instance.stop();
  });

  Future<void> mount(WidgetTester tester,
      {Widget child = const AdhkarAudioScreen(),
      double width = 320,
      double scale = 2,
      bool dark = false}) async {
    tester.view.physicalSize = Size(width, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('separation-pixels'),
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            home: child,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!))));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    const dir = String.fromEnvironment('ADHKAR_SEPARATION_PIXELS_DIR');
    if (dir.isEmpty) return;
    final boundary =
        tester.renderObject(find.byKey(const ValueKey('separation-pixels')))
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  test('four neutral local tracks have no remote or catalog-cache identity',
      () {
    expect(AdhkarAudioScreen.tracks.length, 4);
    expect(AdhkarAudioScreen.pendingTracks.length, 12);
    expect(
        IslamicAudioService.allTracks
            .where((t) => t.type == IslamicAudioType.adhkar)
            .length,
        16);
    for (final t in AdhkarAudioScreen.tracks) {
      expect(t.remoteUrl, isNull);
      expect(t.fallbackUrls, isEmpty);
      expect(File(t.assetPath!).existsSync(), isTrue);
      expect(
          IslamicAudioService.allTracks.any((old) => old.id == t.id), isFalse);
      expect(t.muezzinName, isNull);
      expect(t.quality, isEmpty);
    }
  });
  testWidgets('audio loaded-font layouts across widths scales and themes',
      (tester) async {
    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          await mount(tester, width: width, scale: scale, dark: dark);
          await capture(tester,
              'audio-${width.toInt()}-${scale.toInt()}-${dark ? 'dark' : 'light'}');
          expect(tester.takeException(), isNull);
        }
      }
    }
  });
  testWidgets(
      'semantic playback pause resume queue and stop preserve asset-only source',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mount(tester);
    final button = find.widgetWithText(FilledButton, 'استمع: أذكار الصباح');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    final node = tester.getSemantics(button);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(node.id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();
    final service = IslamicAudioService.instance;
    expect(service.currentTrack?.id, AdhkarAudioScreen.tracks.first.id);
    expect(service.currentTrack?.remoteUrl, isNull);
    expect(service.isPlaying, isTrue);
    await capture(tester, 'playing-320-2');
    final pause = find.widgetWithText(FilledButton, 'إيقاف مؤقت: أذكار الصباح');
    await tester.ensureVisible(pause);
    await tester.pumpAndSettle();
    await tester.tap(pause);
    await tester.pumpAndSettle();
    expect(service.isPlaying, isFalse);
    await capture(tester, 'paused-320-2');
    await tester.tap(find.widgetWithText(FilledButton, 'استمع: أذكار الصباح'));
    await tester.pumpAndSettle();
    expect(service.isPlaying, isTrue);
    await service.playNext();
    await tester.pumpAndSettle();
    expect(service.currentTrack?.id, AdhkarAudioScreen.tracks[1].id);
    expect(service.currentTrack?.fallbackUrls, isEmpty);
    final stop = find.widgetWithText(OutlinedButton, 'إيقاف التشغيل الحالي');
    await tester.scrollUntilVisible(stop, -300);
    await tester.pumpAndSettle();
    await capture(tester, 'stop-control-320-2');
    await tester.tap(stop);
    await tester.pumpAndSettle();
    expect(service.currentTrack, isNull);
    semantics.dispose();
  });
  testWidgets(
      'unreviewed records remain visible disabled without false playable claim',
      (tester) async {
    await mount(tester);
    final text =
        find.text('المصدر الذي فُحص تلاوة لسورة الناس، وليس دعاء ختم القرآن.');
    await tester.scrollUntilVisible(text, 400);
    await tester.pumpAndSettle();
    expect(text, findsOneWidget);
    await capture(tester, 'pending-320-2');
    final buttons = tester.widgetList<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'الاستماع والتحميل غير متاحين'));
    expect(buttons.isNotEmpty, isTrue);
    expect(buttons.every((b) => b.onPressed == null), isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('preexisting other playback gets neutral stop control',
      (tester) async {
    await IslamicAudioService.instance
        .playTrack(IslamicAudioService.allTracks.first);
    await mount(tester);
    expect(find.text('يوجد تشغيل من قسم آخر. لم تُراجع هويته هنا.'),
        findsOneWidget);
    final stop = find.widgetWithText(OutlinedButton, 'إيقاف التشغيل الحالي');
    await tester.scrollUntilVisible(stop, -300);
    await tester.tap(stop);
    await tester.pumpAndSettle();
    expect(IslamicAudioService.instance.currentTrack, isNull);
  });
  testWidgets(
      'written postprayer retains two exact prayer texts and copy share with no audio',
      (tester) async {
    await mount(tester, child: const AdhkarScreen(initialCategoryIndex: 2));
    final card = find.byType(SharawiPostPrayerDuaaCard);
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await capture(tester, 'written-postprayer-320-2');
    expect(tester.widget<SharawiPostPrayerDuaaCard>(card).textOnly, isTrue);
    expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
    expect(find.byType(IconButton), findsWidgets);
    expect(find.byTooltip('السبحة الإلكترونية'), findsOneWidget);
    final first = tester
        .widgetList<SelectableText>(
            find.descendant(of: card, matching: find.byType(SelectableText)))
        .first
        .data!;
    expect(first, contains('اللَّهُمَّ رَبَّ هَذِهِ الدَّعْوَةِ'));
    final secondTab =
        find.widgetWithText(OutlinedButton, 'دعاء ختام الصلاة والمناجاة');
    await tester.ensureVisible(secondTab);
    await tester.tap(secondTab);
    await tester.pumpAndSettle();
    final second = tester
        .widgetList<SelectableText>(
            find.descendant(of: card, matching: find.byType(SelectableText)))
        .first
        .data!;
    expect(second, contains('اللَّهُمَّ يَا رَبَّنَا'));
    expect(second, isNot(first));
    expect(
        find.descendant(
            of: card, matching: find.widgetWithText(OutlinedButton, 'نسخ')),
        findsOneWidget);
    expect(
        find.descendant(
            of: card, matching: find.widgetWithText(OutlinedButton, 'مشاركة')),
        findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('isolated audio route back and written route remain distinct',
      (tester) async {
    appRouter.go('/adhkar-hub');
    await tester.pumpWidget(MaterialApp.router(routerConfig: appRouter));
    await tester.pumpAndSettle();
    final entry = find.text('الأذكار المسموعة');
    await tester.scrollUntilVisible(entry, 300);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(AdhkarAudioScreen), findsOneWidget);
    expect(find.byType(AdhkarScreen), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(AdhkarHubScreen), findsOneWidget);
    expect(find.byType(AdhkarAudioScreen), findsNothing);
  });
}
