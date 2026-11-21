import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/audio/ayah_audio_player.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/mushaf/widgets/scoped_playback_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StreamController<PlayerState> states;
  final played = <String>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    states = StreamController<PlayerState>.broadcast();
    final p = AyahAudioPlayer.instance..resetForTesting();
    played.clear();
    p.stopPlayerRunner = () async {};
    p.loadSurahsRunner = () async => [];
    p.prefetchAudioRunner = (_, __) {};
    p.playerStateStreamOverride = states.stream;
    p.playResilientRunner = (u, {player, primaryUrl, fallbackUrls = const [], cacheKey, localDownloadedPath, onStopCallback}) async {
      played.add(p.currentPlayingKey.value!);
      return true;
    };
  });
  tearDown(() async {
    await states.close();
    AyahAudioPlayer.instance.resetForTesting();
  });

  Widget host() => MaterialApp(
        home: Scaffold(
          body: const SizedBox(),
          bottomNavigationBar: ScopedPlaybackBar(keys: const ['112:1', '112:2', '112:3', '112:4'], scopeName: 'السورة'),
        ),
      );

  testWidgets('play button starts the scope, labelled by state; repeat count controls pass count', (t) async {
    final sem = t.ensureSemantics();
    await t.pumpWidget(host());
    expect(find.byTooltip('تشغيل السورة'), findsOneWidget);
    {final n=t.getSemantics(find.byKey(const ValueKey('scoped-play-pause')));expect('${n.label} ${n.tooltip}', contains('تشغيل السورة'));expect(n.hasFlag(SemanticsFlag.isButton), isTrue);}
    expect(find.byKey(const ValueKey('scoped-count')), findsNothing);
    await t.tap(find.byKey(const ValueKey('scoped-repeat')));
    await t.pump();
    expect(find.text('3'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('scoped-count-down')));
    await t.pump();
    expect(find.text('2'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('scoped-play-pause')));
    await t.pump();
    expect(played, ['112:1']);
    expect(find.byTooltip('إيقاف مؤقت'), findsOneWidget);
    for (var i = 0; i < 8; i++) {
      states.add(PlayerState(false, ProcessingState.completed));
      await t.pump();
      await t.pump();
    }
    expect(played, ['112:1', '112:2', '112:3', '112:4', '112:1', '112:2', '112:3', '112:4']);
    expect(AyahAudioPlayer.instance.scopedActive.value, isFalse);
    expect(find.byTooltip('تشغيل السورة'), findsOneWidget);
    sem.dispose();
  });

  testWidgets('controls are reachable and activate from the keyboard', (t) async {
    await t.pumpWidget(host());
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    final focused = FocusManager.instance.primaryFocus;
    expect(focused, isNotNull);
    // first focusable control is play/pause
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(played, ['112:1']);
    expect(AyahAudioPlayer.instance.scopedActive.value, isTrue);
  });

  testWidgets('stop ends the scope and returns the play label', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.byKey(const ValueKey('scoped-play-pause')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('scoped-stop')));
    await t.pump();
    expect(AyahAudioPlayer.instance.scopedActive.value, isFalse);
    expect(find.byTooltip('تشغيل السورة'), findsOneWidget);
  });

  testWidgets('scope menu switches to the juz and plays only its ayahs', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: const SizedBox(),
        bottomNavigationBar: ScopedPlaybackBar(
          keys: const ['112:1', '112:2'],
          scopeName: 'الصفحة',
          alternates: const {'الجزء 30': ['112:1', '112:2', '113:1']},
        ),
      ),
    ));
    expect(find.byTooltip('تشغيل الصفحة'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('scoped-scope')));
    await t.pumpAndSettle();
    await t.tap(find.text('الجزء 30'));
    await t.pumpAndSettle();
    expect(find.byTooltip('تشغيل الجزء 30'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('scoped-play-pause')));
    await t.pump();
    expect(AyahAudioPlayer.instance.activeScope, ['112:1', '112:2', '113:1']);
  });
}
