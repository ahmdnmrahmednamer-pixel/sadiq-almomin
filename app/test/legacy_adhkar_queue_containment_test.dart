import 'dart:io';
import 'dart:async';
import 'package:just_audio/just_audio.dart';
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

class ContainmentPlayer extends AudioPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  Completer<void>? stopGate;
  Completer<void>? loadGate;
  final loadedPaths = <String>[];
  bool failStop = false;
  final operations = <String>[];
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Future<void> stop() async {
    operations.add('stop-start');
    if (failStop) throw StateError('test stop failed');
    if (stopGate != null) await stopGate!.future;
    operations.add('stop-done');
  }

  @override
  Future<void> play() async {
    operations.add('play');
  }

  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<Duration?> setFilePath(String path,
      {bool preload = true, Duration? initialPosition, dynamic tag}) async {
    operations.add('load');
    loadedPaths.add(path);
    if (loadGate != null) await loadGate!.future;
    return const Duration(seconds: 4);
  }

  @override
  Future<Duration?> setAsset(String path,
      {String? package,
      bool preload = true,
      Duration? initialPosition,
      dynamic tag}) async {
    operations.add('load');
    loadedPaths.add(path);
    if (loadGate != null) await loadGate!.future;
    return const Duration(seconds: 4);
  }

  @override
  Future<void> dispose() async {
    await states.close();
  }
}

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
    const dir = String.fromEnvironment('LEGACY_QUEUE_PIXELS_DIR');
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

  IslamicAudioTrack catalog(String id) =>
      IslamicAudioService.allTracks.firstWhere((t) => t.id == id);
  final service = IslamicAudioService.instance;

  test('exact15 held IDs exclude safe assets and all unrelated media',
      () async {
    expect(IslamicAudioService.heldLegacyAdhkarIds.length, 15);
    final expected = IslamicAudioService.allTracks
        .where((t) =>
            t.type == IslamicAudioType.adhkar &&
            t.id != 'duaa_sharawi_post_prayer')
        .map((t) => t.id)
        .toSet();
    expect(IslamicAudioService.heldLegacyAdhkarIds, expected);
    for (final t in AdhkarAudioScreen.tracks) {
      expect(IslamicAudioService.isHeldLegacyAdhkar(t), isFalse);
    }
    for (final t in IslamicAudioService.allTracks
        .where((t) => t.type != IslamicAudioType.adhkar)) {
      expect(IslamicAudioService.isHeldLegacyAdhkar(t), isFalse);
    }
    expect(
        IslamicAudioService.isHeldLegacyAdhkar(
            catalog('duaa_sharawi_post_prayer')),
        isFalse);
    final before = stored.readAsBytesSync();
    final downloaded = service.getDownloadedTracks().map((t) => t.id).toList();
    for (final id in expected) {
      await service.stop();
      await service.playTrackById(id);
      expect(service.currentTrack, isNull);
      expect(service.heldLegacyTrack?.id, id);
      await service.resume();
      expect(service.isPlaying, isFalse);
    }
    expect(stored.readAsBytesSync(), before);
    expect(service.getDownloadedTracks().map((t) => t.id).toList(), downloaded);
  });
  test(
      'mixed queue preserves allowed order and selected item; all held does not play substitute',
      () async {
    final a = catalog('adhan_makkah'),
        b = catalog('iqamah_full'),
        old = catalog('dua_khatm_abdulbasit');
    await service.playQueue([old, a, old, b], startIndex: 3);
    expect(service.queue.map((t) => t.id), [a.id, b.id]);
    expect(service.currentTrack?.id, b.id);
    expect(service.currentIndex, 1);
    await service.playPrevious();
    expect(service.currentTrack?.id, a.id);
    await service.playNext();
    expect(service.currentTrack?.id, b.id);
    await service.stop();
    await service.playQueue([old, a, b], startIndex: 0);
    expect(service.currentTrack, isNull);
    expect(service.queue.map((t) => t.id), [a.id, b.id]);
    await service.playQueue([old]);
    expect(service.queue, isEmpty);
    expect(service.currentTrack, isNull);
    await service.playNext();
    await service.playPrevious();
    await service.resume();
    expect(service.isPlaying, isFalse);
    await service.playQueue(AdhkarAudioScreen.tracks, startIndex: 2);
    expect(service.currentTrack?.id, AdhkarAudioScreen.tracks[2].id);
    expect(service.queue.map((t) => t.id),
        AdhkarAudioScreen.tracks.map((t) => t.id));
  });
  test(
      'stale next previous and lesson queue preserve intended allowed neighbor',
      () async {
    final a = catalog('adhan_makkah'),
        b = catalog('iqamah_full'),
        old = catalog('dua_khatm_abdulbasit');
    service.seedPlaybackSnapshotForTesting(
        queue: [a, old, b], currentIndex: 1, playing: true);
    await service.playNext();
    expect(service.currentTrack?.id, b.id);
    expect(service.queue.map((t) => t.id), [a.id, b.id]);
    service.seedPlaybackSnapshotForTesting(
        queue: [a, old, b], currentIndex: 1, playing: true);
    await service.playPrevious();
    expect(service.currentTrack?.id, a.id);
    await service.playLessonQueue(tracks: [old, a, b], initialTrack: b);
    expect(service.currentTrack?.id, b.id);
    expect(service.currentIndex, 1);
  });
  test('snapshot test fixture rejects production mode', () {
    service.disableNativePlayerForTesting = false;
    expect(
        () => service.seedPlaybackSnapshotForTesting(
            queue: [catalog('adhan_makkah')], currentIndex: 0, playing: true),
        throwsStateError);
    service.disableNativePlayerForTesting = true;
  });
  testWidgets(
      'stale active mini and studio stop held media and expose only clear safe entry',
      (tester) async {
    for (final dark in [false, true]) {
      for (final studio in [false, true]) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        service.seedPlaybackSnapshotForTesting(
            queue: [catalog('dua_khatm_abdulbasit'), catalog('adhan_makkah')],
            currentIndex: 0,
            playing: true);
        await mount(tester,
            child: studio
                ? const FullScreenStudioPlayer()
                : const GlobalMiniPlayerBar(),
            dark: dark);
        expect(service.currentTrack, isNull);
        expect(service.isPlaying, isFalse);
        expect(service.queue.map((t) => t.id), ['adhan_makkah']);
        expect(find.text('تسجيل قديم يحتاج مراجعة'), findsOneWidget);
        expect(find.byTooltip('استئناف'), findsNothing);
        expect(find.textContaining('حُجب تشغيل هذا التسجيل'),
            studio ? findsOneWidget : findsNothing);
        final noticeScroll = find.descendant(
            of: find.byType(LegacyAdhkarPlaybackNotice),
            matching: find.byType(Scrollable));
        tester.state<ScrollableState>(noticeScroll).position.jumpTo(0);
        await tester.pumpAndSettle();
        expect(tester.state<ScrollableState>(noticeScroll).position.pixels, 0);
        await capture(tester, 'held-$studio-$dark-320-2');
        final open =
            find.widgetWithText(OutlinedButton, 'فتح الأذكار المسموعة');
        await tester.ensureVisible(open);
        await tester.tap(open);
        await tester.pumpAndSettle();
        expect(find.byType(AdhkarAudioScreen), findsOneWidget);
        expect(service.currentTrack, isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }
  });
  test(
      'active legacy stop finishes before safe playback; completion cannot loop legacy',
      () async {
    final player = ContainmentPlayer();
    final isolatedService = IslamicAudioService.forTesting(player);
    isolatedService.disableNativePlayerForTesting = true;
    await isolatedService.init();
    isolatedService.seedPlaybackSnapshotForTesting(queue: [
      catalog('dua_khatm_abdulbasit'),
      AdhkarAudioScreen.tracks.first
    ], currentIndex: 0, playing: true);
    isolatedService.disableNativePlayerForTesting = false;
    final gate = Completer<void>();
    player.stopGate = gate;
    final stopping = isolatedService.containLegacyAdhkarPlayback();
    expect(isolatedService.currentTrack, isNull);
    expect(isolatedService.isPlaying, isFalse);
    final starting = isolatedService.playTrack(AdhkarAudioScreen.tracks.first);
    await Future<void>.delayed(Duration.zero);
    expect(player.operations, ['stop-start']);
    expect(isolatedService.currentTrack, isNull);
    gate.complete();
    await stopping;
    await starting;
    expect(player.operations.indexOf('stop-done'),
        lessThan(player.operations.indexOf('play')));
    expect(isolatedService.currentTrack?.id, AdhkarAudioScreen.tracks.first.id);
    isolatedService.disableNativePlayerForTesting = true;
    isolatedService.seedPlaybackSnapshotForTesting(
        queue: [catalog('dua_khatm_abdulbasit')],
        currentIndex: 0,
        playing: true);
    isolatedService.disableNativePlayerForTesting = false;
    isolatedService.toggleLoopMode();
    isolatedService.toggleLoopMode();
    final priorPlay = player.operations.where((o) => o == 'play').length;
    player.states.add(PlayerState(false, ProcessingState.completed));
    await Future<void>.delayed(Duration.zero);
    expect(isolatedService.currentTrack, isNull);
    expect(isolatedService.queue, isEmpty);
    expect(player.operations.where((o) => o == 'play').length, priorPlay);
    isolatedService.dispose();
  });
  test('failed legacy stop fails closed without starting any replacement',
      () async {
    final player = ContainmentPlayer()..failStop = true;
    final isolatedService = IslamicAudioService.forTesting(player);
    isolatedService.disableNativePlayerForTesting = true;
    isolatedService.seedPlaybackSnapshotForTesting(
        queue: [catalog('dua_khatm_abdulbasit')],
        currentIndex: 0,
        playing: true);
    isolatedService.disableNativePlayerForTesting = false;
    await isolatedService.containLegacyAdhkarPlayback();
    expect(isolatedService.legacyStopFailed, isTrue);
    await isolatedService.playTrack(AdhkarAudioScreen.tracks.first);
    await isolatedService.resume();
    expect(player.operations, ['stop-start']);
    expect(isolatedService.currentTrack, isNull);
    player.failStop = false;
    final gate = Completer<void>();
    player.stopGate = gate;
    final retry = isolatedService.retryLegacyPlaybackStop();
    expect(isolatedService.legacyStopPending, isTrue);
    final replacement =
        isolatedService.playTrack(AdhkarAudioScreen.tracks.first);
    await Future<void>.delayed(Duration.zero);
    expect(player.operations.where((e) => e == 'play'), isEmpty);
    gate.complete();
    await retry;
    await replacement;
    expect(isolatedService.legacyStopFailed, isFalse);
    expect(isolatedService.legacyStopPending, isFalse);
    expect(isolatedService.currentTrack?.id, AdhkarAudioScreen.tracks.first.id);
    isolatedService.dispose();
  });

  testWidgets(
      'failed native stop warning remains readable and blocks replacement action',
      (tester) async {
    await mount(tester,
        dark: true,
        child: LegacyAdhkarPlaybackNotice(
            track: catalog('dua_khatm_abdulbasit'), stopFailed: true));
    final open = find.widgetWithText(OutlinedButton, 'فتح الأذكار المسموعة');
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(open).onPressed, isNull);
    expect(find.textContaining('تعذر إيقاف الصوت الحالي'), findsOneWidget);
    await capture(tester, 'native-stop-failed-320-2');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'retry stop shows pending failure and successful unlock without native-stop claims',
      (tester) async {
    final player = ContainmentPlayer()..failStop = true;
    final isolatedService = IslamicAudioService.forTesting(player);
    isolatedService.disableNativePlayerForTesting = true;
    isolatedService.seedPlaybackSnapshotForTesting(
        queue: [catalog('dua_khatm_abdulbasit')],
        currentIndex: 0,
        playing: true);
    isolatedService.disableNativePlayerForTesting = false;
    await isolatedService.containLegacyAdhkarPlayback();
    await mount(tester,
        dark: true,
        child: AnimatedBuilder(
            animation: isolatedService,
            builder: (context, _) => LegacyAdhkarPlaybackNotice(
                track: catalog('dua_khatm_abdulbasit'),
                compact: true,
                stopFailed: isolatedService.legacyStopFailed,
                stopPending: isolatedService.legacyStopPending,
                onRetryStop: isolatedService.retryLegacyPlaybackStop)));
    final retry = find.widgetWithText(TextButton, 'إعادة محاولة الإيقاف');
    final open = find.widgetWithText(OutlinedButton, 'فتح الأذكار المسموعة');
    await capture(tester, 'retry-failure-320-2');
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(isolatedService.legacyStopFailed, isTrue);
    player.failStop = false;
    final gate = Completer<void>();
    player.stopGate = gate;
    await tester.tap(retry);
    await tester.pump();
    expect(find.text('جاري إيقاف الصوت الحالي...'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(open).onPressed, isNull);
    await capture(tester, 'retry-pending-320-2');
    gate.complete();
    await tester.pumpAndSettle();
    expect(isolatedService.legacyStopFailed, isFalse);
    expect(isolatedService.legacyStopPending, isFalse);
    expect(tester.widget<OutlinedButton>(open).onPressed, isNotNull);
    expect(find.textContaining('تعذر إيقاف'), findsNothing);
    await capture(tester, 'retry-success-320-2');
    await tester.pumpWidget(const SizedBox());
    isolatedService.dispose();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'allowed active playback survives stale mixed queue held selection without hidden UI or substitute',
      (tester) async {
    final allowed = AdhkarAudioScreen.tracks.first,
        old = catalog('dua_khatm_abdulbasit');
    service.disableNativePlayerForTesting = true;
    service.seedPlaybackSnapshotForTesting(
        queue: [allowed, old], currentIndex: 0, playing: true);
    await service.playQueue([old, allowed], startIndex: 0);
    expect(service.currentTrack?.id, allowed.id);
    expect(service.isPlaying, isTrue);
    expect(service.queue.map((t) => t.id), [allowed.id]);
    expect(service.currentIndex, 0);
    await mount(tester,
        child: const GlobalMiniPlayerBar(),
        settle: false,
        width: 800,
        scale: 1);
    expect(find.byType(LegacyAdhkarPlaybackNotice), findsNothing);
    await mount(tester,
        child: const FullScreenStudioPlayer(),
        settle: false,
        width: 800,
        scale: 1);
    expect(find.byType(LegacyAdhkarPlaybackNotice), findsNothing);
    expect(service.currentTrack?.id, allowed.id);
    await tester.pumpWidget(const SizedBox());
    await service.stop();
  });
  test(
      'held entries cannot load or play while an allowed actual source load is in flight',
      () async {
    final player = ContainmentPlayer()..loadGate = Completer<void>();
    final isolatedService = IslamicAudioService.forTesting(player);
    final allowed = AdhkarAudioScreen.tracks.first,
        old = catalog('dua_khatm_abdulbasit');
    final pending = isolatedService.playTrack(allowed);
    while (!player.operations.contains('load')) {
      await Future<void>.delayed(Duration.zero);
    }
    final before = List<String>.of(player.operations);
    await isolatedService.playQueue([old, allowed], startIndex: 0);
    await isolatedService.playTrack(old);
    await isolatedService.containLegacyAdhkarPlayback();
    expect(player.operations, before);
    expect(isolatedService.currentTrack?.id, allowed.id);
    expect(player.loadedPaths, [allowed.assetPath]);
    player.loadGate!.complete();
    await pending;
    expect(player.operations.where((e) => e == 'play').length, 1);
    expect(player.loadedPaths, [allowed.assetPath]);
    expect(isolatedService.currentTrack?.id, allowed.id);
    isolatedService.dispose();
  });
}
