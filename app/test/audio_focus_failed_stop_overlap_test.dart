import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';

class FocusProbePlayer extends Fake implements AudioPlayer {
  bool active = false;
  bool refuseStop = false;
  bool ignoreStop = false;
  int plays = 0;
  int stops = 0;
  Completer<void>? stopGate;
  Completer<void>? firstStopGate;
  @override
  bool get playing => active;
  @override
  Future<void> stop() async {
    stops++;
    if (stops == 1 && firstStopGate != null) await firstStopGate!.future;
    if (stopGate != null) await stopGate!.future;
    if (refuseStop) throw StateError('prior audio still active');
    if (!ignoreStop) active = false;
  }

  @override
  Future<Duration?> setAudioSource(AudioSource source,
          {bool preload = true,
          int? initialIndex,
          Duration? initialPosition}) async =>
      const Duration(seconds: 1);
  @override
  Future<void> play() async {
    active = true;
    plays++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'new adhan-like playback must not overlap a prior player whose stop failed',
      () async {
    final engine = FastAudioService.instance;
    engine.resetForTesting();
    final old = FocusProbePlayer()
      ..active = true
      ..refuseStop = true;
    final next = FocusProbePlayer();
    engine.registerAudioFocus(player: old, onStopOther: old.stop);
    try {
      try {
        await engine.playWithZeroDelay(next,
            AudioSource.uri(Uri.parse('https://example.invalid/test.mp3')));
      } catch (_) {}
      expect(old.playing, isTrue);
      expect(next.plays, 0,
          reason:
              'Failed prior stop must block a second voice, not silently continue');
    } finally {
      engine.resetForTesting();
    }
  });
  test(
      'unconfirmed prior stop which returns normally must also block the next voice',
      () async {
    final engine = FastAudioService.instance;
    engine.resetForTesting();
    final old = FocusProbePlayer()
      ..active = true
      ..ignoreStop = true;
    final next = FocusProbePlayer();
    engine.registerAudioFocus(player: old);
    try {
      try {
        await engine.playWithZeroDelay(next,
            AudioSource.uri(Uri.parse('https://example.invalid/test.mp3')));
      } catch (_) {}
      expect(old.playing, isTrue);
      expect(next.plays, 0);
    } finally {
      engine.resetForTesting();
    }
  });
  test('custom audio owner stop failure must not grant focus to another voice',
      () async {
    final engine = FastAudioService.instance;
    engine.resetForTesting();
    final next = FocusProbePlayer();
    engine.registerAudioFocus(onStopOther: () async {
      throw StateError('custom audio still active');
    });
    try {
      try {
        await engine.playWithZeroDelay(next,
            AudioSource.uri(Uri.parse('https://example.invalid/test.mp3')));
      } catch (_) {}
      expect(next.plays, 0);
    } finally {
      engine.resetForTesting();
    }
  });

  setUp(() => FastAudioService.instance.resetForTesting());
  tearDown(() => FastAudioService.instance.resetForTesting());

  test(
      'failed prior owner is retained across a third claim then can be retried',
      () async {
    final engine = FastAudioService.instance;
    final old = FocusProbePlayer()
      ..active = true
      ..refuseStop = true;
    final rejected = FocusProbePlayer();
    final next = FocusProbePlayer();
    engine.registerAudioFocus(player: old);
    await expectLater(
        engine.claimAudioFocus(player: rejected), throwsStateError);
    await expectLater(engine.claimAudioFocus(player: next), throwsStateError);
    expect(rejected.plays + next.plays, 0);
    old.refuseStop = false;
    expect(
        await engine.playWithZeroDelay(next,
            AudioSource.uri(Uri.parse('https://example.invalid/test.mp3'))),
        isTrue);
    expect(old.active, isFalse);
    expect(next.plays, 1);
  });

  test('global stop reports failure and can retry the same sounding owner',
      () async {
    final engine = FastAudioService.instance;
    final old = FocusProbePlayer()
      ..active = true
      ..refuseStop = true;
    engine.registerAudioFocus(player: old);
    await expectLater(engine.stop(), throwsStateError);
    old.refuseStop = false;
    await engine.stop();
    expect(old.active, isFalse);
    expect(old.stops, 2);
  });

  test('released native stop failure cannot disappear from the focus ledger',
      () async {
    final engine = FastAudioService.instance;
    final old = FocusProbePlayer()
      ..active = true
      ..refuseStop = true;
    final next = FocusProbePlayer();
    engine.registerAudioFocus(player: old);
    engine.releaseAudioFocusFor(old);
    await expectLater(engine.claimAudioFocus(player: next), throwsStateError);
    expect(old.playing, isTrue);
    expect(next.plays, 0);
  });

  test(
      'resilient playback returns false without trying fallback on focus failure',
      () async {
    final engine = FastAudioService.instance;
    final old = FocusProbePlayer()
      ..active = true
      ..ignoreStop = true;
    final next = FocusProbePlayer();
    engine.registerAudioFocus(player: old);
    var loads = 0;
    engine.getFastAudioSourceOverride = (url,
        {required cacheKey, localDownloadedPath, isLiveStream = false}) async {
      loads++;
      return AudioSource.uri(Uri.parse(url));
    };
    expect(
        await engine.playResilient('https://example.invalid/one.mp3',
            player: next, fallbackUrls: ['https://example.invalid/two.mp3']),
        isFalse);
    expect(loads, 0);
    expect(next.plays, 0);
  });

  test(
      'a newer claim waits for the prior physical stop and only newest can start',
      () async {
    final engine = FastAudioService.instance;
    final gate = Completer<void>();
    final old = FocusProbePlayer()
      ..active = true
      ..stopGate = gate;
    final middle = FocusProbePlayer();
    final newest = FocusProbePlayer();
    engine.registerAudioFocus(player: old);
    final first = engine.playWithZeroDelay(middle,
        AudioSource.uri(Uri.parse('https://example.invalid/first.mp3')));
    await Future<void>.delayed(Duration.zero);
    final second = engine.playWithZeroDelay(newest,
        AudioSource.uri(Uri.parse('https://example.invalid/second.mp3')));
    await Future<void>.delayed(Duration.zero);
    expect(newest.plays, 0);
    gate.complete();
    expect(await first, isFalse);
    expect(await second, isTrue);
    expect(old.active, isFalse);
    expect(middle.plays, 0);
    expect(newest.plays, 1);
  });

  test(
      'failed in-flight stop cannot overwrite a newer owner and no second voice starts',
      () async {
    final engine = FastAudioService.instance;
    final gate = Completer<void>();
    final old = FocusProbePlayer()
      ..active = true
      ..refuseStop = true
      ..stopGate = gate;
    final middle = FocusProbePlayer();
    final newest = FocusProbePlayer();
    engine.registerAudioFocus(player: old);
    final first = engine.claimAudioFocus(player: middle);
    final firstError = expectLater(first, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    final second = engine.claimAudioFocus(player: newest);
    final secondError = expectLater(second, throwsStateError);
    final latestToken = engine.activePlaybackToken;
    gate.complete();
    await firstError;
    await secondError;
    expect(engine.activePlaybackToken, latestToken);
    expect(middle.plays + newest.plays, 0);
    old.refuseStop = false;
    await engine.stop();
    expect(old.active, isFalse);
  });

  test('same player must confirm stop before loading again', () async {
    final engine = FastAudioService.instance;
    final player = FocusProbePlayer()
      ..active = true
      ..ignoreStop = true;
    engine.registerAudioFocus(player: player);
    await expectLater(
        engine.playWithZeroDelay(player,
            AudioSource.uri(Uri.parse('https://example.invalid/replay.mp3'))),
        throwsStateError);
    expect(player.plays, 0);
  });

  test('custom stop callback retry is required before another claim succeeds',
      () async {
    final engine = FastAudioService.instance;
    var fail = true;
    var calls = 0;
    Future<void> stopCustom() async {
      calls++;
      if (fail) throw StateError('not stopped');
    }

    final next = FocusProbePlayer();
    engine.registerAudioFocus(onStopOther: stopCustom);
    await expectLater(engine.claimAudioFocus(player: next), throwsStateError);
    fail = false;
    await engine.claimAudioFocus(player: next);
    expect(calls, greaterThanOrEqualTo(2));
  });
  test('idle target reset cannot finish late after a newer same-player start',
      () async {
    final engine = FastAudioService.instance;
    final gate = Completer<void>();
    final player = FocusProbePlayer()..firstStopGate = gate;
    final first = engine.playWithZeroDelay(player,
        AudioSource.uri(Uri.parse('https://example.invalid/first.mp3')));
    await Future<void>.delayed(Duration.zero);
    final second = engine.playWithZeroDelay(player,
        AudioSource.uri(Uri.parse('https://example.invalid/second.mp3')));
    await Future<void>.delayed(Duration.zero);
    expect(player.plays, 0,
        reason: 'New playback must wait for the older native reset');
    gate.complete();
    expect(await first, isFalse);
    expect(await second, isTrue);
    expect(player.active, isTrue);
    expect(player.plays, 1);
  });
}
