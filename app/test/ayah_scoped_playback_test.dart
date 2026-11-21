import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/audio/ayah_audio_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StreamController<PlayerState> states;
  final played = <String>[];
  late BuildContext ctx;

  Future<void> boot(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) { ctx = c; return const SizedBox(); }))));
    final p = AyahAudioPlayer.instance;
    p.resetForTesting();
    played.clear();
    p.stopPlayerRunner = () async {};
    p.loadSurahsRunner = () async => [];
    p.prefetchAudioRunner = (_, __) {};
    p.playerStateStreamOverride = states.stream;
    p.playResilientRunner = (u, {player, primaryUrl, fallbackUrls = const [], cacheKey, localDownloadedPath, onStopCallback}) async {
      played.add(p.currentPlayingKey.value!);
      return true;
    };
  }

  Future<void> finishCurrent(WidgetTester t) async {
    states.add(PlayerState(false, ProcessingState.completed));
    await t.pump();
    await t.pump();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    states = StreamController<PlayerState>.broadcast();
  });
  tearDown(() async {
    await states.close();
    AyahAudioPlayer.instance.resetForTesting();
  });

  testWidgets('scope plays only its ayahs in order and stops after the last (no repeat)', (t) async {
    await boot(t);
    final p = AyahAudioPlayer.instance;
    await t.runAsync(() async {});
    unawaited(p.playScope(ctx, ['112:1', '112:2', '112:3']));
    await t.pump();
    expect(p.scopedActive.value, isTrue);
    expect(played, ['112:1']);
    await finishCurrent(t);
    expect(played, ['112:1', '112:2']);
    await finishCurrent(t);
    expect(played, ['112:1', '112:2', '112:3']);
    await finishCurrent(t);
    expect(played, hasLength(3));
    expect(p.scopedActive.value, isFalse);
    expect(p.currentPlayingKey.value, isNull);
  });

  testWidgets('repeat count plays the whole scope that many times', (t) async {
    await boot(t);
    final p = AyahAudioPlayer.instance;
    unawaited(p.playScope(ctx, ['112:1', '112:2'], passes: 2));
    await t.pump();
    for (var i = 0; i < 4; i++) {
      await finishCurrent(t);
    }
    expect(played, ['112:1', '112:2', '112:1', '112:2']);
    expect(p.scopedActive.value, isFalse);
  });

  testWidgets('single ayah tap leaves the scope and plays only that ayah', (t) async {
    await boot(t);
    final p = AyahAudioPlayer.instance;
    unawaited(p.playScope(ctx, ['112:1', '112:2', '112:3']));
    await t.pump();
    unawaited(p.playAyah(ctx, 1, 5));
    await t.pump();
    expect(p.scopedActive.value, isFalse);
    expect(played.last, '1:5');
    await finishCurrent(t);
    expect(played.where((k) => k == '112:2'), isEmpty);
  });

  testWidgets('stop clears the scope', (t) async {
    await boot(t);
    final p = AyahAudioPlayer.instance;
    unawaited(p.playScope(ctx, ['112:1', '112:2']));
    await t.pump();
    await p.stop();
    expect(p.scopedActive.value, isFalse);
    expect(p.activeScope, isNull);
  });
}
