import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/adhkar/adhkar_audio_screen.dart';
import 'legacy_adhkar_queue_containment_test.dart' show ContainmentPlayer;

class LifecyclePlayer extends ContainmentPlayer {
  bool sounding = false;
  bool disposed = false;
  @override
  bool get playing => sounding;
  @override
  Future<void> play() {
    sounding = true;
    return super.play();
  }

  @override
  Future<void> stop() async {
    await super.stop();
    sounding = false;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    // Keep sounding unchanged to model native disposal not yet confirmed.
    await super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final focus = FastAudioService.instance;
  final allowed = AdhkarAudioScreen.tracks.first;
  final owners = <IslamicAudioService, LifecyclePlayer>{};
  late Directory temp;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  IslamicAudioService owner(LifecyclePlayer player) {
    final service = IslamicAudioService.forTesting(player);
    owners[service] = player;
    return service;
  }

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('islamic-dispose-focus-');
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => temp.path);
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    focus.resetForTesting();
  });
  tearDown(() async {
    for (final entry in owners.entries) {
      if (!entry.value.disposed) {
        entry.value.failStop = false;
        await entry.key.stop();
        entry.key.dispose();
      }
    }
    owners.clear();
    focus.resetForTesting();
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), null);
    temp.deleteSync(recursive: true);
  });

  test('disposed active owner cannot poison the next focus claim', () async {
    final oldPlayer = LifecyclePlayer();
    final old = owner(oldPlayer);
    await old.playTrack(allowed);
    expect(oldPlayer.sounding, isTrue);
    old.dispose();
    final nextPlayer = LifecyclePlayer();
    final next = owner(nextPlayer);
    await next.playTrack(allowed);
    expect(nextPlayer.operations.where((op) => op == 'play').length, 1);
    expect(oldPlayer.sounding, isFalse);
    expect(next.currentTrack?.id, allowed.id);
  });

  test('disposing a stale owner does not revoke replacement focus', () async {
    final old = owner(LifecyclePlayer());
    await old.playTrack(allowed);
    final nextPlayer = LifecyclePlayer();
    final next = owner(nextPlayer);
    await next.playTrack(allowed);
    final token = focus.activePlaybackToken;
    old.dispose();
    expect(focus.activePlaybackToken, token);
    expect(nextPlayer.sounding, isTrue);
    expect(next.currentTrack?.id, allowed.id);
  });

  test('dispose invalidates an actual gated source load before it can play',
      () async {
    final player = LifecyclePlayer()..loadGate = Completer<void>();
    final service = owner(player);
    final loading = service.playTrack(allowed);
    for (var tick = 0;
        tick < 200 && !player.operations.contains('load');
        tick++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(player.operations, contains('load'));
    service.dispose();
    player.loadGate!.complete();
    await loading;
    expect(player.operations.where((op) => op == 'play'), isEmpty);
  });

  test(
      'disposed sounding owner retains failed physical stop and explicit retry',
      () async {
    final oldPlayer = LifecyclePlayer();
    final old = owner(oldPlayer);
    await old.playTrack(allowed);
    old.dispose();
    oldPlayer.failStop = true;
    final nextPlayer = LifecyclePlayer();
    final next = owner(nextPlayer);
    await next.playTrack(allowed);
    expect(oldPlayer.sounding, isTrue);
    expect(nextPlayer.operations.where((op) => op == 'play'), isEmpty);
    oldPlayer.failStop = false;
    await next.playTrack(allowed);
    expect(oldPlayer.sounding, isFalse);
    expect(nextPlayer.operations.where((op) => op == 'play').length, 1);
  });
}
