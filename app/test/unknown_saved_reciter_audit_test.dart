import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/features/audio/audio_screen.dart';
import 'package:almomin/features/audio/widgets/recitation_reciter_selector.dart';
import 'package:almomin/features/settings/widgets/sections/settings_quran_and_audio_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/audio/ayah_audio_player.dart';
import 'package:almomin/features/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const savedId = 'removed-saved-reciter';
  late Directory directory;
  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('unknown_reciter_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => directory.path);
    await (FontLoader('Cairo')
          ..addFont(Future.value(ByteData.sublistView(
              File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync()))))
        .load();
    await (FontLoader('Amiri')
          ..addFont(Future.value(ByteData.sublistView(
              File('assets/fonts/Amiri-Regular.ttf').readAsBytesSync()))))
        .load();
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty)
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    directory.deleteSync(recursive: true);
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({'selected_reciter_id': savedId});
    await SettingsService.instance.init(forceReload: true);
    AyahAudioPlayer.instance.resetForTesting();
    AyahAudioPlayer.instance.stopPlayerRunner = () async {};
  });
  tearDown(() => AyahAudioPlayer.instance.resetForTesting());

  test(
      'unavailable saved reciter is never displayed as the first catalog voice',
      () {
    final reciter = SettingsService.instance.currentReciter;
    expect(reciter.id, savedId);
    expect(
        reciter.nameAr, isNot(SettingsService.availableReciters.first.nameAr));
    expect(reciter.hasVerseAudio, isFalse);
    expect(SettingsService.instance.selectedReciterId, savedId);
  });

  test('unknown saved whole-surah request does not return another reciter URL',
      () {
    expect(() => SettingsService.instance.getSurahAudioUrl(1),
        throwsA(isA<Exception>()));
    expect(SettingsService.instance.selectedReciterId, savedId);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('unknown saved selector is honest and recoverable at $scale',
        (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      var choices = 0;
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Cairo'),
              builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(c)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: Directionality(
                      textDirection: TextDirection.rtl, child: child!)),
              home: Scaffold(
                  body: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: RecitationReciterSelector(
                          reciter: SettingsService.instance.currentReciter,
                          onChanged: (_) => choices++,
                          onPreview: () => fail(
                              'Unavailable preview must be disabled')))))));
      await t.pumpAndSettle();
      expect(find.textContaining('القارئ المحفوظ غير متاح'), findsOneWidget);
      expect(
          t
              .widget<FilledButton>(
                  find.byKey(const ValueKey('recitation_preview_button')))
              .onPressed,
          isNull);
      expect(choices, 0);
      expect(SettingsService.instance.selectedReciterId, savedId);
      expect(t.takeException(), isNull);
      final dir = Platform.environment['UNKNOWN_RECITER_PIXELS'];
      if (dir != null)
        await t.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/unknown-selector-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('unknown legacy settings dropdown does not display first voice',
      (t) async {
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body:
                SingleChildScrollView(child: SettingsQuranAndAudioSection()))));
    await t.pumpAndSettle();
    expect(find.text('القارئ المحفوظ غير متاح'), findsWidgets);
    expect(find.textContaining('محمد صديق المنشاوي'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('whole-surah screen refuses unknown voice and preserves choice',
      (t) async {
    await t.runAsync(() => QuranRepository.loadSurahs());
    await t.pumpWidget(const MaterialApp(home: AudioScreen()));
    await t.pumpAndSettle();
    final first = find.text('سورة الفاتحة');
    await t.scrollUntilVisible(first, 250,
        scrollable: find.byType(Scrollable).first);
    await t.tap(first);
    await t.pumpAndSettle();
    expect(find.textContaining('لم يتم تشغيل قارئ بديل'), findsOneWidget);
    expect(find.byTooltip('إيقاف التلاوة'), findsNothing);
    await t.tap(first);
    await t.pumpAndSettle();
    expect(find.byTooltip('إيقاف التلاوة'), findsNothing);
    expect(SettingsService.instance.selectedReciterId, savedId);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
      'explicit choice recovers an unknown inline reciter without auto-play',
      (t) async {
    await t.runAsync(() => QuranRepository.loadSurahs());
    await t.pumpWidget(const MaterialApp(home: AudioScreen()));
    await t.pumpAndSettle();
    final fields = find.byType(DropdownButtonFormField<String>);
    await t.tap(fields.first);
    await t.pumpAndSettle();
    await t.tap(find.text('مجود').last);
    await t.pumpAndSettle();
    expect(SettingsService.instance.selectedReciterId, savedId);
    await t.tap(fields.last);
    await t.pumpAndSettle();
    await t.tap(find.text('محمد صديق المنشاوي').last);
    await t.pumpAndSettle();
    expect(SettingsService.instance.selectedReciterId, 'minshawi_mujawwad');
    expect(find.byTooltip('إيقاف التلاوة'), findsNothing);
    expect(find.textContaining('القارئ المحفوظ غير متاح'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('new settings do not preview a substituted saved reciter',
      (t) async {
    var calls = 0;
    AyahAudioPlayer.instance.playResilientRunner = (url,
        {player,
        primaryUrl,
        fallbackUrls = const [],
        localDownloadedPath,
        cacheKey,
        onStopCallback}) async {
      calls++;
      return false;
    };
    await t.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('settings_category_1')));
    await t.pumpAndSettle();
    await t.tap(find.text('استماع أو إيقاف العينة'));
    await t.pumpAndSettle();
    expect(calls, 0);
    expect(find.textContaining('غير متاح'), findsWidgets);
    expect(SettingsService.instance.selectedReciterId, savedId);
    await t.pumpWidget(const SizedBox());
  });
}
