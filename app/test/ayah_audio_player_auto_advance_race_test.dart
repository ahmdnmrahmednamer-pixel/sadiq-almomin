import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/models/surah.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/audio/ayah_audio_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testSurah1 = Surah(
    id: 1,
    nameAr: 'الفاتحة',
    nameSimple: 'Al-Fatihah',
    revelationPlace: 'makkah',
    revelationOrder: 5,
    ayahCount: 7,
    hasBasmala: false,
    pageStart: 1,
    pageEnd: 1,
  );

  const testSurah2 = Surah(
    id: 2,
    nameAr: 'البقرة',
    nameSimple: 'Al-Baqarah',
    revelationPlace: 'madinah',
    revelationOrder: 87,
    ayahCount: 286,
    hasBasmala: true,
    pageStart: 2,
    pageEnd: 49,
  );

  final mockSurahs = [testSurah1, testSurah2];

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

  group('AyahAudioPlayer Auto-Advance Session Race & Error Tests', () {
    testWidgets('RED Test 1: metadata delay (loadSurahs) -> newer manual ayah is preserved and stale auto-advance call count is zero', (tester) async {
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
      player.prefetchAudioRunner = (url, key) {};

      final recordedCacheKeys = <String>[];
      final metadataCompleter = Completer<List<Surah>>();
      final ayahCompleter = Completer<bool>();
      Future<void>? playAyahFuture;

      try {
        player.loadSurahsRunner = () => metadataCompleter.future;
        player.playResilientRunner = (url, {player, primaryUrl, fallbackUrls = const [], cacheKey, localDownloadedPath, onStopCallback}) {
          if (cacheKey != null) recordedCacheKeys.add(cacheKey);
          return ayahCompleter.future;
        };

        // 1. Initial ayah is playing
        player.currentPlayingKey.value = '1:1';
        player.isPlaying.value = true;

        // 2. Playback completes, triggering auto-advance which pauses at loadSurahsRunner
        playerStateController.add(PlayerState(false, ProcessingState.completed));
        await tester.pump();

        // 3. User manually selects another Ayah before metadata completes
        playAyahFuture = player.playAyah(buildContext, 2, 255);
        await tester.pump();
        expect(player.currentPlayingKey.value, equals('2:255'));

        // 4. Stale metadata completes
        metadataCompleter.complete(mockSurahs);
        await tester.pump();

        // Auto-advance must detect post-await that it no longer owns the session
        // and must NOT overwrite currentPlayingKey with '1:2'
        expect(
          player.currentPlayingKey.value,
          equals('2:255'),
          reason: 'Auto-advance must not clobber manual ayah after loadSurahs delay',
        );
        expect(player.isPlaying.value, isTrue);

        // Stale auto-advance 1:2 call count must be ZERO after metadata resumes
        final staleAutoAdvanceCalls = recordedCacheKeys.where((k) => k.contains('_1_2')).toList();
        expect(
          staleAutoAdvanceCalls.length,
          equals(0),
          reason: 'Stale auto-advance 1:2 service call count must be ZERO after metadata resumes',
        );
        // Legitimate manual ayah 2:255 call is allowed
        expect(recordedCacheKeys.where((k) => k.contains('_2_255')).length, equals(1));
      } finally {
        if (!metadataCompleter.isCompleted) metadataCompleter.complete(mockSurahs);
        if (!ayahCompleter.isCompleted) ayahCompleter.complete(false);
        if (playAyahFuture != null) {
          try {
            await playAyahFuture;
          } catch (_) {}
        }
        await tester.pump();
      }
    });

    testWidgets('RED Test 2: metadata delay (loadSurahs) -> newer preview is preserved and stale auto-advance call count is zero', (tester) async {
      final player = AyahAudioPlayer.instance;
      player.resetForTesting();
      player.stopPlayerRunner = () async {};
      player.playerStateStreamOverride = playerStateController.stream;
      player.prefetchAudioRunner = (url, key) {};

      final recordedCacheKeys = <String>[];
      final metadataCompleter = Completer<List<Surah>>();
      final previewCompleter = Completer<bool>();
      Future<bool>? previewFuture;

      try {
        player.loadSurahsRunner = () => metadataCompleter.future;
        player.playResilientRunner = (url, {player, primaryUrl, fallbackUrls = const [], cacheKey, localDownloadedPath, onStopCallback}) {
          if (cacheKey != null) recordedCacheKeys.add(cacheKey);
          return previewCompleter.future;
        };

        // 1. Initial ayah is playing
        player.currentPlayingKey.value = '1:1';
        player.isPlaying.value = true;

        // 2. Playback completes, triggering auto-advance which pauses at loadSurahsRunner
        playerStateController.add(PlayerState(false, ProcessingState.completed));
        await tester.pump();

        // 3. User starts reciter preview before metadata completes
        final reciter = SettingsService.availableReciters.first;
        previewFuture = player.playReciterPreview(reciter);
        await tester.pump();
        expect(player.currentPlayingKey.value, equals('preview_${reciter.id}'));

        // 4. Stale metadata completes
        metadataCompleter.complete(mockSurahs);
        await tester.pump();

        // Auto-advance must detect post-await that it was superseded and must NOT overwrite with '1:2'
        expect(
          player.currentPlayingKey.value,
          equals('preview_${reciter.id}'),
          reason: 'Auto-advance must not clobber preview after loadSurahs delay',
        );
        expect(player.isPlaying.value, isTrue);

        // Stale auto-advance 1:2 call count must be ZERO after metadata resumes
        final staleAutoAdvanceCalls = recordedCacheKeys.where((k) => k.contains('_1_2')).toList();
        expect(
          staleAutoAdvanceCalls.length,
          equals(0),
          reason: 'Stale auto-advance 1:2 service call count must be ZERO after metadata resumes',
        );
        // Legitimate preview call is allowed
        expect(recordedCacheKeys.where((k) => k.contains('preview_reciter_')).length, equals(1));
      } finally {
        if (!metadataCompleter.isCompleted) metadataCompleter.complete(mockSurahs);
        if (!previewCompleter.isCompleted) previewCompleter.complete(false);
        if (previewFuture != null) {
          try {
            await previewFuture;
          } catch (_) {}
        }
        await tester.pump();
      }
    });

    testWidgets('RED Test 3: metadata delay (loadSurahs) -> manual stop preserves stopped state and stale auto-advance call count is zero', (tester) async {
      final player = AyahAudioPlayer.instance;
      player.resetForTesting();
      player.stopPlayerRunner = () async {};
      player.playerStateStreamOverride = playerStateController.stream;
      player.prefetchAudioRunner = (url, key) {};

      final recordedCacheKeys = <String>[];
      final metadataCompleter = Completer<List<Surah>>();
      final advanceAudioCompleter = Completer<bool>();

      try {
        player.loadSurahsRunner = () => metadataCompleter.future;
        player.playResilientRunner = (url, {player, primaryUrl, fallbackUrls = const [], cacheKey, localDownloadedPath, onStopCallback}) {
          if (cacheKey != null) recordedCacheKeys.add(cacheKey);
          return advanceAudioCompleter.future;
        };

        // 1. Initial ayah is playing
        player.currentPlayingKey.value = '1:1';
        player.isPlaying.value = true;

        // 2. Playback completes, auto-advance starts and awaits metadata
        playerStateController.add(PlayerState(false, ProcessingState.completed));
        await tester.pump();

        // 3. User calls stop() during metadata delay
        await player.stop();
        await tester.pump();
        expect(player.currentPlayingKey.value, isNull);
        expect(player.isPlaying.value, isFalse);

        // 4. Stale metadata completes
        metadataCompleter.complete(mockSurahs);
        await tester.pump();

        // Auto-advance must NOT take ownership or start playback of '1:2'
        expect(
          player.currentPlayingKey.value,
          isNull,
          reason: 'Auto-advance must not start playback after manual stop was called during loadSurahs delay',
        );
        expect(player.isPlaying.value, isFalse);

        // Stale auto-advance 1:2 call count must be ZERO after metadata resumes
        final staleAutoAdvanceCalls = recordedCacheKeys.where((k) => k.contains('_1_2')).toList();
        expect(
          staleAutoAdvanceCalls.length,
          equals(0),
          reason: 'Stale auto-advance 1:2 service call count must be ZERO after metadata resumes',
        );
      } finally {
        if (!metadataCompleter.isCompleted) metadataCompleter.complete(mockSurahs);
        if (!advanceAudioCompleter.isCompleted) advanceAudioCompleter.complete(false);
        await tester.pump();
      }
    });

    testWidgets('RED Test 4: stale service throw after auto-advance claims NEW token preserves newer ayah', (tester) async {
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
      player.prefetchAudioRunner = (url, key) {};
      player.loadSurahsRunner = () async => mockSurahs;

      final advanceAudioCompleter = Completer<bool>();
      final manualAyahCompleter = Completer<bool>();
      Future<void>? playAyahFuture;

      try {
        int callIndex = 0;
        player.playResilientRunner = (url, {player, primaryUrl, fallbackUrls = const [], cacheKey, localDownloadedPath, onStopCallback}) {
          callIndex++;
          if (callIndex == 1) {
            return advanceAudioCompleter.future;
          } else {
            return manualAyahCompleter.future;
          }
        };

        // 1. Initial ayah 1:1 finishes
        player.currentPlayingKey.value = '1:1';
        player.isPlaying.value = true;

        // 2. Completed event triggers auto-advance which completes loadSurahs and claims its NEW token for 1:2
        playerStateController.add(PlayerState(false, ProcessingState.completed));
        await tester.pump();
        expect(player.currentPlayingKey.value, equals('1:2'));

        // 3. While auto-advance 1:2 is in-flight at playResilientRunner, user starts manual ayah 2:255
        playAyahFuture = player.playAyah(buildContext, 2, 255);
        await tester.pump();
        expect(player.currentPlayingKey.value, equals('2:255'));

        // 4. Stale auto-advance 1:2 throws an error
        advanceAudioCompleter.completeError(Exception('Simulated auto-advance network failure'));
        await tester.pump();

        // Stale auto-advance catch block must NOT wipe the active session
        expect(
          player.currentPlayingKey.value,
          equals('2:255'),
          reason: 'Stale auto-advance throw must not wipe active manual ayah state in catch block',
        );
        expect(player.isPlaying.value, isTrue);
      } finally {
        if (!advanceAudioCompleter.isCompleted) advanceAudioCompleter.complete(false);
        if (!manualAyahCompleter.isCompleted) manualAyahCompleter.complete(false);
        if (playAyahFuture != null) {
          try {
            await playAyahFuture;
          } catch (_) {}
        }
        await tester.pump();
      }
    });

    testWidgets('Control Test 5: service true after manual stop preserves stopped state (existing guard control)', (tester) async {
      final player = AyahAudioPlayer.instance;
      player.resetForTesting();
      player.stopPlayerRunner = () async {};
      player.playerStateStreamOverride = playerStateController.stream;
      player.prefetchAudioRunner = (url, key) {};
      player.loadSurahsRunner = () async => mockSurahs;

      final advanceAudioCompleter = Completer<bool>();

      try {
        player.playResilientRunner = (url, {player, primaryUrl, fallbackUrls = const [], cacheKey, localDownloadedPath, onStopCallback}) {
          return advanceAudioCompleter.future;
        };

        // 1. Initial ayah finishes
        player.currentPlayingKey.value = '1:1';
        player.isPlaying.value = true;

        // 2. Auto-advance claims token and begins awaiting playResilient
        playerStateController.add(PlayerState(false, ProcessingState.completed));
        await tester.pump();
        expect(player.currentPlayingKey.value, equals('1:2'));

        // 3. User calls stop()
        await player.stop();
        await tester.pump();
        expect(player.currentPlayingKey.value, isNull);
        expect(player.isPlaying.value, isFalse);

        // 4. Stale auto-advance service completes true
        advanceAudioCompleter.complete(true);
        await tester.pump();

        // Caller state must remain stopped
        expect(player.currentPlayingKey.value, isNull);
        expect(player.isPlaying.value, isFalse);
      } finally {
        if (!advanceAudioCompleter.isCompleted) advanceAudioCompleter.complete(false);
        await tester.pump();
      }
    });

    testWidgets('Control Test 6: active success advances to next ayah cleanly without interference', (tester) async {
      final player = AyahAudioPlayer.instance;
      player.resetForTesting();
      player.stopPlayerRunner = () async {};
      player.playerStateStreamOverride = playerStateController.stream;
      player.prefetchAudioRunner = (url, key) {};
      player.loadSurahsRunner = () async => mockSurahs;

      player.playResilientRunner = (url, {player, primaryUrl, fallbackUrls = const [], cacheKey, localDownloadedPath, onStopCallback}) async {
        return true;
      };

      player.currentPlayingKey.value = '1:1';
      player.isPlaying.value = true;

      playerStateController.add(PlayerState(false, ProcessingState.completed));
      await tester.pump();

      expect(player.currentPlayingKey.value, equals('1:2'));
      expect(player.isPlaying.value, isTrue);
    });

    testWidgets('Control Test 7: active failure resets state to null without interference', (tester) async {
      final player = AyahAudioPlayer.instance;
      player.resetForTesting();
      player.stopPlayerRunner = () async {};
      player.playerStateStreamOverride = playerStateController.stream;
      player.prefetchAudioRunner = (url, key) {};
      player.loadSurahsRunner = () async => mockSurahs;

      player.playResilientRunner = (url, {player, primaryUrl, fallbackUrls = const [], cacheKey, localDownloadedPath, onStopCallback}) async {
        return false;
      };

      player.currentPlayingKey.value = '1:1';
      player.isPlaying.value = true;

      playerStateController.add(PlayerState(false, ProcessingState.completed));
      await tester.pump();

      expect(player.currentPlayingKey.value, isNull);
      expect(player.isPlaying.value, isFalse);
    });

    testWidgets('Control Test 8: end of Surah does not advance beyond ayahCount', (tester) async {
      final player = AyahAudioPlayer.instance;
      player.resetForTesting();
      player.stopPlayerRunner = () async {};
      player.playerStateStreamOverride = playerStateController.stream;
      player.prefetchAudioRunner = (url, key) {};
      player.loadSurahsRunner = () async => mockSurahs;

      bool playCalled = false;
      player.playResilientRunner = (url, {player, primaryUrl, fallbackUrls = const [], cacheKey, localDownloadedPath, onStopCallback}) async {
        playCalled = true;
        return true;
      };

      // 1:7 is the last ayah of Surah 1 (ayahCount = 7)
      player.currentPlayingKey.value = '1:7';
      player.isPlaying.value = true;

      playerStateController.add(PlayerState(false, ProcessingState.completed));
      await tester.pump();

      expect(playCalled, isFalse);
      expect(player.currentPlayingKey.value, isNull);
      expect(player.isPlaying.value, isFalse);
    });

    testWidgets('Control Test 9: disabled auto-advance setting prevents next ayah playback', (tester) async {
      final player = AyahAudioPlayer.instance;
      player.resetForTesting();
      player.stopPlayerRunner = () async {};
      player.playerStateStreamOverride = playerStateController.stream;
      player.prefetchAudioRunner = (url, key) {};
      player.loadSurahsRunner = () async => mockSurahs;

      await SettingsService.instance.toggleAutoPlayNextAyah(false);

      bool playCalled = false;
      player.playResilientRunner = (url, {player, primaryUrl, fallbackUrls = const [], cacheKey, localDownloadedPath, onStopCallback}) async {
        playCalled = true;
        return true;
      };

      player.currentPlayingKey.value = '1:1';
      player.isPlaying.value = true;

      playerStateController.add(PlayerState(false, ProcessingState.completed));
      await tester.pump();

      expect(playCalled, isFalse);
      expect(player.currentPlayingKey.value, isNull);
      expect(player.isPlaying.value, isFalse);
    });

    testWidgets('Control Test 10: active service throw clears state when auto-advance still owns the session token', (tester) async {
      final player = AyahAudioPlayer.instance;
      player.resetForTesting();
      player.stopPlayerRunner = () async {};
      player.playerStateStreamOverride = playerStateController.stream;
      player.prefetchAudioRunner = (url, key) {};
      player.loadSurahsRunner = () async => mockSurahs;

      player.playResilientRunner = (url, {player, primaryUrl, fallbackUrls = const [], cacheKey, localDownloadedPath, onStopCallback}) async {
        throw Exception('Active stream error');
      };

      player.currentPlayingKey.value = '1:1';
      player.isPlaying.value = true;

      // Completed event triggers auto-advance
      playerStateController.add(PlayerState(false, ProcessingState.completed));
      await tester.pump();

      // Because auto-advance was active and claimed the new token, when playResilient throws,
      // the catch block must correctly clear state (distinct from returning false)
      expect(player.currentPlayingKey.value, isNull);
      expect(player.isPlaying.value, isFalse);
    });
  });
}
