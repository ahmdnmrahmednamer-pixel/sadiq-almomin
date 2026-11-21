import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';

class RecordingPlayer extends AudioPlayer {
  int sourceAssignments = 0;
  int starts = 0;
  bool failStop = false;
  Completer<void>? blockedStop;
  Completer<void>? sourceGate;
  Completer<void>? speedGate;
  int speedChanges = 0;
  @override
  Future<void> setSpeed(double speed) async {
    speedChanges++;
    await speedGate?.future;
  }

  @override
  bool get playing => false;
  @override
  Future<void> stop() async {
    if (failStop) throw StateError('stop failed');
    await blockedStop?.future;
  }

  @override
  Future<Duration?> setAudioSource(AudioSource source,
      {bool preload = true,
      int? initialIndex,
      Duration? initialPosition}) async {
    sourceAssignments++;
    await sourceGate?.future;
    return const Duration(seconds: 1);
  }

  @override
  Future<void> play() async {
    starts++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engine = FastAudioService.instance;
  setUp(engine.resetForTesting);
  tearDown(engine.resetForTesting);
  for (final phase in ['stop', 'source', 'speed']) {
    test('zero-delay start cannot survive ownership change during $phase',
        () async {
      final old = RecordingPlayer();
      final newer = RecordingPlayer();
      final gate = Completer<void>();
      if (phase == 'stop')
        old.blockedStop = gate;
      else if (phase == 'source')
        old.sourceGate = gate;
      else
        old.speedGate = gate;
      final pending = engine.playWithZeroDelay(
          old, AudioSource.uri(Uri.parse('https://example.invalid/old.mp3')),
          speed: 1.5);
      await Future<void>.delayed(Duration.zero);
      engine.registerAudioFocus(player: newer);
      gate.complete();
      expect(await pending, isFalse);
      expect(old.starts, 0);
      if (phase == 'stop') expect(old.sourceAssignments, 0);
      await old.dispose();
      await newer.dispose();
    });
  }
  test('active zero-delay request returns true and starts exactly once',
      () async {
    final player = RecordingPlayer();
    expect(
        await engine.playWithZeroDelay(player,
            AudioSource.uri(Uri.parse('https://example.invalid/active.mp3')),
            speed: 1.5),
        isTrue);
    expect(player.starts, 1);
    expect(player.sourceAssignments, 1);
    expect(player.speedChanges, 1);
    await player.dispose();
  });
  test(
      'releasing the same player during source load returns false and never starts',
      () async {
    final player = RecordingPlayer()..sourceGate = Completer<void>();
    final pending = engine.playWithZeroDelay(player,
        AudioSource.uri(Uri.parse('https://example.invalid/stopped.mp3')));
    await Future<void>.delayed(Duration.zero);
    engine.releaseAudioFocusFor(player);
    player.sourceGate!.complete();
    expect(await pending, isFalse);
    expect(player.starts, 0);
    await player.dispose();
  });
}
