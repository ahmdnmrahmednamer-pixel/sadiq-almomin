import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/audio/ayah_audio_player.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/features/settings/widgets/settings_reciter_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final boundary = GlobalKey();
  setUpAll(() async {
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
  });
  final audio = AyahAudioPlayer.instance;
  final engine = FastAudioService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    audio.resetForTesting();
    engine.resetForTesting();
    audio.stopPlayerRunner = () async {};
  });
  tearDown(() {
    audio.resetForTesting();
    engine.resetForTesting();
  });
  Future<void> mount(WidgetTester t, {double scale = 1}) async {
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
                data: MediaQuery.of(c)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: Directionality(
                    textDirection: TextDirection.rtl, child: child!)),
            home: Scaffold(
                body: Builder(
                    builder: (c) => TextButton(
                        onPressed: () => showSettingsReciterModal(c),
                        child: const Text('open')))))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'Warsh catalog entry never receives a blanket Hafs badge at $scale',
        (t) async {
      await mount(t, scale: scale);
      await t.enterText(find.byType(TextField), 'الكوشي');
      await t.pumpAndSettle();
      expect(find.text('العيون الكوشي (رواية ورش)'), findsOneWidget);
      expect(find.text('رواية حفص عن عاصم'), findsNothing);
      expect(t.takeException(), isNull);
      final dir = Platform.environment['RECITER_MODAL_PIXELS_DIR'];
      if (dir != null)
        await t.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/warsh-modal-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets('accepted preview keeps playing after the picker closes itself',
      (t) async {
    audio.playResilientRunner = (url,
            {player,
            primaryUrl,
            fallbackUrls = const [],
            cacheKey,
            localDownloadedPath,
            onStopCallback}) async =>
        true;
    await mount(t);
    await t.enterText(find.byType(TextField), 'الكردي');
    await t.pumpAndSettle();
    await t.tap(find.text('رعد محمد الكردي'));
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(audio.currentPlayingKey.value, 'preview_kurdi');
    expect(audio.isPlaying.value, isTrue);
    expect(find.textContaining('تم تشغيل عينته'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('pending picker selection cannot be replaced by another card tap',
      (t) async {
    final pending = Completer<bool>();
    var calls = 0;
    audio.playResilientRunner = (url,
        {player,
        primaryUrl,
        fallbackUrls = const [],
        cacheKey,
        localDownloadedPath,
        onStopCallback}) {
      calls++;
      return pending.future;
    };
    await mount(t);
    await t.enterText(find.byType(TextField), 'الكردي');
    await t.pumpAndSettle();
    await t.tap(find.text('رعد محمد الكردي'));
    await t.pump();
    await t.enterText(find.byType(TextField), 'الكوشي');
    await t.pumpAndSettle();
    final card = find
        .ancestor(
            of: find.text('العيون الكوشي (رواية ورش)'),
            matching: find.byType(InkWell))
        .first;
    expect(t.widget<InkWell>(card).onTap, isNull);
    await t.tap(find.text('العيون الكوشي (رواية ورش)'));
    await t.pump();
    expect(SettingsService.instance.selectedReciterId, 'kurdi');
    expect(calls, 1);
    Navigator.of(t.element(find.byType(BottomSheet))).pop();
    await t.pumpAndSettle();
    pending.complete(false);
    await t.pumpAndSettle();
    expect(audio.currentPlayingKey.value, isNull);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  for (final replace in [false, true]) {
    testWidgets(
        'dismissed picker cancels only its pending preview, replacement=$replace',
        (t) async {
      await mount(t);
      final pending = Completer<AudioSource>();
      final entered = Completer<void>();
      var assignments = 0;
      engine.getFastAudioSourceOverride = (url,
          {required cacheKey, localDownloadedPath, isLiveStream = false}) {
        if (!entered.isCompleted) entered.complete();
        return pending.future;
      };
      engine.setAudioSourceOverride = (_, __) async {
        assignments++;
        throw StateError('cancelled preview must not assign');
      };
      await t.enterText(find.byType(TextField), 'الكردي');
      await t.pumpAndSettle();
      await t.tap(find.text('رعد محمد الكردي'));
      await t
          .runAsync(() => entered.future.timeout(const Duration(seconds: 2)));
      if (replace) {
        audio.playResilientRunner = (url,
                {player,
                primaryUrl,
                fallbackUrls = const [],
                cacheKey,
                localDownloadedPath,
                onStopCallback}) async =>
            true;
        expect(
            await audio
                .playReciterPreview(SettingsService.availableReciters.first),
            isTrue);
      }
      Navigator.of(t.element(find.byType(BottomSheet))).pop();
      await t.pumpAndSettle();
      pending.complete(
          AudioSource.uri(Uri.parse('https://example.invalid/recording.mp3')));
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pumpAndSettle();
      expect(assignments, 0);
      expect(audio.currentPlayingKey.value,
          replace ? 'preview_minshawi_murattal' : null);
      expect(audio.isPlaying.value, replace);
      expect(find.textContaining('تم تشغيل عينته'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
