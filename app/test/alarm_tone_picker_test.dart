import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/core/services/fajr_qiyam_alarm_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/prayer/fajr_qiyam_alarm_screen.dart';

class PreviewPlayer extends AudioPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final loaded = <String>[];
  bool playingValue = false;
  bool disposed = false;
  int stops = 0;
  bool failLoad = false;
  bool failPlay = false;
  bool failStop = false;
  bool failDispose = false;
  Completer<void>? pendingPlay;
  int activeLoads = 0;
  int maxActiveLoads = 0;
  Completer<void>? pendingLoad;
  Completer<void>? pendingStop;
  @override
  bool get playing => playingValue;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  void emit(bool playing, ProcessingState state) {
    playingValue = playing;
    states.add(PlayerState(playing, state));
  }

  @override
  Future<Duration?> setAsset(String assetPath,
      {String? package,
      bool preload = true,
      Duration? initialPosition,
      dynamic tag}) async {
    loaded.add(assetPath);
    ++activeLoads;
    if (activeLoads > maxActiveLoads) maxActiveLoads = activeLoads;
    try {
      if (pendingLoad != null) await pendingLoad!.future;
      if (failLoad) throw StateError('load failed');
      return const Duration(seconds: 4);
    } finally {
      --activeLoads;
    }
  }

  @override
  Future<void> play() async {
    if (failPlay) throw StateError('play failed');
    emit(true, ProcessingState.ready);
    if (pendingPlay != null) await pendingPlay!.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (failStop) throw StateError('stop failed');
    playingValue = false;
    if (pendingStop != null) await pendingStop!.future;
    if (!disposed) emit(false, ProcessingState.idle);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    if (failDispose) throw StateError('dispose failed');
    playingValue = false;
    await states.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PreviewPlayer player;
  final service = FajrQiyamAlarmService.instance;
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
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    await service.init(forceReload: true);
    IslamicAudioService.instance.disableNativePlayerForTesting = true;
    FastAudioService.instance.resetForTesting();
    player = PreviewPlayer();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async => call.method == 'initialize' ? true : null);
  });
  tearDown(() {
    FastAudioService.instance.resetForTesting();
  });

  Future<void> mount(WidgetTester tester,
      {double width = 412,
      double height = 915,
      double scale = 1,
      bool dark = false}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(
                key: const ValueKey('alarm-pixels'), child: child!)),
        home: FajrQiyamAlarmScreen(previewPlayerFactory: () => player)));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, {bool qiyam = false}) async {
    final finder =
        find.byKey(ValueKey(qiyam ? 'qiyam-tone-picker' : 'fajr-tone-picker'));
    await tester.scrollUntilVisible(finder, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  void choose(WidgetTester tester, String id) {
    tester
        .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('alarm-tone-dropdown')))
        .onChanged!(id);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    const out = String.fromEnvironment('ALARM_PIXELS_DIR');
    if (out.isEmpty) return;
    await tester.pumpAndSettle();
    final boundary =
        tester.renderObject(find.byKey(const ValueKey('alarm-pixels')))
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(out).createSync(recursive: true);
      File('$out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
      'draft and preview never persist; cancel and system back preserve both alarms',
      (tester) async {
    await mount(tester);
    await open(tester);
    choose(tester, 'takbeerat');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    expect(player.loaded.single, 'assets/audio/takbeerat.mp3');
    expect(player.playing, isTrue);
    expect(service.preFajrToneId, 'adhan_fajr');
    expect(service.qiyamToneId, 'duaa_sharawi_post_prayer');
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(player.disposed, isTrue);
    expect(player.playing, isFalse);
    expect(service.preFajrToneId, 'adhan_fajr');
    player = PreviewPlayer();
    await open(tester, qiyam: true);
    choose(tester, 'approaching_fajr');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(service.qiyamToneId, 'duaa_sharawi_post_prayer');
    expect(player.disposed, isTrue);
  });
  testWidgets(
      'all seven real options exposed; each explicit save changes only its own alarm once',
      (tester) async {
    await mount(tester);
    await open(tester);
    final dropdown = tester.widget<DropdownButton<String>>(find.descendant(
        of: find.byKey(const ValueKey('alarm-tone-dropdown')),
        matching: find.byType(DropdownButton<String>)));
    expect(dropdown.items!.map((e) => e.value),
        FajrQiyamAlarmService.availableTones.map((e) => e.id));
    int changes = 0;
    void listener() => changes++;
    service.addListener(listener);
    choose(tester, 'takbeerat');
    await tester.pumpAndSettle();
    expect(changes, 0);
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(changes, 1);
    expect(service.preFajrToneId, 'takbeerat');
    expect(service.qiyamToneId, 'duaa_sharawi_post_prayer');
    player = PreviewPlayer();
    await open(tester, qiyam: true);
    expect(
        tester
            .widget<DropdownButton<String>>(find.descendant(
                of: find.byKey(const ValueKey('alarm-tone-dropdown')),
                matching: find.byType(DropdownButton<String>)))
            .items,
        hasLength(7));
    choose(tester, 'approaching_fajr');
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(changes, 2);
    expect(service.qiyamToneId, 'approaching_fajr');
    expect(service.preFajrToneId, 'takbeerat');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('wake_pre_fajr_tone'), 'takbeerat');
    expect(prefs.getString('wake_qiyam_tone'), 'approaching_fajr');
    service.removeListener(listener);
  });
  testWidgets(
      'preview handles direct load/play failures, completion and explicit stop',
      (tester) async {
    await mount(tester);
    await open(tester);
    player.failLoad = true;
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    expect(find.textContaining('تعذر تشغيل النغمة'), findsOneWidget);
    expect(service.preFajrToneId, 'adhan_fajr');
    player.failLoad = false;
    player.failPlay = true;
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    expect(find.textContaining('تعذر تشغيل النغمة'), findsOneWidget);
    player.failPlay = false;
    choose(tester, 'approaching_fajr');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    expect(player.loaded.last, 'assets/audio/approaching_fajr.mp3');
    expect(find.text('إيقاف الاستماع'), findsOneWidget);
    player.emit(true, ProcessingState.completed);
    await tester.pumpAndSettle();
    expect(find.text('الاستماع للنغمة'), findsOneWidget);
    final loadsBeforeReplay = player.loaded.length;
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    expect(player.loaded.length, loadsBeforeReplay + 1);
    expect(player.loaded.last, 'assets/audio/approaching_fajr.mp3');
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    expect(player.playing, isFalse);
    expect(service.preFajrToneId, 'adhan_fajr');
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });
  testWidgets(
      'late loads cannot revive closed preview or stop newer audio owner',
      (tester) async {
    await mount(tester);
    await open(tester);
    final gate = Completer<void>();
    player.pendingLoad = gate;
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pump();
    final newer = PreviewPlayer();
    await FastAudioService.instance.claimAudioFocus(player: newer);
    newer.emit(true, ProcessingState.ready);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(player.disposed, isTrue);
    expect(player.playing, isFalse);
    expect(newer.playing, isTrue);
    await newer.dispose();
  });
  testWidgets(
      'changing tones invalidates old load; save stops preview before persisting',
      (tester) async {
    await mount(tester);
    await open(tester);
    final gate = Completer<void>();
    player.pendingLoad = gate;
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pump();
    choose(tester, 'takbeerat');
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(player.playing, isFalse);
    player.pendingLoad = null;
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    expect(player.loaded.last, 'assets/audio/takbeerat.mp3');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(player.disposed, isTrue);
    expect(player.playing, isFalse);
    expect(service.preFajrToneId, 'takbeerat');
  });
  testWidgets(
      'semantics activation can preview and confirm without touch gestures',
      (tester) async {
    final semantics = tester.ensureSemantics();

    await mount(tester);
    await open(tester);
    final previewNode =
        tester.getSemantics(find.byKey(const ValueKey('alarm-tone-preview')));
    expect(previewNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
        isTrue);
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(previewNode.id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(player.playing, isTrue);
    final saveNode =
        tester.getSemantics(find.widgetWithText(FilledButton, 'حفظ'));
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(saveNode.id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(player.disposed, isTrue);
    semantics.dispose();
  });
  testWidgets(
      'loaded fonts all viewport scales keep page, picker and options usable',
      (tester) async {
    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        player = PreviewPlayer();
        await mount(tester, width: width, scale: scale);
        await open(tester);
        await capture(tester, 'picker-${width.toInt()}-${scale.toInt()}');
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('alarm-tone-dropdown')));
        await tester.pumpAndSettle();
        await capture(tester, 'options-${width.toInt()}-${scale.toInt()}');
        expect(tester.takeException(), isNull);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(find.text('إلغاء'));
        await tester.pumpAndSettle();
        await capture(tester, 'page-${width.toInt()}-${scale.toInt()}');
        expect(tester.takeException(), isNull);
      }
    }
  });
  testWidgets(
      'all seven previews resolve the actual bundled tone without changing saved choices',
      (tester) async {
    await mount(tester);
    await open(tester, qiyam: true);
    for (final tone in FajrQiyamAlarmService.availableTones) {
      choose(tester, tone.id);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
      await tester.pumpAndSettle();
      final expected = tone.id == 'approaching_fajr'
          ? 'assets/audio/approaching_fajr.mp3'
          : IslamicAudioService.allTracks
              .firstWhere((track) => track.id == tone.trackId)
              .assetPath;
      expect(player.loaded.last, expected);
      expect(service.qiyamToneId, 'duaa_sharawi_post_prayer');
      expect(service.preFajrToneId, 'adhan_fajr');
    }
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(player.disposed, isTrue);
    expect(player.playing, isFalse);
  });
  testWidgets(
      'Qiyam large-text picker full collapsed name remains in semantics and options wrap',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mount(tester, width: 320, scale: 2);
    await open(tester, qiyam: true);
    expect(
        find.bySemanticsLabel(
            RegExp('.*مناجاة ودعاء الشيخ محمد متولي الشعراوي.*')),
        findsWidgets);
    await capture(tester, 'qiyam-picker-320-2');
    await tester.tap(find.byKey(const ValueKey('alarm-tone-dropdown')));
    await tester.pumpAndSettle();
    await capture(tester, 'qiyam-options-320-2');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    semantics.dispose();
  });
  testWidgets(
      'pending stop from previous tone cannot stop a newer same-player preview',
      (tester) async {
    await mount(tester);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    expect(player.playing, isTrue);
    final stopGate = Completer<void>();
    player.pendingStop = stopGate;
    choose(tester, 'takbeerat');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pump();
    final countWhileStopping = player.loaded.length;
    stopGate.complete();
    await tester.pumpAndSettle();
    expect(countWhileStopping, 1,
        reason: 'new load must wait for older stop completion');
    expect(player.loaded.last, 'assets/audio/takbeerat.mp3');
    expect(player.playing, isTrue);
    player.pendingStop = null;
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });
  testWidgets('r48 pause stops the owned alarm preview', (tester) async {
    await mount(tester);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    expect(player.playing, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    final stillPlaying = player.playing;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(stillPlaying, isFalse, reason: 'hidden alarm preview must stop');
  });
  for (final requestFocus in [true, false]) {
    testWidgets(
        'r48 Material cover requestFocus=$requestFocus stops owned preview',
        (tester) async {
      await mount(tester);
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
      await tester.pumpAndSettle();
      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      unawaited(navigator.push(MaterialPageRoute<void>(
          requestFocus: requestFocus,
          builder: (_) => const Scaffold(body: Text('cover')))));
      await tester.pumpAndSettle();
      final stillPlaying = player.playing;
      navigator.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(stillPlaying, isFalse, reason: 'covered alarm preview must stop');
    });
  }
  testWidgets('stop failure keeps a retry and blocks save until stopped',
      (tester) async {
    await mount(tester);
    await open(tester);
    choose(tester, 'takbeerat');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    player.failStop = true;
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    expect(player.playing, isTrue);
    expect(find.text('إيقاف الاستماع'), findsOneWidget);
    expect(find.textContaining('تعذر إيقاف المعاينة'), findsOneWidget);
    await capture(tester, 'stop-failure');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(service.preFajrToneId, 'adhan_fajr');
    expect(find.byKey(const ValueKey('alarm-tone-dropdown')), findsOneWidget);
    player.failStop = false;
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    expect(player.playing, isFalse);
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(service.preFajrToneId, 'takbeerat');
    expect(player.disposed, isTrue);
  });
  testWidgets('cancel independently disposes when stop is rejected',
      (tester) async {
    await mount(tester);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    player.failStop = true;
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(player.disposed, isTrue);
    expect(player.playing, isFalse);
    expect(tester.takeException(), isNull);
    expect(service.preFajrToneId, 'adhan_fajr');
  });
  testWidgets('barrier disposal independently stops when disposal is rejected',
      (tester) async {
    await mount(tester);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    player.failDispose = true;
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(player.disposed, isTrue);
    expect(player.playing, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('sequential loads avoid overlap and old load cannot play',
      (tester) async {
    await mount(tester);
    await open(tester);
    final gate = Completer<void>();
    player.pendingLoad = gate;
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pump();
    choose(tester, 'takbeerat');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pump();
    expect(player.loaded, hasLength(1));
    expect(player.playing, isFalse);
    player.pendingLoad = null;
    gate.complete();
    await tester.pumpAndSettle();
    expect(player.maxActiveLoads, 1);
    expect(player.loaded.last, 'assets/audio/takbeerat.mp3');
    expect(player.playing, isTrue);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });
  testWidgets(
      'late old play and untagged stream errors leave newer preview alone',
      (tester) async {
    await mount(tester);
    await open(tester);
    final oldPlay = Completer<void>();
    player.pendingPlay = oldPlay;
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    choose(tester, 'takbeerat');
    await tester.pumpAndSettle();
    player.pendingPlay = null;
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    oldPlay.completeError(StateError('old play error'));
    player.states.addError(StateError('untagged old stream error'));
    await tester.pumpAndSettle();
    expect(player.playing, isTrue);
    expect(player.loaded.last, 'assets/audio/takbeerat.mp3');
    expect(find.textContaining('تعذر'), findsNothing);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });
  testWidgets('disposed focus callback is inert and cannot block newer owner',
      (tester) async {
    await mount(tester);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    final stops = player.stops;
    final newer = PreviewPlayer();
    await FastAudioService.instance.claimAudioFocus(player: newer);
    newer.emit(true, ProcessingState.ready);
    await tester.pumpAndSettle();
    expect(player.stops, stops);
    expect(newer.playing, isTrue);
    await newer.dispose();
  });
  testWidgets('lifecycle invalidates pending load without resuming it',
      (tester) async {
    await mount(tester);
    await open(tester);
    final gate = Completer<void>();
    player.pendingLoad = gate;
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(player.playing, isFalse);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });
  testWidgets('rejected stop and dispose futures do not leak uncaught errors',
      (tester) async {
    await mount(tester);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    player.failStop = true;
    player.failDispose = true;
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(player.disposed, isTrue);
    expect(tester.takeException(), isNull);
    // The UI can attempt both calls, not promise silence if both are rejected.
    player.failStop = false;
    player.failDispose = false;
    await player.dispose();
  });
  testWidgets('late rejected load does not cancel the queued newer tone',
      (tester) async {
    await mount(tester);
    await open(tester);
    final gate = Completer<void>();
    player.pendingLoad = gate;
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pump();
    choose(tester, 'takbeerat');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pump();
    player.pendingLoad = null;
    gate.completeError(StateError('late load error'));
    await tester.pumpAndSettle();
    expect(player.playing, isTrue);
    expect(player.loaded.last, 'assets/audio/takbeerat.mp3');
    expect(find.textContaining('تعذر'), findsNothing);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });
  testWidgets('paused old dialog does not stop newer global owner',
      (tester) async {
    await mount(tester);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    final newer = PreviewPlayer();
    await FastAudioService.instance.claimAudioFocus(player: newer);
    newer.emit(true, ProcessingState.ready);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(newer.playing, isTrue);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(newer.playing, isTrue);
    await newer.dispose();
  });
  testWidgets('descendant focus does not stop owned preview', (tester) async {
    await mount(tester);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('حفظ'))).requestFocus();
    await tester.pumpAndSettle();
    expect(player.playing, isTrue);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });
  testWidgets(
      'narrow large text stop error and retry remain readable in both themes',
      (tester) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      player = PreviewPlayer();
      await mount(tester, width: 320, height: 640, scale: 2, dark: dark);
      await open(tester);
      await tester
          .ensureVisible(find.byKey(const ValueKey('alarm-tone-preview')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
      await tester.pumpAndSettle();
      player.failStop = true;
      await tester.tap(find.byKey(const ValueKey('alarm-tone-preview')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.textContaining('تعذر إيقاف المعاينة'));
      await tester.pumpAndSettle();
      await capture(tester, 'stop-error-320-2-$dark');
      expect(tester.takeException(), isNull);
      expect(find.text('إيقاف الاستماع'), findsOneWidget);
      player.failStop = false;
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
    }
  });
}
