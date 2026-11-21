import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:almomin/core/models/surah.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/settings/widgets/settings_reciter_modal.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/features/mushaf/memorization_screen.dart';
import 'package:almomin/core/audio/ayah_audio_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Cairo')
          ..addFont(Future.value(ByteData.sublistView(
              File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync()))))
        .load();
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty)
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    AyahAudioPlayer.instance.resetForTesting();
    AyahAudioPlayer.instance.stopPlayerRunner = () async {};
  });
  tearDown(() => AyahAudioPlayer.instance.resetForTesting());

  test('unsupported verse reciter must not be silently routed to Minshawi',
      () async {
    await SettingsService.instance.setSelectedReciter('kurdi');
    expect(SettingsService.instance.currentReciter.hasVerseAudio, isFalse);
    expect(() => SettingsService.instance.getAyahAudioUrl(1, 2),
        throwsA(isA<VerseRecordingUnavailable>()));
    expect(SettingsService.instance.selectedReciterId, 'kurdi');
  });

  testWidgets('a supported reciter never offers another voice on verse failure',
      (t) async {
    late BuildContext context;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    }))));
    await SettingsService.instance.setSelectedReciter('husary');
    List<String>? fallbacks;
    AyahAudioPlayer.instance.playResilientRunner = (url,
        {player,
        primaryUrl,
        fallbackUrls = const [],
        cacheKey,
        localDownloadedPath,
        onStopCallback}) async {
      fallbacks = fallbackUrls;
      expect(primaryUrl, contains('/Husary_128kbps/'));
      return false;
    };
    await AyahAudioPlayer.instance.playAyah(context, 1, 2);
    expect(fallbacks, isEmpty);
    expect(SettingsService.instance.selectedReciterId, 'husary');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
      'pending verse keeps its requested identity after selection changes',
      (t) async {
    await SettingsService.instance.setSelectedReciter('husary');
    final pendingStop = Completer<void>();
    final audio = AyahAudioPlayer.instance;
    audio.stopPlayerRunner = () => pendingStop.future;
    String? actual;
    audio.playResilientRunner = (url,
        {player,
        primaryUrl,
        fallbackUrls = const [],
        cacheKey,
        localDownloadedPath,
        onStopCallback}) async {
      actual = primaryUrl;
      return false;
    };
    late BuildContext context;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    }))));
    final first = audio.playAyah(context, 1, 2);
    await t.pump();
    await SettingsService.instance.setSelectedReciter('alafasy');
    pendingStop.complete();
    await first;
    expect(actual, contains('/Husary_128kbps/'));
    expect(SettingsService.instance.selectedReciterId, 'alafasy');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('automatic next verse does not offer a different reciter',
      (t) async {
    await SettingsService.instance.setSelectedReciter('husary');
    final events = StreamController<PlayerState>.broadcast();
    final audio = AyahAudioPlayer.instance;
    audio.playerStateStreamOverride = events.stream;
    audio.loadSurahsRunner = () async => [
          const Surah(
              id: 1,
              nameAr: 'الفاتحة',
              nameSimple: 'Al-Fatihah',
              revelationPlace: 'makkah',
              revelationOrder: 5,
              ayahCount: 7,
              hasBasmala: false,
              pageStart: 1,
              pageEnd: 1)
        ];
    List<String>? fallbacks;
    audio.playResilientRunner = (url,
        {player,
        primaryUrl,
        fallbackUrls = const [],
        cacheKey,
        localDownloadedPath,
        onStopCallback}) async {
      fallbacks = fallbackUrls;
      return false;
    };
    audio.currentPlayingKey.value = '1:1';
    events.add(PlayerState(false, ProcessingState.completed));
    await t.pump();
    expect(fallbacks, isEmpty);
    await events.close();
  });

  test('unknown saved verse identity fails closed without overwriting it',
      () async {
    await SettingsService.instance.setSelectedReciter('unknown-saved-reciter');
    expect(() => SettingsService.instance.getAyahAudioUrl(1, 2),
        throwsA(isA<VerseRecordingUnavailable>()));
    expect(SettingsService.instance.selectedReciterId, 'unknown-saved-reciter');
  });

  for (final savedId in ['kurdi', 'unknown-saved-reciter']) {
    testWidgets(
        'unavailable manual verse $savedId gives explicit choice and no player call',
        (t) async {
      await SettingsService.instance.setSelectedReciter(savedId);
      var calls = 0;
      AyahAudioPlayer.instance.playResilientRunner = (url,
          {player,
          primaryUrl,
          fallbackUrls = const [],
          cacheKey,
          localDownloadedPath,
          onStopCallback}) async {
        calls++;
        return true;
      };
      late BuildContext context;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }))));
      await AyahAudioPlayer.instance.playAyah(context, 1, 2);
      await t.pump();
      expect(calls, 0);
      expect(find.textContaining('اختر قارئاً آخر بنفسك'), findsOneWidget);
      expect(AyahAudioPlayer.instance.isPlaying.value, isFalse);
      expect(SettingsService.instance.selectedReciterId, savedId);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'memorization unavailable recording is caught and choice stays saved',
      (t) async {
    await SettingsService.instance.setSelectedReciter('kurdi');
    await t.runAsync(() async {
      await QuranRepository.loadSurahs();
      await QuranRepository.getAyahsForSurah(1);
    });
    await t.pumpWidget(const MaterialApp(home: MemorizationScreen()));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('بدء التكرار والتحفيظ'));
    await t.pumpAndSettle();
    expect(find.textContaining('اختر قارئاً آخر بنفسك'), findsOneWidget);
    expect(find.byTooltip('بدء التكرار والتحفيظ'), findsOneWidget);
    expect(SettingsService.instance.selectedReciterId, 'kurdi');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('preview failure is visible without substituting another voice',
      (t) async {
    final audio = AyahAudioPlayer.instance;
    audio.playResilientRunner = (url,
            {player,
            primaryUrl,
            fallbackUrls = const [],
            cacheKey,
            localDownloadedPath,
            onStopCallback}) async =>
        false;
    late BuildContext context;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    }))));
    final reciter =
        SettingsService.availableReciters.firstWhere((r) => r.id == 'kurdi');
    await audio.previewReciterWithFeedback(context, reciter);
    await t.pump();
    expect(find.textContaining('لم يتم تشغيل قارئ بديل'), findsOneWidget);
    expect(audio.isPlaying.value, isFalse);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
      'stale preview failure does not warn about newer successful preview',
      (t) async {
    final audio = AyahAudioPlayer.instance;
    final pending = Completer<bool>();
    var calls = 0;
    audio.playResilientRunner = (url,
        {player,
        primaryUrl,
        fallbackUrls = const [],
        cacheKey,
        localDownloadedPath,
        onStopCallback}) async {
      if (++calls == 1) return await pending.future;
      return true;
    };
    late BuildContext context;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    }))));
    final first = audio.previewReciterWithFeedback(
        context, SettingsService.availableReciters[0]);
    await t.pump();
    await audio.previewReciterWithFeedback(
        context, SettingsService.availableReciters[1]);
    pending.complete(false);
    await first;
    await t.pump();
    expect(find.textContaining('لم يتم تشغيل قارئ بديل'), findsNothing);
    expect(audio.currentPlayingKey.value,
        'preview_${SettingsService.availableReciters[1].id}');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('legacy reciter modal never claims failed preview is playing',
      (t) async {
    AyahAudioPlayer.instance.playResilientRunner = (url,
            {player,
            primaryUrl,
            fallbackUrls = const [],
            cacheKey,
            localDownloadedPath,
            onStopCallback}) async =>
        false;
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Cairo'),
            builder: (c, child) => MediaQuery(
                data:
                    MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(2)),
                child: child!),
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () => showSettingsReciterModal(context),
                        child: const Text('open')))))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'الكردي');
    await t.pumpAndSettle();
    await t.tap(find.text('رعد محمد الكردي'));
    await t.pumpAndSettle();
    expect(find.textContaining('العينة متوقفة أو غير متاحة'), findsOneWidget);
    expect(find.textContaining('جاري سماع صوته الآن'), findsNothing);
    expect(SettingsService.instance.selectedReciterId, 'kurdi');
    expect(t.takeException(), isNull);
    final dir = Platform.environment['RECITER_SCREENSHOT_DIR'];
    if (dir != null)
      await t.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$dir/modal-failure-2.0.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    await t.pumpWidget(const SizedBox());
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('unavailable verse feedback is readable at $scale', (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await SettingsService.instance.setSelectedReciter('kurdi');
      final key = GlobalKey();
      late BuildContext context;
      await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
              theme: ThemeData(fontFamily: 'Cairo'),
              builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(c)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Scaffold(body: Builder(builder: (c) {
                context = c;
                return const Center(child: Text('اختبار تلاوة القارئ المختار'));
              })))));
      await AyahAudioPlayer.instance.playAyah(context, 1, 2);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('اختر قارئاً آخر بنفسك'), findsOneWidget);
      expect(t.takeException(), isNull);
      final dir = Platform.environment['RECITER_SCREENSHOT_DIR'];
      if (dir != null)
        await t.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/unavailable-verse-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      await t.pumpWidget(const SizedBox());
    });
  }

  test('Kurdi reciter preview must not offer Minshawi as its hidden fallback',
      () async {
    final reciter =
        SettingsService.availableReciters.firstWhere((r) => r.id == 'kurdi');
    List<String>? actual;
    AyahAudioPlayer.instance.playResilientRunner = (positional,
        {player,
        primaryUrl,
        fallbackUrls = const [],
        cacheKey,
        localDownloadedPath,
        onStopCallback}) async {
      actual = fallbackUrls;
      return false;
    };
    await AyahAudioPlayer.instance.playReciterPreview(reciter);
    expect(actual, isNotNull);
    expect(actual!.where((url) => url.contains('Minshawy_Murattal')), isEmpty);
  });
}
