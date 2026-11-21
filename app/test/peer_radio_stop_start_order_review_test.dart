import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/features/radio/curated_radio_screen.dart';
import 'radio_owned_adapter_test.dart' show RadioTarget;
class StopRaceTarget extends RadioTarget {
  Completer<void>? gate;
  bool holdNext = false;
  @override
  Future<void> stop() async {
    if (holdNext) {holdNext = false;await gate!.future;}
    active = false;
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('same-target new radio start waits for a native Stop already in flight', () async {
    final focus = FastAudioService.instance; focus.resetForTesting();
    focus.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, isLiveStream = false}) async => AudioSource.uri(Uri.parse(url));
    focus.setAudioSourceOverride = (_, __) async {};
    final target = StopRaceTarget();
    final radio = FastAudioRadioPlayer(nativeTarget: target);
    try {
      await radio.play('https://example.test/first');
      target.gate = Completer<void>();target.holdNext = true;
      final stopping = radio.stop();
      await Future<void>.delayed(Duration.zero);
      final starting = radio.play('https://example.test/second');
      await Future<void>.delayed(Duration.zero);
      final playsBeforeStopCompleted = target.plays;
      target.gate!.complete();
      await stopping;await starting;
      expect(playsBeforeStopCompleted, 1, reason: 'An older native Stop must finish before a newer same-player start');
      expect(target.active, isTrue);
    } finally {radio.dispose();await Future<void>.delayed(Duration.zero);focus.resetForTesting();}
  });
}
