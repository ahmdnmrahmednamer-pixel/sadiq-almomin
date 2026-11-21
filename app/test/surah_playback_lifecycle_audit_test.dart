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
import 'package:almomin/features/audio/audio_screen.dart';
import 'zero_delay_owner_audit_test.dart' show RecordingPlayer;

class CompletingSurahPlayer extends RecordingPlayer {
  final states = StreamController<PlayerState>.broadcast();
  final sources = <AudioSource>[];
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Future<Duration?> setAudioSource(AudioSource source,
      {bool preload = true, int? initialIndex, Duration? initialPosition}) {
    sources.add(source);
    return super.setAudioSource(source,
        preload: preload,
        initialIndex: initialIndex,
        initialPosition: initialPosition);
  }

  @override
  Future<void> dispose() async {
    await states.close();
    await super.dispose();
  }
}

class ResumeSurahPlayer extends RecordingPlayer {
  final positions = StreamController<Duration>.broadcast();
  Duration? loadedPosition;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Future<Duration?> setAudioSource(AudioSource source,
      {bool preload = true, int? initialIndex, Duration? initialPosition}) {
    loadedPosition = initialPosition;
    return super.setAudioSource(source,
        preload: preload,
        initialIndex: initialIndex,
        initialPosition: initialPosition);
  }

  @override
  Future<void> dispose() async {
    await positions.close();
    await super.dispose();
  }
}

class StatefulSurahPlayer extends ResumeSurahPlayer {
  bool active = false;
  bool failPause = false;
  Completer<void>? pauseGate;
  @override
  bool get playing => active;
  @override
  Future<void> play() async {
    active = true;
    await super.play();
  }

  @override
  Future<void> stop() async {
    await super.stop();
    active = false;
  }

  @override
  Future<void> pause() async {
    if (failPause) throw StateError('pause failed');
    active = false;
    await pauseGate?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final boundary = GlobalKey();
  final engine = FastAudioService.instance;
  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('surah_lifecycle_');
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
  Future<void> mount(WidgetTester t, RecordingPlayer player,
      {double scale = 1}) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.runAsync(() => engine.init());
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
            home: AudioScreen(player: player))));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('سورة الفاتحة'), 250,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    await t.tap(find.text('سورة الفاتحة'));
    await t.pump();
    await t.runAsync(() async {
      for (var i = 0; i < 30 && player.sourceAssignments == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await t.pump();
    if (player.sourceAssignments == 0) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump();
    }
    expect(player.sourceAssignments, 1);
  }

  for (final action in ['stop', 'dispose', 'success']) {
    testWidgets('pre-engine whole-surah source control $action', (t) async {
      final player = RecordingPlayer();
      final pending = Completer<AudioSource>();
      await t.pumpWidget(MaterialApp(
          home: AudioScreen(
              player: player, loadSource: (_, __) => pending.future)));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('سورة الفاتحة'), 250,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      await t.tap(find.text('سورة الفاتحة'));
      await t.pump();
      if (action == 'stop') {
        await t.tap(find.byTooltip('إيقاف التلاوة'));
        await t.pump();
      }
      if (action == 'dispose') await t.pumpWidget(const SizedBox());
      pending.complete(
          AudioSource.uri(Uri.parse('https://example.invalid/pending.mp3')));
      await t.pumpAndSettle();
      expect(player.starts, action == 'success' ? 1 : 0);
      expect(player.sourceAssignments, action == 'success' ? 1 : 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  for (final phase in ['initial-stop', 'source']) {
    testWidgets(
        'pre-engine whole-surah load cannot reclaim focus during $phase',
        (t) async {
      final player = RecordingPlayer();
      final pending = Completer<AudioSource>();
      if (phase == 'initial-stop') player.blockedStop = Completer<void>();
      await t.pumpWidget(MaterialApp(
          home: AudioScreen(
              player: player, loadSource: (_, __) => pending.future)));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('سورة الفاتحة'), 250,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      await t.tap(find.text('سورة الفاتحة'));
      await t.pump();
      final newer = engine.registerAudioFocus();
      if (phase == 'initial-stop') {
        player.blockedStop!.complete();
        await t.pump();
      }
      pending.complete(
          AudioSource.uri(Uri.parse('https://example.invalid/pending.mp3')));
      await t.pumpAndSettle();
      expect(player.starts, 0);
      expect(player.sourceAssignments, 0);
      expect(engine.activePlaybackToken, newer);
      expect(find.textContaining('بدء تشغيل سورة'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  for (final action in ['stop', 'dispose', 'other-owner']) {
    testWidgets('whole-surah pending source cannot start after $action',
        (t) async {
      final player = RecordingPlayer()..sourceGate = Completer<void>();
      await mount(t, player);
      if (action == 'stop') {
        await t.tap(find.byTooltip('إيقاف التلاوة'));
        await t.pump();
      } else if (action == 'dispose') {
        await t.pumpWidget(const SizedBox());
      } else {
        engine.registerAudioFocus();
      }
      player.sourceGate!.complete();
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pumpAndSettle();
      expect(player.starts, 0);
      expect(find.textContaining('بدء تشغيل سورة'), findsNothing);
      expect(find.byTooltip('إيقاف التلاوة'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
      'browsing another reciter never relabels the loaded whole-surah voice',
      (t) async {
    final player = RecordingPlayer();
    await mount(t, player);
    await t.pumpAndSettle();
    expect(player.starts, 1);
    await t.drag(find.byType(CustomScrollView), const Offset(0, 1000));
    await t.pumpAndSettle();
    final fields = find.byType(DropdownButtonFormField<String>);
    await t.ensureVisible(fields.first);
    await t.tap(fields.first);
    await t.pumpAndSettle();
    await t.tap(find.text('مجود').last);
    await t.pumpAndSettle();
    await t.tap(fields.last);
    await t.pumpAndSettle();
    await t.tap(find.text('محمد صديق المنشاوي').last);
    await t.pumpAndSettle();
    final stop = find.byTooltip('إيقاف التلاوة');
    final bar = find.ancestor(of: stop, matching: find.byType(Column)).first;
    expect(
        find.descendant(
            of: bar, matching: find.text('محمد صديق المنشاوي (مرتل)')),
        findsOneWidget);
    expect(
        find.descendant(
            of: bar, matching: find.text('محمد صديق المنشاوي (مجود)')),
        findsNothing);
    expect(player.starts, 1);
    await t.pumpWidget(const SizedBox());
  });
  for (final path in ['bar', 'same-surah-row']) {
    testWidgets('whole-surah resume reclaims central ownership through $path',
        (t) async {
      final player = ResumeSurahPlayer();
      await mount(t, player);
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      player.positions.add(const Duration(seconds: 45));
      await t.pump();
      var stops = 0;
      final other = RecordingPlayer();
      engine.registerAudioFocus(
          player: other,
          onStopOther: () async {
            stops++;
          });
      if (path == 'bar') {
        final bar = find
            .ancestor(
                of: find.byTooltip('إيقاف التلاوة'),
                matching: find.byType(Column))
            .first;
        await t.tap(find.descendant(
            of: bar, matching: find.byTooltip('تشغيل أو إيقاف الصوت')));
      } else {
        await t.tap(find.text('سورة الفاتحة').first);
      }
      await t.pump();
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pumpAndSettle();
      expect(player.starts, 2);
      expect(player.loadedPosition, const Duration(seconds: 45));
      expect(stops, 1,
          reason: 'resume must stop the intervening central owner');
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() => other.dispose());
    });
  }

  for (final action in ['stop', 'dispose', 'other-owner']) {
    testWidgets('pending whole-surah resume cannot start after $action',
        (t) async {
      final player = ResumeSurahPlayer();
      await mount(t, player);
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      player.sourceGate = Completer<void>();
      final bar = find
          .ancestor(
              of: find.byTooltip('إيقاف التلاوة'),
              matching: find.byType(Column))
          .first;
      await t.tap(find.descendant(
          of: bar, matching: find.byTooltip('تشغيل أو إيقاف الصوت')));
      await t.pump();
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump();
      expect(player.sourceAssignments, 2);
      if (action == 'stop') {
        await t.tap(find.byTooltip('إيقاف التلاوة'));
        await t.pump();
      } else if (action == 'dispose') {
        await t.pumpWidget(const SizedBox());
      } else {
        engine.registerAudioFocus();
      }
      player.sourceGate!.complete();
      await t.pumpAndSettle();
      expect(player.starts, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('failed whole-surah pause stays unconfirmed at $scale',
        (t) async {
      final semantics = t.ensureSemantics();
      final player = StatefulSurahPlayer();
      await mount(t, player, scale: scale);
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      player.failPause = true;
      final bar = find
          .ancestor(
              of: find.byTooltip('إيقاف التلاوة'),
              matching: find.byType(Column))
          .first;
      await t.tap(find.descendant(
          of: bar, matching: find.byTooltip('تشغيل أو إيقاف الصوت')));
      await t.pumpAndSettle();
      expect(player.playing, isTrue);
      expect(find.textContaining('لم يتم تأكيد الإيقاف'), findsOneWidget);
      expect(find.byTooltip('إيقاف التلاوة'), findsOneWidget);
      expect(t.takeException(), isNull);
      final dir = Platform.environment['SURAH_PLAYER_PIXELS_DIR'];
      if (dir != null)
        await t.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/failed-pause-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      final failure =
          t.getSemantics(find.textContaining('لم يتم تأكيد الإيقاف'));
      expect(failure.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      final stopRect = t.getRect(find.byTooltip('إيقاف التلاوة'));
      expect(stopRect.bottom, lessThanOrEqualTo(800));
      expect(stopRect.top, greaterThanOrEqualTo(0));

      await t.tap(find.byTooltip('إيقاف التلاوة'));
      await t.pumpAndSettle();
      expect(find.byTooltip('إيقاف التلاوة'), findsNothing);
      expect(player.playing, isFalse);
      await t.pumpWidget(const SizedBox());
      semantics.dispose();
    });
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'failed pause Stop supports immediate semantic action at $scale',
        (t) async {
      final semantics = t.ensureSemantics();
      final player = StatefulSurahPlayer();
      await mount(t, player, scale: scale);
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      player.failPause = true;
      final bar = find
          .ancestor(
              of: find.byTooltip('إيقاف التلاوة'),
              matching: find.byType(Column))
          .first;
      await t.tap(find.descendant(
          of: bar, matching: find.byTooltip('تشغيل أو إيقاف الصوت')));
      await t.pumpAndSettle();
      expect(player.playing, isTrue);
      expect(find.textContaining('لم يتم تأكيد الإيقاف'), findsOneWidget);
      expect(find.byTooltip('إيقاف التلاوة'), findsOneWidget);
      expect(t.takeException(), isNull);
      final dir = Platform.environment['SURAH_PLAYER_PIXELS_DIR'];
      if (dir != null)
        await t.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/failed-pause-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      final failure =
          t.getSemantics(find.textContaining('لم يتم تأكيد الإيقاف'));
      expect(failure.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      final stopRect = t.getRect(find.byTooltip('إيقاف التلاوة'));
      expect(stopRect.bottom, lessThanOrEqualTo(800));
      expect(stopRect.top, greaterThanOrEqualTo(0));

      final stopNode = t.getSemantics(find.byTooltip('إيقاف التلاوة'));
      expect(stopNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isTrue);
      t.binding.performSemanticsAction(ui.SemanticsActionEvent(
          type: ui.SemanticsAction.tap,
          viewId: t.view.viewId,
          nodeId: stopNode.id));
      await t.pumpAndSettle();
      expect(find.byTooltip('إيقاف التلاوة'), findsNothing);
      expect(player.playing, isFalse);
      await t.pumpWidget(const SizedBox());
      semantics.dispose();
    });
  }
  testWidgets('late whole-surah pause result cannot clear newer loaded surah',
      (t) async {
    final player = StatefulSurahPlayer();
    await mount(t, player);
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    player.pauseGate = Completer<void>();
    final bar = find
        .ancestor(
            of: find.byTooltip('إيقاف التلاوة'), matching: find.byType(Column))
        .first;
    await t.tap(find.descendant(
        of: bar, matching: find.byTooltip('تشغيل أو إيقاف الصوت')));
    await t.pump();
    await t.tap(find.text('سورة البقرة').first);
    await t.pump();
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pumpAndSettle();
    expect(player.starts, 2);
    player.pauseGate!.complete();
    await t.pumpAndSettle();
    expect(player.playing, isTrue);
    expect(find.byTooltip('إيقاف التلاوة'), findsOneWidget);
    expect(find.textContaining('بدء تشغيل سورة البقرة'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  for (final repeat in [false, true]) {
    testWidgets(
        'whole-surah completion keeps loaded reciter after browsing, repeat=$repeat',
        (t) async {
      final player = CompletingSurahPlayer();
      await mount(t, player);
      await t.pumpAndSettle();
      await t.drag(find.byType(CustomScrollView), const Offset(0, 1000));
      await t.pumpAndSettle();
      final fields = find.byType(DropdownButtonFormField<String>);
      await t.ensureVisible(fields.first);
      await t.tap(fields.first);
      await t.pumpAndSettle();
      await t.tap(find.text('مجود').last);
      await t.pumpAndSettle();
      await t.tap(fields.last);
      await t.pumpAndSettle();
      await t.tap(find.text('محمد صديق المنشاوي').last);
      await t.pumpAndSettle();
      if (repeat) {
        await t.tap(find.byTooltip('تكرار السورة معطل'));
        await t.pump();
      }
      final initial = (player.sources.single as UriAudioSource).uri.toString();
      player.states.add(PlayerState(false, ProcessingState.completed));
      await t.pump();
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pumpAndSettle();
      expect(player.starts, 2);
      expect(
          (player.sources.last as UriAudioSource).uri.toString(),
          repeat
              ? initial
              : SettingsService.instance
                  .getSurahAudioUrl(2, 'minshawi_murattal'));
      expect(SettingsService.instance.currentReciter.nameAr, contains('مجود'));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'newer whole-surah request alone starts after overlapping source loads',
      (t) async {
    final player = RecordingPlayer()..sourceGate = Completer<void>();
    await mount(t, player);
    await t.tap(find.text('سورة البقرة').first);
    await t.pump();
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await t.pump();
    expect(player.sourceAssignments, 2);
    player.sourceGate!.complete();
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await t.pumpAndSettle();
    expect(player.starts, 1);
    expect(find.textContaining('بدء تشغيل سورة البقرة'), findsOneWidget);
    expect(find.textContaining('بدء تشغيل سورة الفاتحة'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('failed stop keeps the player visible and never claims success',
      (t) async {
    final player = RecordingPlayer();
    await mount(t, player);
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    player.failStop = true;
    await t.tap(find.byTooltip('إيقاف التلاوة'));
    await t.pumpAndSettle();
    expect(find.byTooltip('إيقاف التلاوة'), findsOneWidget);
    expect(find.textContaining('لم يتم تأكيد الإيقاف'), findsOneWidget);
    expect(player.starts, 1);
    expect(t.takeException(), isNull);
    player.failStop = false;
    await t.pumpWidget(const SizedBox());
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('loaded whole-surah player is readable at $scale', (t) async {
      final player = RecordingPlayer();
      await mount(t, player, scale: scale);
      await t.pumpAndSettle();
      expect(player.starts, 1);
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final dir = Platform.environment['SURAH_PLAYER_PIXELS_DIR'];
      if (dir != null)
        await t.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/loaded-surah-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      await t.pumpWidget(const SizedBox());
    });
  }
}
