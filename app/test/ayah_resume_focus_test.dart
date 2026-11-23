import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/audio/ayah_audio_player.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'islamic_audio_play_failure_test.dart' show ObservedPlayPlayer;

class ResumePlayer extends ObservedPlayPlayer {
  int pauses = 0;
  bool failStop = false;
  @override
  Future<void> pause() async {
    pauses++;
    active = false;
  }

  @override
  Future<void> stop() async {
    if (failStop) throw StateError('still sounding');
    await super.stop();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final focus = FastAudioService.instance;
  late ResumePlayer player;
  late AyahAudioPlayer audio;
  setUp(() {
    focus.resetForTesting();
    player = ResumePlayer();
    audio = AyahAudioPlayer.forTesting(player);
    audio.currentPlayingKey.value = '1:1';
  });
  tearDown(() {
    audio.resetForTesting();
    focus.resetForTesting();
  });
  test('failed stop of sounding owner prevents resume', () async {
    final owner = ResumePlayer()
      ..active = true
      ..failStop = true;
    focus.registerAudioFocus(player: owner);
    await audio.togglePause();
    expect(player.plays, 0);
    expect(audio.isPlaying.value, false);
  });
  test('successful owner stop precedes one nonblocking resume', () async {
    final owner = ResumePlayer()..active = true;
    focus.registerAudioFocus(player: owner);
    final pending = Completer<void>();
    player.playingResult = pending;
    await audio.togglePause().timeout(const Duration(seconds: 1));
    expect(owner.active, false);
    expect(player.plays, 1);
    expect(pending.isCompleted, false);
    expect(audio.isPlaying.value, true);
    pending.complete();
  });
  for (final stale in ['stop', 'key', 'owner']) {
    test('resume cannot survive $stale while owner stop awaits', () async {
      final gate = Completer<void>();
      final owner = ResumePlayer()
        ..active = true
        ..stopGate = gate;
      focus.registerAudioFocus(player: owner);
      final pending = audio.togglePause();
      await Future<void>.delayed(Duration.zero);
      if (stale == 'stop') await audio.stop();
      if (stale == 'key') audio.currentPlayingKey.value = '2:2';
      if (stale == 'owner') focus.registerAudioFocus(player: ResumePlayer());
      gate.complete();
      await pending;
      expect(player.plays, 0);
    });
  }
  test('current rejected resume reports actual paused state and permits retry',
      () async {
    player.rejects = true;
    await audio.togglePause();
    await Future<void>.delayed(Duration.zero);
    expect(audio.isPlaying.value, false);
    expect(audio.currentPlayingKey.value, '1:1');
    player.rejects = false;
    await audio.togglePause();
    expect(player.plays, 2);
  });
  test('late resume rejection cannot clear newer verse state', () async {
    final pending = Completer<void>();
    player.playingResult = pending;
    await audio.togglePause();
    audio.currentPlayingKey.value = '2:2';
    audio.isPlaying.value = true;
    pending.completeError(StateError('late'));
    await Future<void>.delayed(Duration.zero);
    expect(audio.currentPlayingKey.value, '2:2');
    expect(audio.isPlaying.value, true);
  });
  test('playing branch still pauses without claiming another owner', () async {
    player.active = true;
    final owner = ResumePlayer();
    final token = focus.registerAudioFocus(player: owner);
    await audio.togglePause();
    expect(player.pauses, 1);
    expect(player.plays, 0);
    expect(focus.activePlaybackToken, token);
    expect(audio.isPlaying.value, false);
  });
}
