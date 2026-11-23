import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'islamic_audio_play_failure_test.dart' show ObservedPlayPlayer;

class CentralPlayPlayer extends ObservedPlayPlayer {
  int sourceLoads = 0;
  @override
  Future<Duration?> setAudioSource(AudioSource source,
      {bool preload = true,
      int? initialIndex,
      Duration? initialPosition}) async {
    sourceLoads++;
    return const Duration(seconds: 1);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engine = FastAudioService.instance;
  late Directory temp;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('central-play-error-');
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => temp.path);
    engine.resetForTesting();
  });
  tearDown(() {
    engine.resetForTesting();
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), null);
    temp.deleteSync(recursive: true);
  });
  for (final path in ['asset', 'direct', 'lockCache', 'zeroDelay']) {
    for (final outcome in ['reject', 'complete', 'lateNewOwner']) {
      test('$path observes $outcome without changing admission or focus',
          () async {
        final player = CentralPlayPlayer()..loadGate.complete();
        final pending = Completer<void>();
        player.playingResult = pending;
        var remoteLoads = 0;
        if (path == 'lockCache') await engine.init();
        engine.getFastAudioSourceOverride = (url,
            {required cacheKey,
            localDownloadedPath,
            isLiveStream = false}) async {
          remoteLoads++;
          if (path == 'lockCache') throw StateError('direct load failed');
          return AudioSource.uri(Uri.parse(url));
        };
        engine.setAudioSourceOverride = (target, source) async {};
        var stops = 0;
        final result = path == 'zeroDelay'
            ? await engine.playWithZeroDelay(player,
                AudioSource.uri(Uri.parse('https://example.invalid/test.mp3')),
                onStopCallback: () async {
                stops++;
              })
            : await engine.playResilient(
                path == 'asset'
                    ? 'assets/test.mp3'
                    : 'https://example.invalid/test.mp3',
                player: player,
                isLiveStream: path != 'lockCache', onStopCallback: () async {
                stops++;
              });
        expect(result, true);
        expect(player.plays, 1);
        expect(pending.isCompleted, false);
        if (path == 'lockCache') {
          expect(remoteLoads, 1);
          expect(player.sourceLoads, 1);
        }
        if (outcome == 'lateNewOwner') {
          engine.registerAudioFocus(player: CentralPlayPlayer());
        }
        final token = engine.activePlaybackToken;
        if (outcome == 'complete') {
          pending.complete();
        } else {
          pending.completeError(StateError('native rejected'));
        }
        await Future<void>.delayed(Duration.zero);
        expect(engine.activePlaybackToken, token);
        expect(stops, 0);
        expect(player.plays, 1);
      });
    }
  }
}
