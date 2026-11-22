import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/adhkar/adhkar_audio_screen.dart';
import 'legacy_adhkar_queue_containment_test.dart' show ContainmentPlayer;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final heldId in ['dua_khatm_abdulbasit', 'adhan_sudais']) {
    test('rejected $heldId request cannot cancel an allowed actual source load',
        () async {
      final temp = Directory.systemTemp.createTempSync('held-load-session-');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path);
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.init(forceReload: true);
      final focus = FastAudioService.instance;
      focus.resetForTesting();
      final player = ContainmentPlayer()..loadGate = Completer<void>();
      final service = IslamicAudioService.forTesting(player);
      final allowed = AdhkarAudioScreen.tracks.first;
      final held =
          IslamicAudioService.allTracks.firstWhere((t) => t.id == heldId);
      Future<void>? pending;
      try {
        expect(IslamicAudioService.isHeldRecording(held), isTrue);
        expect(IslamicAudioService.isHeldRecording(allowed), isFalse);
        expect(allowed.assetPath, isNotNull);
        expect(allowed.remoteUrl, isNull);
        await service.init();
        pending = service.playTrack(allowed);
        for (var tick = 0;
            tick < 200 && !player.operations.contains('load');
            tick++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(player.operations, contains('load'));
        expect(player.operations.where((op) => op == 'play'), isEmpty);
        final before = List<String>.of(player.operations);
        final focusToken = focus.activePlaybackToken;
        await service.playQueue([held, allowed], startIndex: 0);
        await service.playTrack(held);
        await service.playTrack(held);
        await service.containLegacyAdhkarPlayback();
        expect(player.operations, before);
        expect(focus.activePlaybackToken, focusToken);
        expect(player.loadedPaths, [allowed.assetPath]);
        expect(service.currentTrack?.id, allowed.id);
        expect(service.heldLegacyTrack?.id, held.id);
        expect(service.queue.map((t) => t.id), [allowed.id]);
        expect(service.isBuffering, isTrue);
        player.loadGate!.complete();
        await pending;
        expect(player.operations.where((op) => op == 'play').length, 1);
        expect(player.loadedPaths, [allowed.assetPath]);
        expect(service.currentTrack?.id, allowed.id);
        // This fake's play() records the call but does not emit native events.
        player.states.add(PlayerState(true, ProcessingState.ready));
        expect(service.isPlaying, isTrue);
        expect(service.isBuffering, isFalse);
        expect(service.getLocalAudioPath(held.id), isNull);
      } finally {
        if (!player.loadGate!.isCompleted) player.loadGate!.complete();
        if (pending != null) await pending;
        await service.stop();
        focus.releaseAudioFocusFor(player);
        service.dispose();
        focus.resetForTesting();
        messenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
        temp.deleteSync(recursive: true);
      }
    });
  }
}
