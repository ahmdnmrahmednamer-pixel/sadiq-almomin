import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'islamic_audio_play_failure_test.dart' show ObservedPlayPlayer, first;

class CompletionPlayer extends ObservedPlayPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Future<void> seek(Duration? position, {int? index}) async {}
  @override
  Future<void> dispose() async {
    await states.close();
    await super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final outcome in ['reject', 'complete', 'lateAfterStop']) {
    test('single completion-loop play is observed without blocking $outcome',
        () async {
      final temp = Directory.systemTemp.createTempSync('loop-rejection-');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => temp.path);
      FastAudioService.instance.resetForTesting();
      final player = CompletionPlayer()..loadGate.complete();
      final service = IslamicAudioService.forTesting(player);
      try {
        await service.playTrack(first);
        service.toggleLoopMode();
        service.toggleLoopMode();
        expect(service.loopMode, PlaybackLoopMode.single);
        final pending = Completer<void>();
        player.playingResult = pending;
        player.states.add(PlayerState(false, ProcessingState.completed));
        expect(player.plays, 2);
        expect(pending.isCompleted, false);
        if (outcome == 'lateAfterStop') await service.stop();
        final current = service.currentTrack;
        final buffering = service.isBuffering;
        var notifications = 0;
        service.addListener(() => notifications++);
        if (outcome == 'complete') {
          pending.complete();
        } else {
          pending.completeError(StateError('loop replay rejected'));
        }
        await Future<void>.delayed(Duration.zero);
        expect(service.currentTrack, current);
        expect(service.isBuffering, buffering);
        expect(notifications, 0);
      } finally {
        service.dispose();
        FastAudioService.instance.resetForTesting();
        messenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
        temp.deleteSync(recursive: true);
      }
    });
  }
}
