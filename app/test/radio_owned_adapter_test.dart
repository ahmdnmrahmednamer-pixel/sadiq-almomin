import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/features/radio/curated_radio_screen.dart';

class RadioTarget extends AudioPlayer {
  bool active = false, disposed = false, failStop = false;
  int stops = 0, plays = 0;
  final events = StreamController<PlaybackEvent>.broadcast();
  @override
  bool get playing => active;
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;
  @override
  Future<void> play() async { plays++; active = true; }
  @override
  Future<void> stop() async {
    stops++;
    if (failStop) throw StateError('physical stop failed');
    active = false;
  }
  @override
  Future<void> dispose() async { disposed = true; active = false; await events.close(); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final focus = FastAudioService.instance;
  setUp(() {
    focus.resetForTesting();
    focus.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, isLiveStream = false}) async => AudioSource.uri(Uri.parse(url));
    focus.setAudioSourceOverride = (_, __) async {};
  });
  tearDown(focus.resetForTesting);

  test('radio disposal cannot stop or revoke a newer unrelated owner', () async {
    final target = RadioTarget(), newer = RadioTarget();
    final radio = FastAudioRadioPlayer(nativeTarget: target);
    await radio.play('https://example.test/radio');
    expect(target.playing, isTrue);
    final token = await focus.claimAudioFocus(player: newer);
    await newer.play();
    expect(target.playing, isFalse);
    final stopsBefore = newer.stops;
    radio.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(newer.playing, isTrue);
    expect(newer.stops, stopsBefore);
    expect(focus.activePlaybackToken, token);
    await newer.dispose();
  });

  test('disposed pending real central start never plays after source load', () async {
    final target = RadioTarget(), newer = RadioTarget();
    final entered = Completer<void>(), gate = Completer<void>();
    focus.setAudioSourceOverride = (_, __) async { entered.complete(); await gate.future; };
    final radio = FastAudioRadioPlayer(nativeTarget: target);
    final starting = radio.play('https://example.test/radio');
    await entered.future;
    radio.dispose();
    final token = await focus.claimAudioFocus(player: newer);
    await newer.play();
    final stopsBefore = newer.stops;
    gate.complete();
    await starting;
    expect(target.plays, 0);
    expect(target.playing, isFalse);
    expect(target.disposed, isTrue);
    expect(newer.playing, isTrue);
    expect(newer.stops, stopsBefore);
    expect(focus.activePlaybackToken, token);
    await newer.dispose();
  });

  test('physical stop failure stays retryable and blocks a new focus until fixed', () async {
    final target = RadioTarget(), newer = RadioTarget();
    final radio = FastAudioRadioPlayer(nativeTarget: target);
    await radio.play('https://example.test/radio');
    target.failStop = true;
    await expectLater(radio.stop(), throwsStateError);
    expect(target.playing, isTrue);
    await expectLater(focus.claimAudioFocus(player: newer), throwsStateError);
    expect(newer.plays, 0);
    target.failStop = false;
    await radio.stop();
    expect(target.playing, isFalse);
    await focus.claimAudioFocus(player: newer);
    await newer.play();
    expect(newer.playing, isTrue);
    radio.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(newer.playing, isTrue);
    await newer.dispose();
  });
}
