import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/features/mushaf/memorization_screen.dart';
import 'zero_delay_owner_audit_test.dart' show RecordingPlayer;

class MemorizationPlayer extends RecordingPlayer {
  @override
  Future<void> pause() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final engine = FastAudioService.instance;
  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('memo_lifetime_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => directory.path);
    for (final family in ['Cairo', 'Amiri']) {
      await (FontLoader(family)
            ..addFont(Future.value(ByteData.sublistView(
                File('assets/fonts/$family-Regular.ttf').readAsBytesSync()))))
          .load();
    }
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty)
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
    await QuranRepository.loadSurahs();
    await QuranRepository.getAyahsForSurah(1);
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    directory.deleteSync(recursive: true);
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    engine.resetForTesting();
  });
  tearDown(engine.resetForTesting);
  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'memorization label stays with loaded voice after saved reciter changes at $scale',
        (t) async {
      final player = MemorizationPlayer();
      final boundary = GlobalKey();
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      Future<AudioSource> source(String url, String key) async =>
          AudioSource.uri(Uri.parse(url));
      final loaded = SettingsService.instance.currentReciter;
      Widget app() => RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Cairo'),
              builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(c)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: Directionality(
                      textDirection: TextDirection.rtl, child: child!)),
              home: MemorizationScreen(player: player, loadSource: source)));
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('بدء التكرار والتحفيظ'));
      await t.pumpAndSettle();
      expect(player.starts, 1);
      await SettingsService.instance.setSelectedReciter('banna');
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      expect(
          find.textContaining('القارئ: ${loaded.nameAr}', findRichText: true),
          findsOneWidget);
      expect(
          find.textContaining(
              'القارئ: ${SettingsService.instance.currentReciter.nameAr}',
              findRichText: true),
          findsNothing);
      expect(player.starts, 1);
      final dir = Platform.environment['MEMO_LIFETIME_PIXELS_DIR'];
      if (dir != null)
        await t.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/loaded-reciter-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      await t.tap(find.byTooltip('إيقاف مؤقت'));
      await t.pumpAndSettle();
      expect(
          find.textContaining('القارئ: ${loaded.nameAr}', findRichText: true),
          findsOneWidget);
      await t.tap(find.byTooltip('بدء التكرار والتحفيظ'));
      await t.pumpAndSettle();
      expect(player.starts, 2);
      expect(
          find.textContaining(
              'القارئ: ${SettingsService.instance.currentReciter.nameAr}',
              findRichText: true),
          findsOneWidget);
      await t.tap(find.byTooltip('إيقاف كامل'));
      await t.pumpAndSettle();
      await SettingsService.instance.setSelectedReciter(loaded.id);
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      expect(
          find.textContaining('القارئ: ${loaded.nameAr}', findRichText: true),
          findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  for (final action in ['stop', 'pause', 'dispose', 'other-owner']) {
    testWidgets('memorization pending source does not start after $action',
        (t) async {
      final player = MemorizationPlayer();
      final pending = Completer<AudioSource>();
      await t.pumpWidget(MaterialApp(
          home: MemorizationScreen(
              player: player, loadSource: (_, __) => pending.future)));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('بدء التكرار والتحفيظ'));
      await t.pump();
      if (action == 'dispose') {
        await t.pumpWidget(const SizedBox());
      } else if (action == 'other-owner') {
        engine.registerAudioFocus();
      } else {
        await t.tap(
            find.byTooltip(action == 'stop' ? 'إيقاف كامل' : 'إيقاف مؤقت'));
        await t.pump();
      }
      pending.complete(
          AudioSource.uri(Uri.parse('https://example.invalid/memo.mp3')));
      await t.pumpAndSettle();
      expect(player.starts, 0);
      expect(player.sourceAssignments, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
      'only newer memorization verse starts after overlapping loads and old failure',
      (t) async {
    final player = MemorizationPlayer();
    final first = Completer<AudioSource>();
    final second = Completer<AudioSource>();
    var calls = 0;
    await t.pumpWidget(MaterialApp(
        home: MemorizationScreen(
            player: player,
            loadSource: (_, __) =>
                ++calls == 1 ? first.future : second.future)));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('بدء التكرار والتحفيظ'));
    await t.pump();
    await t.tap(find.byTooltip('الآية التالية'));
    await t.pump();
    expect(calls, 2);
    second.complete(
        AudioSource.uri(Uri.parse('https://example.invalid/second.mp3')));
    await t.pumpAndSettle();
    expect(player.starts, 1);
    first.completeError(StateError('old source failed'));
    await t.pumpAndSettle();
    expect(find.byTooltip('إيقاف مؤقت'), findsOneWidget);
    expect(find.textContaining('تعذر تشغيل التلاوة'), findsNothing);
    expect(player.starts, 1);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  for (final action in ['stop', 'pause', 'dispose']) {
    testWidgets('memorization $action also cancels an in-engine source load',
        (t) async {
      final player = MemorizationPlayer()..sourceGate = Completer<void>();
      await t.pumpWidget(MaterialApp(
          home: MemorizationScreen(
              player: player,
              loadSource: (_, __) async => AudioSource.uri(
                  Uri.parse('https://example.invalid/memo.mp3')))));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('بدء التكرار والتحفيظ'));
      await t.pump();
      expect(player.sourceAssignments, 1);
      if (action == 'dispose') {
        await t.pumpWidget(const SizedBox());
      } else {
        await t.tap(
            find.byTooltip(action == 'stop' ? 'إيقاف كامل' : 'إيقاف مؤقت'));
        await t.pump();
      }
      player.sourceGate!.complete();
      await t.pumpAndSettle();
      expect(player.starts, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'active memorization source starts once and failed stop stays honest',
      (t) async {
    final player = MemorizationPlayer();
    final boundary = GlobalKey();
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Cairo'),
            builder: (c, child) => MediaQuery(
                data:
                    MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(2)),
                child: Directionality(
                    textDirection: TextDirection.rtl, child: child!)),
            home: MemorizationScreen(
                player: player,
                loadSource: (_, __) async => AudioSource.uri(
                    Uri.parse('https://example.invalid/memo.mp3'))))));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('بدء التكرار والتحفيظ'));
    await t.pumpAndSettle();
    expect(player.starts, 1);
    player.failStop = true;
    await t.tap(find.byTooltip('إيقاف كامل'));
    await t.pumpAndSettle();
    expect(find.textContaining('لم يتم تأكيد الإيقاف'), findsOneWidget);
    expect(find.byTooltip('إيقاف مؤقت'), findsOneWidget);
    expect(t.takeException(), isNull);
    final dir = Platform.environment['MEMO_LIFETIME_PIXELS_DIR'];
    if (dir != null)
      await t.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$dir/memo-stop-failure-2x.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    player.failStop = false;
    await t.pumpWidget(const SizedBox());
  });
}
