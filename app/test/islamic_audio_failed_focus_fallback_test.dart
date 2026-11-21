import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';

class UnstoppableOwner extends Fake implements AudioPlayer {
  @override
  bool get playing => true;
  @override
  Future<void> stop() async => throw StateError('still sounding');
}

class FallbackProbePlayer extends AudioPlayer {
  int plays = 0;
  bool takeoverOnVolume = true;
  bool failStop = false;
  bool ignoreStop = false;
  bool active = false;
  Completer<void>? stopGate;
  bool takeoverOnSource = false;
  bool failSource = false;
  int assets = 0;
  int nativeStops = 0;
  final blocker = UnstoppableOwner();
  @override
  bool get playing => active;
  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();
  @override
  Future<void> stop() async {
    nativeStops++;
    if (stopGate != null) await stopGate!.future;
    if (failStop) throw StateError('stop failed');
    if (!ignoreStop) active = false;
  }

  @override
  Future<void> setVolume(double value) async {
    if (takeoverOnVolume)
      FastAudioService.instance.registerAudioFocus(player: blocker);
  }

  @override
  Future<void> setSpeed(double value) async {}
  @override
  Future<Duration?> setAsset(String path,
      {String? package,
      bool preload = true,
      Duration? initialPosition,
      dynamic tag}) async {
    assets++;
    if (takeoverOnSource)
      FastAudioService.instance.registerAudioFocus(player: blocker);
    return const Duration(seconds: 1);
  }

  @override
  Future<Duration?> setAudioSource(AudioSource source,
      {bool preload = true,
      int? initialIndex,
      Duration? initialPosition}) async {
    if (failSource) throw StateError('network unavailable');
    return const Duration(seconds: 1);
  }

  @override
  Future<void> play() async {
    plays++;
    active = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('bundled fallback must not bypass a failed central stop', () async {
    final temp = Directory.systemTemp.createTempSync('focus-fallback-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => temp.path);
    final engine = FastAudioService.instance;
    engine.resetForTesting();
    final player = FallbackProbePlayer();
    final service = IslamicAudioService.forTesting(player);
    try {
      await service.playTrack(const IslamicAudioTrack(
          id: 'test-focus-fallback',
          title: 'test',
          subtitle: '',
          type: IslamicAudioType.adhan,
          remoteUrl: 'https://example.invalid/test.mp3',
          assetPath: 'assets/not-present-test.mp3',
          durationFormatted: '0:01'));
      expect(player.plays, 0,
          reason:
              'An unchanged service session is not evidence that central focus is safe');
    } finally {
      service.dispose();
      engine.resetForTesting();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'), null);
      temp.deleteSync(recursive: true);
    }
  });
  for (final mode in ['throw', 'unconfirmed']) {
    test('failed Stop retains the current track and retry control: $mode',
        () async {
      final engine = FastAudioService.instance;
      engine.resetForTesting();
      final player = FallbackProbePlayer()..takeoverOnVolume = false;
      final service = IslamicAudioService.forTesting(player);
      try {
        await service.playTrack(const IslamicAudioTrack(
            id: 'stop-test',
            title: 'test',
            subtitle: '',
            type: IslamicAudioType.adhan,
            assetPath: 'assets/test.mp3',
            durationFormatted: '0:01'));
        expect(player.plays, 1);
        player.failStop = mode == 'throw';
        player.ignoreStop = mode == 'unconfirmed';
        await service.stop();
        expect(service.currentTrack?.id, 'stop-test');
        expect(service.isPlaying, isTrue);
        expect(service.stopFailed, isTrue);
        player.failStop = false;
        player.ignoreStop = false;
        await service.stop();
        expect(service.currentTrack, isNull);
        expect(service.stopFailed, isFalse);
        expect(player.active, isFalse);
      } finally {
        service.dispose();
        engine.resetForTesting();
      }
    });
  }

  test('resume must not overlap another owner whose stop is refused', () async {
    final engine = FastAudioService.instance;
    engine.resetForTesting();
    final player = FallbackProbePlayer()..takeoverOnVolume = false;
    final service = IslamicAudioService.forTesting(player);
    try {
      await service.playTrack(const IslamicAudioTrack(
          id: 'resume-test',
          title: 'test',
          subtitle: '',
          type: IslamicAudioType.adhan,
          assetPath: 'assets/test.mp3',
          durationFormatted: '0:01'));
      player.active = false;
      engine.registerAudioFocus(player: player.blocker);
      await service.resume();
      expect(player.plays, 1, reason: 'Resume must claim focus too');
      expect(player.active, isFalse);
    } finally {
      service.dispose();
      engine.resetForTesting();
    }
  });
  test(
      'genuine source failure still permits bundled fallback after a safe focus retry',
      () async {
    final engine = FastAudioService.instance;
    engine.resetForTesting();
    final player = FallbackProbePlayer()
      ..takeoverOnVolume = false
      ..failSource = true;
    final service = IslamicAudioService.forTesting(player);
    engine.getFastAudioSourceOverride = (url,
            {required cacheKey,
            localDownloadedPath,
            isLiveStream = false}) async =>
        AudioSource.uri(Uri.parse(url));
    try {
      await service.playTrack(const IslamicAudioTrack(
          id: 'offline',
          title: 'test',
          subtitle: '',
          type: IslamicAudioType.adhan,
          remoteUrl: 'https://example.invalid/test.mp3',
          assetPath: 'assets/test.mp3',
          durationFormatted: '0:01'));
      expect(player.assets, 1);
      expect(player.plays, 1);
    } finally {
      service.dispose();
      engine.resetForTesting();
    }
  });

  test('ownership change during bundled load cancels before play', () async {
    final engine = FastAudioService.instance;
    engine.resetForTesting();
    final player = FallbackProbePlayer()
      ..takeoverOnVolume = false
      ..takeoverOnSource = true;
    final service = IslamicAudioService.forTesting(player);
    try {
      await service.playTrack(const IslamicAudioTrack(
          id: 'local',
          title: 'test',
          subtitle: '',
          type: IslamicAudioType.adhan,
          assetPath: 'assets/test.mp3',
          durationFormatted: '0:01'));
      expect(player.plays, 0);
      expect(service.isBuffering, isFalse);
      expect(service.currentTrack, isNull);
    } finally {
      service.dispose();
      engine.resetForTesting();
    }
  });

  test('new same-player start waits for an in-flight native Stop', () async {
    final engine = FastAudioService.instance;
    engine.resetForTesting();
    final player = FallbackProbePlayer()..takeoverOnVolume = false;
    final service = IslamicAudioService.forTesting(player);
    const first = IslamicAudioTrack(
        id: 'first',
        title: 'test',
        subtitle: '',
        type: IslamicAudioType.adhan,
        assetPath: 'assets/test.mp3',
        durationFormatted: '0:01');
    const next = IslamicAudioTrack(
        id: 'next',
        title: 'test',
        subtitle: '',
        type: IslamicAudioType.adhan,
        assetPath: 'assets/test.mp3',
        durationFormatted: '0:01');
    try {
      await service.playTrack(first);
      player.stopGate = Completer<void>();
      final stopping = service.stop();
      await Future<void>.delayed(Duration.zero);
      final starting = service.playTrack(next);
      await Future<void>.delayed(Duration.zero);
      expect(player.plays, 1);
      player.stopGate!.complete();
      await stopping;
      await starting;
      expect(player.plays, 2);
      expect(player.active, isTrue);
      expect(service.currentTrack?.id, 'next');
    } finally {
      service.dispose();
      engine.resetForTesting();
    }
  });
}
