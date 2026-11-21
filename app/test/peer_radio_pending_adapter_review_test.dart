import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/features/radio/curated_radio_screen.dart';
void main() {
  test('disposing during a pending start cancels that start before it can survive', () async {
    final gate = Completer<bool>();
    var stops = 0;
    final player = FastAudioRadioPlayer(playFn: (url, callback) => gate.future, stopFn: () async {stops++;});
    final starting = player.play('https://example.test/live');
    player.dispose();
    gate.complete(true);
    await starting;
    expect(stops, greaterThan(0), reason: 'A pending successful start must not outlive its disposed screen');
  });
  test('stop failure keeps adapter ownership available for cleanup retry', () async {
    var stops = 0;
    final player = FastAudioRadioPlayer(playFn: (url, callback) async => true, stopFn: () async {stops++; throw StateError('still playing');});
    await player.play('https://example.test/live');
    await expectLater(player.stop(), throwsStateError);
    player.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(stops, greaterThan(1), reason: 'A failed Stop must not discard the sounding owner');
  });
}
