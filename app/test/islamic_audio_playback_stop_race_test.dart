import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';

class DelayedLoadPlayer extends AudioPlayer {
  final entered = Completer<void>();
  final loadGate = Completer<void>();
  int plays = 0;
  Completer<void>? stopGate;
  bool active = false;
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
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> stop() async {
    if (stopGate != null) await stopGate!.future;
    active = false;
  }

  @override
  Future<void> play() async {
    plays++;
    active = true;
  }

  @override
  Future<Duration?> setAsset(String path,
      {String? package,
      bool preload = true,
      Duration? initialPosition,
      dynamic tag}) async {
    if (!entered.isCompleted) entered.complete();
    await loadGate.future;
    return const Duration(seconds: 10);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('audio-stop-race-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => temp.path);
    FastAudioService.instance.resetForTesting();
  });
  tearDown(() {
    FastAudioService.instance.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    temp.deleteSync(recursive: true);
  });
  test('Stop during a bundled load prevents late playback', () async {
    final player = DelayedLoadPlayer();
    final service = IslamicAudioService.forTesting(player);
    final pending = service.playTrack(const IslamicAudioTrack(
        id: 'test-local',
        title: 'test',
        subtitle: '',
        type: IslamicAudioType.adhan,
        assetPath: 'assets/not-present-test.mp3',
        durationFormatted: '0:10'));
    await player.entered.future;
    await service.stop();
    player.loadGate.complete();
    await pending;
    expect(player.plays, 0);
    expect(player.active, false);
    expect(service.currentTrack, isNull);
    service.dispose();
  });
  test(
      'Stop during remote source load prevents late streaming and bundled fallback',
      () async {
    final player = DelayedLoadPlayer();
    final service = IslamicAudioService.forTesting(player);
    FastAudioService.instance.getFastAudioSourceOverride = (url,
            {required cacheKey,
            localDownloadedPath,
            isLiveStream = false}) async =>
        AudioSource.uri(Uri.parse(url));
    FastAudioService.instance.setAudioSourceOverride = (target, source) async {
      player.entered.complete();
      await player.loadGate.future;
    };
    final pending = service.playTrack(const IslamicAudioTrack(
        id: 'test-remote',
        title: 'test',
        subtitle: '',
        type: IslamicAudioType.adhan,
        remoteUrl: 'https://example.invalid/test.mp3',
        assetPath: 'assets/not-present-test.mp3',
        durationFormatted: '0:10'));
    await player.entered.future;
    await service.stop();
    player.loadGate.complete();
    await pending;
    expect(player.plays, 0);
    expect(player.active, false);
    expect(service.currentTrack, isNull);
    service.dispose();
  });
  test('releasing a stopped player cannot invalidate a newer audio owner',
      () async {
    final first = DelayedLoadPlayer();
    final second = DelayedLoadPlayer();
    final focus = FastAudioService.instance;
    focus.registerAudioFocus(player: first);
    final newer = focus.registerAudioFocus(player: second);
    focus.releaseAudioFocusFor(first);
    expect(focus.activePlaybackToken, newer);
    focus.releaseAudioFocusFor(second);
    expect(focus.activePlaybackToken, greaterThan(newer));
  });
  test('an older delayed start cannot overwrite newer selected track',
      () async {
    final player = DelayedLoadPlayer();
    final service = IslamicAudioService.forTesting(player);
    const first = IslamicAudioTrack(
        id: 'first',
        title: 'first',
        subtitle: '',
        type: IslamicAudioType.adhan,
        assetPath: 'assets/test-first.mp3',
        durationFormatted: '0:10');
    const second = IslamicAudioTrack(
        id: 'second',
        title: 'second',
        subtitle: '',
        type: IslamicAudioType.adhan,
        assetPath: 'assets/test-second.mp3',
        durationFormatted: '0:10');
    final old = service.playTrack(first);
    await player.entered.future;
    final newer = service.playTrack(second);
    await Future<void>.delayed(Duration.zero);
    player.loadGate.complete();
    await Future.wait([old, newer]);
    expect(player.plays, 1);
    expect(service.currentTrack?.id, 'second');
    await service.stop();
    expect(service.isBuffering, false);
    service.dispose();
  });
  test('an older Stop completion cannot clear newer playback selection',
      () async {
    final player = DelayedLoadPlayer();
    final service = IslamicAudioService.forTesting(player);
    const first = IslamicAudioTrack(
        id: 'first',
        title: 'first',
        subtitle: '',
        type: IslamicAudioType.adhan,
        assetPath: 'assets/test-first.mp3',
        durationFormatted: '0:10');
    const second = IslamicAudioTrack(
        id: 'second',
        title: 'second',
        subtitle: '',
        type: IslamicAudioType.adhan,
        assetPath: 'assets/test-second.mp3',
        durationFormatted: '0:10');
    final initial = service.playTrack(first);
    await player.entered.future;
    player.loadGate.complete();
    await initial;
    player.stopGate = Completer<void>();
    final stopping = service.stop();
    final newer = service.playTrack(second);
    await Future<void>.delayed(Duration.zero);
    player.stopGate!.complete();
    await Future.wait([stopping, newer]);
    expect(service.currentTrack?.id, 'second');
    player.stopGate = null;
    await service.stop();
    service.dispose();
  });
}
