import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'islamic_audio_playback_stop_race_test.dart' show DelayedLoadPlayer;

class ObservedPlayPlayer extends DelayedLoadPlayer {
  Completer<void>? playingResult;
  bool rejects = false;
  @override
  Future<void> play() {
    plays++;
    if (rejects) return Future<void>.error(StateError('native play rejected'));
    return playingResult?.future ?? Future<void>.value();
  }

  @override
  Future<Duration?> setFilePath(String path,
          {Duration? initialPosition,
          bool preload = true,
          dynamic tag}) async =>
      const Duration(seconds: 10);
}

const first = IslamicAudioTrack(
    id: 'test-first',
    title: 'test',
    subtitle: '',
    type: IslamicAudioType.adhan,
    assetPath: 'assets/test.mp3',
    durationFormatted: '0:10');
const second = IslamicAudioTrack(
    id: 'test-second',
    title: 'test',
    subtitle: '',
    type: IslamicAudioType.adhan,
    assetPath: 'assets/test.mp3',
    durationFormatted: '0:10');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late ObservedPlayPlayer player;
  late IslamicAudioService service;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('observed-play-');
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => temp.path);
    FastAudioService.instance.resetForTesting();
    player = ObservedPlayPlayer()..loadGate.complete();
    service = IslamicAudioService.forTesting(player);
  });
  tearDown(() {
    service.dispose();
    FastAudioService.instance.resetForTesting();
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), null);
    temp.deleteSync(recursive: true);
  });
  test('bundled play rejection is observed and clears pending selection',
      () async {
    player.rejects = true;
    await service.playTrack(first);
    await Future<void>.delayed(Duration.zero);
    expect(service.isBuffering, false);
    expect(service.isPlaying, false);
    expect(service.currentTrack, isNull);
    player.rejects = false;
    await service.playTrack(first);
    expect(player.plays, 2);
    expect(service.currentTrack, first);
  });
  test('local file play rejection follows same observer', () async {
    final file = File('${temp.path}/local.mp3')
      ..writeAsBytesSync(List.filled(2048, 0));
    player.rejects = true;
    await service.playTrack(IslamicAudioTrack(
        id: 'local-file',
        title: 'test',
        subtitle: '',
        type: IslamicAudioType.adhan,
        assetPath: file.path,
        durationFormatted: '0:10'));
    await Future<void>.delayed(Duration.zero);
    expect(service.isBuffering, false);
    expect(service.currentTrack, isNull);
  });
  test('remote load failure bundled fallback rejection is observed', () async {
    var remoteAttempts = 0;
    FastAudioService.instance.getFastAudioSourceOverride = (url,
        {required cacheKey, localDownloadedPath, isLiveStream = false}) async {
      remoteAttempts++;
      throw StateError('injected remote source failure');
    };
    player.rejects = true;
    await service.playTrack(const IslamicAudioTrack(
        id: 'remote-fallback',
        title: 'test',
        subtitle: '',
        type: IslamicAudioType.adhan,
        remoteUrl: 'https://example.invalid/audio.mp3',
        assetPath: 'assets/test.mp3',
        durationFormatted: '0:10'));
    await Future<void>.delayed(Duration.zero);
    expect(remoteAttempts, 1);
    expect(player.plays, 1);
    expect(service.isBuffering, false);
    expect(service.currentTrack, isNull);
  });
  test('resume rejection is observed without changing existing state policy',
      () async {
    await service.playTrack(first);
    final track = service.currentTrack;
    final buffering = service.isBuffering;
    player.rejects = true;
    await service.resume();
    await Future<void>.delayed(Duration.zero);
    expect(service.currentTrack, track);
    expect(service.isBuffering, buffering);
  });
  test('resume returns before playback completes and consumes late stop error',
      () async {
    await service.playTrack(first);
    final pending = Completer<void>();
    player.playingResult = pending;
    await service.resume().timeout(const Duration(seconds: 2));
    expect(pending.isCompleted, false);
    await service.stop();
    pending.completeError(StateError('late resumed native rejection'));
    await Future<void>.delayed(Duration.zero);
    expect(service.currentTrack, isNull);
  });
  test('downloaded local playback rejection is observed', () async {
    service.dispose();
    service = IslamicAudioService.forTesting(player, catalog: [first]);
    await service.init();
    final file = File(
        '${temp.path}/${IslamicAudioService.downloadFileNameForTrack(first.id)}');
    file.writeAsBytesSync(List.filled(2048, 0));
    await service.scanDownloadsForTesting(temp);
    expect(service.getLocalAudioPath(first.id), file.path);
    player.rejects = true;
    await service.playTrack(first);
    await Future<void>.delayed(Duration.zero);
    expect(service.isBuffering, false);
    expect(service.currentTrack, isNull);
  });
  test('current rejection retains actual sounding prior track', () async {
    await service.playTrack(first);
    player.active = true;
    final pending = Completer<void>();
    player.playingResult = pending;
    await service.playTrack(second);
    player.active = true;
    pending.completeError(StateError('rejected while native prior continues'));
    await Future<void>.delayed(Duration.zero);
    expect(service.isPlaying, true);
    expect(service.currentTrack, first);
    expect(service.isBuffering, false);
  });
  test('play request returns without waiting for playback completion',
      () async {
    player.playingResult = Completer<void>();
    await service.playTrack(first).timeout(const Duration(seconds: 2));
    expect(player.playingResult!.isCompleted, false);
    expect(player.plays, 1);
    player.playingResult!.complete();
  });
  for (final stale in ['stop', 'newerSelection', 'newerOwner', 'dispose']) {
    test('late rejected play cannot mutate state after $stale', () async {
      final pending = Completer<void>();
      player.playingResult = pending;
      await service.playTrack(first);
      var notifications = 0;
      service.addListener(() => notifications++);
      if (stale == 'stop') await service.stop();
      if (stale == 'newerSelection') {
        player.playingResult = null;
        await service.playTrack(second);
      }
      if (stale == 'newerOwner') {
        FastAudioService.instance
            .registerAudioFocus(player: ObservedPlayPlayer());
      }
      if (stale == 'dispose') {
        service.dispose();
        service = IslamicAudioService.forTesting(
            ObservedPlayPlayer()..loadGate.complete());
      }
      final track = service.currentTrack;
      final buffering = service.isBuffering;
      final count = notifications;
      pending.completeError(StateError('late native rejection'));
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack, track);
      expect(service.isBuffering, buffering);
      expect(notifications, count);
    });
  }
}
