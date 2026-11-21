import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/models/prophet_story.dart';
import 'package:almomin/features/stories/widgets/prophet_story_player_sheet.dart';
import 'zero_delay_owner_audit_test.dart' show RecordingPlayer;

class StoryPlayer extends RecordingPlayer {
  bool failPause = false;
  @override
  Future<void> pause() async {
    if (failPause) throw StateError('pause failed');
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {}
}

const story = ProphetAudioStory(
    id: 'lifetime-test',
    title: 'قصة اختبار',
    characterName: 'اختبار',
    subtitle: 'اختبار',
    category: StoryCategory.prophet,
    duration: '1:00',
    durationSeconds: 60,
    fileSizeBytes: 100,
    audioUrl: 'https://example.invalid/story.mp3',
    era: '',
    surahsMentioned: [],
    summary: '',
    keyLessons: []);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engine = FastAudioService.instance;
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
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    engine.resetForTesting();
  });
  tearDown(engine.resetForTesting);
  for (final phase in ['before-engine', 'in-engine']) {
    for (final action in ['dispose', 'reset', 'other-owner']) {
      testWidgets('story $phase source does not restart after $action',
          (t) async {
        final player = StoryPlayer();
        final pending = Completer<AudioSource>();
        if (phase == 'in-engine') player.sourceGate = Completer<void>();
        await t.pumpWidget(MaterialApp(
            home: Scaffold(
                body: ProphetStoryPlayerSheet(
                    story: story,
                    player: player,
                    loadSource: (_, __) => phase == 'before-engine'
                        ? pending.future
                        : Future.value(
                            AudioSource.uri(Uri.parse(story.audioUrl)))))));
        await t.pump();
        if (phase == 'in-engine') expect(player.sourceAssignments, 1);
        if (action == 'dispose') {
          await t.pumpWidget(const SizedBox());
        } else if (action == 'reset') {
          await t.tap(find.byTooltip('إيقاف وإعادة للبداية'));
          await t.pump();
        } else {
          engine.registerAudioFocus();
        }
        if (phase == 'before-engine')
          pending.complete(AudioSource.uri(Uri.parse(story.audioUrl)));
        else
          player.sourceGate!.complete();
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(player.starts, 0);
        if (phase == 'before-engine') expect(player.sourceAssignments, 0);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('closing the sheet revokes its source before exit ends',
      (t) async {
    final player = StoryPlayer();
    final pending = Completer<AudioSource>();
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => ProphetStoryPlayerSheet(
                            story: story,
                            player: player,
                            loadSource: (_, __) => pending.future)),
                    child: const Text('open'))))));
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byTooltip('إغلاق'));
    await t.pump();
    pending.complete(AudioSource.uri(Uri.parse(story.audioUrl)));
    await t.pumpAndSettle();
    expect(player.starts, 0);
    expect(player.sourceAssignments, 0);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('story success and resume both take current central ownership',
      (t) async {
    final player = StoryPlayer();
    var calls = 0;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProphetStoryPlayerSheet(
                story: story,
                player: player,
                loadSource: (_, __) async {
                  calls++;
                  return AudioSource.uri(Uri.parse(story.audioUrl));
                }))));
    await t.pumpAndSettle();
    expect(player.starts, 1);
    expect(find.text('استماع عبر الإنترنت'), findsOneWidget);
    expect(find.text('بث مباشر من الإنترنت'), findsNothing);
    await t.tap(find.byTooltip('تشغيل أو إيقاف الصوت'));
    await t.pumpAndSettle();
    final otherToken = engine.registerAudioFocus();
    await t.tap(find.byTooltip('تشغيل أو إيقاف الصوت'));
    await t.pumpAndSettle();
    expect(player.starts, 2);
    expect(calls, 2);
    expect(engine.activePlaybackToken, greaterThan(otherToken));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'story source failure is retryable and failed pause is unconfirmed',
      (t) async {
    final player = StoryPlayer();
    var calls = 0;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProphetStoryPlayerSheet(
                story: story,
                player: player,
                loadSource: (_, __) async {
                  if (++calls == 1) throw StateError('failed');
                  return AudioSource.uri(Uri.parse(story.audioUrl));
                }))));
    await t.pumpAndSettle();
    expect(find.textContaining('تعذر تحميل المقطع الصوتي'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('تشغيل أو إيقاف الصوت'));
    await t.pumpAndSettle();
    expect(player.starts, 1);
    player.failPause = true;
    await t.tap(find.byTooltip('تشغيل أو إيقاف الصوت'));
    await t.pumpAndSettle();
    expect(find.textContaining('لم يتم تأكيد الإيقاف'), findsOneWidget);
    expect(t.takeException(), isNull);
    player.failPause = false;
    await t.pumpWidget(const SizedBox());
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('story player labels and controls readable at $scale',
        (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      final player = StoryPlayer();
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
                  body: ProphetStoryPlayerSheet(
                      story: story,
                      player: player,
                      loadSource: (_, __) async =>
                          AudioSource.uri(Uri.parse(story.audioUrl)))))));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final dir = Platform.environment['STORY_LIFETIME_PIXELS_DIR'];
      if (dir != null)
        await t.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/story-player-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      await t.pumpWidget(const SizedBox());
    });
  }
}
