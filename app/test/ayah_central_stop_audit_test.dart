import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/audio/ayah_audio_player.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test('stopping ayah player never revokes another central player owner',
      () async {
    final other = AudioPlayer();
    final token = engine.registerAudioFocus(player: other);
    await audio.stop();
    expect(engine.activePlaybackToken, token);
    await other.dispose();
  });

  testWidgets('a delayed old stop does not clear a newer preview state',
      (t) async {
    final pendingStop = Completer<void>();
    var calls = 0;
    audio.stopPlayerRunner =
        () => ++calls == 1 ? pendingStop.future : Future.value();
    audio.playResilientRunner = (url,
            {player,
            primaryUrl,
            fallbackUrls = const [],
            cacheKey,
            localDownloadedPath,
            onStopCallback}) async =>
        true;
    final oldStop = audio.stop();
    final reciter = SettingsService.availableReciters.first;
    expect(await audio.playReciterPreview(reciter), isTrue);
    pendingStop.complete();
    await oldStop;
    expect(audio.currentPlayingKey.value, 'preview_${reciter.id}');
    expect(audio.isPlaying.value, isTrue);
  });

  for (final preview in [true, false]) {
    testWidgets(
        'stop revokes central pending ${preview ? "preview" : "verse"} source',
        (t) async {
      late BuildContext context;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }))));
      final pending = Completer<AudioSource>();
      final entered = Completer<void>();
      var assigned = 0;
      engine.getFastAudioSourceOverride = (url,
          {required cacheKey, localDownloadedPath, isLiveStream = false}) {
        if (!entered.isCompleted) entered.complete();
        return pending.future;
      };
      engine.setAudioSourceOverride = (_, __) async {
        assigned++;
        throw StateError('test must never load after stop');
      };
      final future = preview
          ? audio.playReciterPreview(SettingsService.availableReciters.first)
          : audio.playAyah(context, 1, 1);
      await t
          .runAsync(() => entered.future.timeout(const Duration(seconds: 2)));
      await audio.stop();
      pending.complete(
          AudioSource.uri(Uri.parse('https://example.invalid/recording.mp3')));
      await t.runAsync(() async {
        await future;
      });
      expect(assigned, 0,
          reason:
              'Stopping the owning player must revoke the central engine start, not just clear UI state');
      expect(audio.isPlaying.value, isFalse);
      expect(audio.currentPlayingKey.value, isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
