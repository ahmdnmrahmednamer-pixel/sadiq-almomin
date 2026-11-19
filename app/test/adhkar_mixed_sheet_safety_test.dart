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

import 'package:almomin/features/audio/widgets/islamic_audio_player_sheet.dart';
import 'package:almomin/features/audio/downloads_manager_screen.dart';

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
      {Widget child = const IslamicAudioPlayerSheet(),
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
            home: Scaffold(body: child),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!))));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    const dir = String.fromEnvironment('ADHKAR_SAFETY_PIXELS_DIR');
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

  testWidgets('all initial filters never render underlying adhkar playback',
      (tester) async {
    for (final filter in [
      null,
      IslamicAudioType.adhan,
      IslamicAudioType.iqamah,
      IslamicAudioType.adhkar
    ]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await mount(tester,
          child: IslamicAudioPlayerSheet(initialFilter: filter));
      if (filter == IslamicAudioType.adhkar) {
        expect(find.byType(AdhkarAudioScreen), findsOneWidget);
      } else {
        expect(find.byType(AdhkarAudioScreen), findsNothing);
        final text = tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .toList();
        for (final track in IslamicAudioService.allTracks
            .where((t) => t.type == IslamicAudioType.adhkar)) {
          expect(text, isNot(contains(track.title)));
        }
        expect(find.text('تختلف مصادر التسجيلات وتوفرها دون إنترنت'),
            findsOneWidget);
      }
      await capture(tester, 'filter-${filter?.name ?? 'all'}-320-2');
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
      'all filter switch opens safe destination and restricted playback',
      (tester) async {
    for (final type in [
      null,
      IslamicAudioType.adhan,
      IslamicAudioType.iqamah
    ]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await mount(tester, child: IslamicAudioPlayerSheet(initialFilter: type));
      final filter = find.text('الأذكار المسموعة');
      await tester.ensureVisible(filter);
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(find.byType(AdhkarAudioScreen), findsOneWidget);
      final play = find.widgetWithText(FilledButton, 'استمع: أذكار الصباح');
      await tester.ensureVisible(play);
      await tester.tap(play);
      await tester.pumpAndSettle();
      expect(IslamicAudioService.instance.currentTrack?.id,
          AdhkarAudioScreen.tracks.first.id);
      expect(IslamicAudioService.instance.currentTrack?.remoteUrl, isNull);
      expect(IslamicAudioService.instance.queue.map((t) => t.id),
          AdhkarAudioScreen.tracks.map((t) => t.id));
      await IslamicAudioService.instance.stop();
    }
  });
  testWidgets('modal safe adhkar route scroll playback and Back dismisses',
      (tester) async {
    await mount(tester,
        child: Builder(
            builder: (context) => Scaffold(
                body: Center(
                    child: TextButton(
                        onPressed: () => IslamicAudioPlayerSheet.show(context,
                            filter: IslamicAudioType.adhkar),
                        child: const Text('فتح'))))));
    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();
    expect(find.byType(AdhkarAudioScreen), findsOneWidget);
    final list = find.descendant(
        of: find.byType(AdhkarAudioScreen), matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.text('تسجيلات تحتاج مراجعة'), 300,
        scrollable: list);
    await tester.pumpAndSettle();
    await capture(tester, 'modal-pending-320-2');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(AdhkarAudioScreen), findsNothing);
    expect(find.text('فتح'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'stored legacy download keeps bytes count delete cancellation and safe route',
      (tester) async {
    final service = IslamicAudioService.instance;
    final before = service.getDownloadedTracks().map((t) => t.id).toList();
    expect(before, contains('dua_khatm_abdulbasit'));
    await mount(tester, child: const DownloadsManagerScreen());
    await capture(tester, 'downloads-top-320-2');
    final qualifier = find.textContaining('اسم قديم في الفهرس، غير موثّق:');
    await tester.scrollUntilVisible(qualifier, 300,
        scrollable: find
            .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .first);
    await tester.pumpAndSettle();
    expect(qualifier, findsOneWidget);
    expect(find.text('ملف محفوظ لم تُراجع مطابقته للاسم. لا يُشغّل من هنا.'),
        findsOneWidget);
    await capture(tester, 'downloads-stored-320-2');
    final remove = find.byTooltip('حذف التنزيل');
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(stored.readAsBytesSync(), originalBytes);
    expect(service.getDownloadedTracks().map((t) => t.id).toList(), before);
    final open = find.widgetWithText(OutlinedButton, 'فتح الأذكار المسموعة');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.byType(AdhkarAudioScreen), findsOneWidget);
    expect(service.currentTrack?.id, isNot('dua_khatm_abdulbasit'));
    expect(stored.readAsBytesSync(), originalBytes);
    await capture(tester, 'downloads-safe-modal-320-2');
    expect(tester.takeException(), isNull);
  });
  testWidgets('downloads readable at regular width and narrow dark large text',
      (tester) async {
    for (final entry in [(412.0, 1.0, false), (320.0, 2.0, true)]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await mount(tester,
          child: const DownloadsManagerScreen(),
          width: entry.$1,
          scale: entry.$2,
          dark: entry.$3);
      await capture(
          tester, 'downloads-top-${entry.$1}-${entry.$2}-${entry.$3}');
      final qualifier = find.textContaining('اسم قديم في الفهرس، غير موثّق:');
      await tester.scrollUntilVisible(qualifier, 300,
          scrollable: find
              .byWidgetPredicate((w) =>
                  w is Scrollable && w.axisDirection == AxisDirection.down)
              .first);
      await tester.ensureVisible(
          find.widgetWithText(OutlinedButton, 'فتح الأذكار المسموعة'));
      await tester.pumpAndSettle();
      await capture(
          tester, 'downloads-card-${entry.$1}-${entry.$2}-${entry.$3}');
      expect(find.widgetWithText(OutlinedButton, 'فتح الأذكار المسموعة'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
