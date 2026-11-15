import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/audio/ayah_audio_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<PlayerState> playerStateController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    playerStateController = StreamController<PlayerState>.broadcast();
  });

  tearDown(() async {
    await playerStateController.close();
    AyahAudioPlayer.instance.resetForTesting();
  });

  group('AyahAudioPlayer Concurrency & Preview State Race Tests (A/B/C + edge cases)', () {
    testWidgets('Test A: playAyah followed by playReciterPreview preserves preview state', (tester) async {
      late BuildContext buildContext;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (ctx) {
            buildContext = ctx;
            return const SizedBox();
          }),
        ),
      ));

      final player = AyahAudioPlayer.instance;
      player.resetForTesting();
      player.stopPlayerRunner = () async {};
      player.playerStateStreamOverride = playerStateController.stream;

      final ayahCompleter = Completer<bool>();
      final previewCompleter = Completer<bool>();
      Future<void>? playAyahFuture;
      Future<bool>? previewFuture;

      try {
        int callIndex = 0;
        player.playResilientRunner = (
          positionalUrl, {
          player,
          primaryUrl,
          fallbackUrls = const [],
          cacheKey,
          localDownloadedPath,
          onStopCallback,
        }) {
          callIndex++;
          if (callIndex == 1) {
            return ayahCompleter.future;
          } else {
            return previewCompleter.future;
          }
        };

        // 1. User starts playing an Ayah
        playAyahFuture = player.playAyah(buildContext, 1, 1);
        await tester.pump();
        expect(player.currentPlayingKey.value, equals('1:1'));
        expect(player.isPlaying.value, isTrue);

        // 2. While Ayah audio is loading, user triggers Reciter Preview
        final reciter = SettingsService.availableReciters.first;
        previewFuture = player.playReciterPreview(reciter);
        await tester.pump();
        expect(player.currentPlayingKey.value, equals('preview_${reciter.id}'));

        // 3. The superseded Ayah load finishes with false (stopped/cancelled)
        ayahCompleter.complete(false);
        await playAyahFuture;
        await tester.pump();

        // With session guards in place, playAyah detects it was superseded and does NOT wipe out preview
        expect(
          player.currentPlayingKey.value,
          equals('preview_${reciter.id}'),
          reason: 'playAyah must not wipe out preview state when superseded',
        );
        expect(player.isPlaying.value, isTrue);
      } finally {
        if (!ayahCompleter.isCompleted) ayahCompleter.complete(false);
        if (!previewCompleter.isCompleted) previewCompleter.complete(false);
        if (playAyahFuture != null) {
          try {
            await playAyahFuture;
          } catch (_) {}
        }
        if (previewFuture != null) {
          try {
            await previewFuture;
          } catch (_) {}
        }
        await tester.pump();
      }
    });

    testWidgets('Test B: playReciterPreview followed by playAyah preserves ayah state', (tester) async {
      late BuildContext buildContext;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (ctx) {
            buildContext = ctx;
            return const SizedBox();
          }),
        ),
      ));

      final player = AyahAudioPlayer.instance;
      player.resetForTesting();
      player.stopPlayerRunner = () async {};
      player.playerStateStreamOverride = playerStateController.stream;

      final previewCompleter = Completer<bool>();
      final ayahCompleter = Completer<bool>();
      Future<bool>? previewFuture;
      Future<void>? playAyahFuture;

      try {
        int callIndex = 0;
        player.playResilientRunner = (
          positionalUrl, {
          player,
          primaryUrl,
          fallbackUrls = const [],
          cacheKey,
          localDownloadedPath,
          onStopCallback,
        }) {
          callIndex++;
          if (callIndex == 1) {
            return previewCompleter.future;
          } else {
            return ayahCompleter.future;
          }
        };

        // 1. User starts Reciter Preview
        final reciter = SettingsService.availableReciters.first;
        previewFuture = player.playReciterPreview(reciter);
        await tester.pump();
        expect(player.currentPlayingKey.value, equals('preview_${reciter.id}'));

        // 2. User quickly taps an Ayah to play
        playAyahFuture = player.playAyah(buildContext, 2, 255);
        await tester.pump();
        expect(player.currentPlayingKey.value, equals('2:255'));

        // 3. Stale preview completes with false (stopped by playAyah)
        previewCompleter.complete(false);
        final previewResult = await previewFuture;
        await tester.pump();

        // Assert while new ayah is pending: stale preview returns false and must NOT wipe out active playAyah state
        expect(previewResult, isFalse);
        expect(
          player.currentPlayingKey.value,
          equals('2:255'),
          reason: 'Stale preview completion must not wipe out active playAyah state while new ayah is pending',
        );
        expect(player.isPlaying.value, isTrue);

        // Complete false for cleanup, avoiding success I/O (no QuranRepository/prefetch)
        ayahCompleter.complete(false);
        try {
          await playAyahFuture;
        } catch (_) {}
        await tester.pump();
      } finally {
        if (!previewCompleter.isCompleted) previewCompleter.complete(false);
        if (!ayahCompleter.isCompleted) ayahCompleter.complete(false);
        if (previewFuture != null) {
          try {
            await previewFuture;
          } catch (_) {}
        }
        if (playAyahFuture != null) {
          try {
            await playAyahFuture;
          } catch (_) {}
        }
        await tester.pump();
      }
    });

    testWidgets('Test C: preview A followed by preview B preserves preview B state', (tester) async {
      final player = AyahAudioPlayer.instance;
      player.resetForTesting();
      player.stopPlayerRunner = () async {};
      player.playerStateStreamOverride = playerStateController.stream;

      final previewACompleter = Completer<bool>();
      final previewBCompleter = Completer<bool>();
      Future<bool>? futureA;
      Future<bool>? futureB;

      try {
        int callIndex = 0;
        player.playResilientRunner = (
          positionalUrl, {
          player,
          primaryUrl,
          fallbackUrls = const [],
          cacheKey,
          localDownloadedPath,
          onStopCallback,
        }) {
          callIndex++;
          if (callIndex == 1) {
            return previewACompleter.future;
          } else {
            return previewBCompleter.future;
          }
        };

        final reciterA = SettingsService.availableReciters[0];
        final reciterB = SettingsService.availableReciters[1];

        // 1. User clicks Preview for Sheikh A
        futureA = player.playReciterPreview(reciterA);
        await tester.pump();
        expect(player.currentPlayingKey.value, equals('preview_${reciterA.id}'));

        // 2. User quickly switches to Preview for Sheikh B
        futureB = player.playReciterPreview(reciterB);
        await tester.pump();
        expect(player.currentPlayingKey.value, equals('preview_${reciterB.id}'));

        // 3. Preview A completes with false (cancelled by Preview B)
        previewACompleter.complete(false);
        final resultA = await futureA;
        await tester.pump();

        expect(resultA, isFalse);
        expect(
          player.currentPlayingKey.value,
          equals('preview_${reciterB.id}'),
          reason: 'Stale preview A must not wipe out preview B state',
        );
        expect(player.isPlaying.value, isTrue);
      } finally {
        if (!previewACompleter.isCompleted) previewACompleter.complete(false);
        if (!previewBCompleter.isCompleted) previewBCompleter.complete(false);
        if (futureA != null) {
          try {
            await futureA;
          } catch (_) {}
        }
        if (futureB != null) {
          try {
            await futureB;
          } catch (_) {}
        }
        await tester.pump();
      }
    });

    testWidgets('Test D (throw): preview A throwing after being superseded does not corrupt preview B state', (tester) async {
      final player = AyahAudioPlayer.instance;
      player.resetForTesting();
      player.stopPlayerRunner = () async {};
      player.playerStateStreamOverride = playerStateController.stream;

      final previewACompleter = Completer<bool>();
      final previewBCompleter = Completer<bool>();
      Future<bool>? futureA;
      Future<bool>? futureB;

      try {
        int callIndex = 0;
        player.playResilientRunner = (
          positionalUrl, {
          player,
          primaryUrl,
          fallbackUrls = const [],
          cacheKey,
          localDownloadedPath,
          onStopCallback,
        }) {
          callIndex++;
          if (callIndex == 1) {
            return previewACompleter.future;
          } else {
            return previewBCompleter.future;
          }
        };

        final reciterA = SettingsService.availableReciters[0];
        final reciterB = SettingsService.availableReciters[1];

        futureA = player.playReciterPreview(reciterA);
        await tester.pump();
        expect(player.currentPlayingKey.value, equals('preview_${reciterA.id}'));

        futureB = player.playReciterPreview(reciterB);
        await tester.pump();
        expect(player.currentPlayingKey.value, equals('preview_${reciterB.id}'));

        // Preview A throws an unhandled error (e.g. SocketException / player error)
        previewACompleter.completeError(Exception('Network timeout in preview A'));
        final resultA = await futureA;
        await tester.pump();

        expect(resultA, isFalse);
        // Preview A's catch block must not reset preview B's key
        expect(player.currentPlayingKey.value, equals('preview_${reciterB.id}'));
        expect(player.isPlaying.value, isTrue);
      } finally {
        if (!previewACompleter.isCompleted) previewACompleter.complete(false);
        if (!previewBCompleter.isCompleted) previewBCompleter.complete(false);
        if (futureA != null) {
          try {
            await futureA;
          } catch (_) {}
        }
        if (futureB != null) {
          try {
            await futureB;
          } catch (_) {}
        }
        await tester.pump();
      }
    });

    testWidgets('Test E: active preview returns false or throws -> resets state to null', (tester) async {
      final player = AyahAudioPlayer.instance;
      player.resetForTesting();
      player.stopPlayerRunner = () async {};
      player.playerStateStreamOverride = playerStateController.stream;

      final reciter = SettingsService.availableReciters.first;

      // Case 1: active preview returns false
      player.playResilientRunner = (url, {player, primaryUrl, fallbackUrls = const [], cacheKey, localDownloadedPath, onStopCallback}) async {
        return false;
      };

      final result1 = await player.playReciterPreview(reciter);
      await tester.pump();
      expect(result1, isFalse);
      expect(player.currentPlayingKey.value, isNull);
      expect(player.isPlaying.value, isFalse);

      // Case 2: active preview throws
      player.playResilientRunner = (url, {player, primaryUrl, fallbackUrls = const [], cacheKey, localDownloadedPath, onStopCallback}) async {
        throw Exception('Playback stream error');
      };

      final result2 = await player.playReciterPreview(reciter);
      await tester.pump();
      expect(result2, isFalse);
      expect(player.currentPlayingKey.value, isNull);
      expect(player.isPlaying.value, isFalse);
    });

    testWidgets('Test F (delayed-stop): preview A whose stopPlayer awaits is aborted when preview B starts', (tester) async {
      final player = AyahAudioPlayer.instance;
      player.resetForTesting();
      player.playerStateStreamOverride = playerStateController.stream;

      final stopCompleter = Completer<void>();
      int stopCallCount = 0;
      player.stopPlayerRunner = () async {
        stopCallCount++;
        if (stopCallCount == 1) {
          await stopCompleter.future;
        }
      };

      player.playResilientRunner = (url, {player, primaryUrl, fallbackUrls = const [], cacheKey, localDownloadedPath, onStopCallback}) async {
        return true;
      };

      final reciterA = SettingsService.availableReciters[0];
      final reciterB = SettingsService.availableReciters[1];

      // 1. Preview A starts, its _stopPlayer is delayed
      final futureA = player.playReciterPreview(reciterA);
      await tester.pump();
      // Has not set currentPlayingKey yet because it is awaiting _stopPlayer
      expect(player.currentPlayingKey.value, isNull);

      // 2. While Preview A is stopped, user starts Preview B
      final futureB = player.playReciterPreview(reciterB);
      await tester.pump();
      expect(player.currentPlayingKey.value, equals('preview_${reciterB.id}'));

      // 3. Preview A's stop finally finishes
      stopCompleter.complete();
      final resultA = await futureA;
      await tester.pump();

      // Preview A detects (sessionId != _activePlaySessionId) right after _stopPlayer and exits early
      expect(resultA, isFalse);
      expect(player.currentPlayingKey.value, equals('preview_${reciterB.id}'));

      final resultB = await futureB;
      expect(resultB, isTrue);
    });

    testWidgets('Test G (preserve toggle): calling preview while playing the same reciter preview toggles it off', (tester) async {
      final player = AyahAudioPlayer.instance;
      player.resetForTesting();
      player.stopPlayerRunner = () async {};
      player.playerStateStreamOverride = playerStateController.stream;

      final reciter = SettingsService.availableReciters.first;

      // Simulate player is currently playing preview for this reciter
      player.isPlayerPlayingOverride = () => true;
      player.currentPlayingKey.value = 'preview_${reciter.id}';
      player.isPlaying.value = true;
      // Set the private playingReciterId by playing once or starting
      player.playResilientRunner = (url, {player, primaryUrl, fallbackUrls = const [], cacheKey, localDownloadedPath, onStopCallback}) async {
        return true;
      };
      await player.playReciterPreview(reciter);
      expect(player.currentPlayingKey.value, equals('preview_${reciter.id}'));

      // Now toggle off by calling playReciterPreview again with the exact same reciter while playing
      final toggleResult = await player.playReciterPreview(reciter);
      expect(toggleResult, isFalse);
      expect(player.currentPlayingKey.value, isNull);
      expect(player.isPlaying.value, isFalse);
    });
  });
}
