import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';

// Shared engine regressions retained after removal of the removed live-broadcast feature.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FastAudioService.instance.resetForTesting());
  tearDown(() => FastAudioService.instance.resetForTesting());
  group('Playback Concurrency, Token Guards & Real Race Tests', () {
    test(
        'Delayed A/B playback race: Stale delayed request A is dropped and cannot clobber B',
        () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final completerA = Completer<AudioSource>();
      final completerB = Completer<AudioSource>();

      final playedUrls = <String>[];

      audioService.getFastAudioSourceOverride = (url,
          {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        if (url == 'https://test/streamA') {
          return completerA.future;
        } else if (url == 'https://test/streamB') {
          return completerB.future;
        }
        return Future.value(AudioSource.uri(Uri.parse(url)));
      };

      audioService.setAudioSourceOverride = (player, source) async {};
      audioService.onBeforePlayCallback = (token, url) async {
        playedUrls.add(url);
      };

      // 1. Start Request A (slow connection)
      final futureA = audioService.playResilient(
        null,
        isLiveStream: true,
        primaryUrl: 'https://test/streamA',
      );

      // 2. While A is in-flight, user triggers Request B
      final futureB = audioService.playResilient(
        null,
        isLiveStream: true,
        primaryUrl: 'https://test/streamB',
      );

      // 3. Resolve B first
      completerB.complete(AudioSource.uri(Uri.parse('https://test/streamB')));
      final resultB = await futureB;
      expect(resultB, isTrue, reason: 'Request B should succeed');
      expect(playedUrls, contains('https://test/streamB'));

      // 4. Now delayed Request A finally arrives
      completerA.complete(AudioSource.uri(Uri.parse('https://test/streamA')));
      final resultA = await futureA;

      // 5. Assert: Request A was detected as stale and returned false
      expect(resultA, isFalse,
          reason: 'Delayed request A must be aborted by session token guard');
      expect(playedUrls, isNot(contains('https://test/streamA')),
          reason: 'Stale A must NEVER trigger play()');
    });

    test(
        'Stop Race: Calling stop() while playback connection is in-flight drops playback',
        () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final completer = Completer<AudioSource>();
      bool didPlay = false;

      audioService.getFastAudioSourceOverride = (url,
          {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return completer.future;
      };

      audioService.setAudioSourceOverride = (player, source) async {};
      audioService.onBeforePlayCallback = (token, url) async {
        didPlay = true;
      };

      // 1. Start playback
      final futurePlay = audioService.playResilient(
        null,
        isLiveStream: true,
        primaryUrl: 'https://test/stream_slow',
      );

      // 2. User immediately clicks stop while buffering
      await audioService.stop();

      // 3. Slow network connection finally succeeds
      completer
          .complete(AudioSource.uri(Uri.parse('https://test/stream_slow')));
      final result = await futurePlay;

      // 4. Playback must be cancelled and never play
      expect(result, isFalse);
      expect(didPlay, isFalse,
          reason: 'Playback must not trigger after stop()');
    });

    test(
        'Audio Focus Interruption: External audio focus claim invalidates in-flight network request',
        () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final completer = Completer<AudioSource>();
      bool didPlay = false;
      bool wasStoppedCallbackFired = false;

      audioService.getFastAudioSourceOverride = (url,
          {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return completer.future;
      };
      audioService.setAudioSourceOverride = (player, source) async {};
      audioService.onBeforePlayCallback = (token, url) async {
        didPlay = true;
      };

      // 1. Start network audio with stop callback
      final futureNetworkStream = audioService.playResilient(
        null,
        isLiveStream: true,
        primaryUrl: 'https://test/network_stream',
        onStopCallback: () async {
          wasStoppedCallbackFired = true;
        },
      );

      // 2. Another player (e.g. Ayah audio or Adhan) claims audio focus
      await audioService.claimAudioFocus(
        onStopOther: () async {},
      );

      expect(wasStoppedCallbackFired, isTrue,
          reason: 'onStopCallback must be invoked when audio focus is claimed');

      // 3. NetworkStream connection finally returns
      completer
          .complete(AudioSource.uri(Uri.parse('https://test/network_stream')));
      final result = await futureNetworkStream;

      // 4. In-flight network request was invalidated by token
      expect(result, isFalse);
      expect(didPlay, isFalse);
    });

    test(
        'Cross-audio interruption with null callback: Clears active stop callback safely without throwing',
        () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      bool networkStopped = false;
      audioService.getFastAudioSourceOverride = (url,
          {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return Future.value(AudioSource.uri(Uri.parse(url)));
      };
      audioService.setAudioSourceOverride = (player, source) async {};

      // 1. Play network audio with a stop callback
      final ok = await audioService.playResilient(
        null,
        isLiveStream: true,
        primaryUrl: 'https://example.test/network-audio',
        onStopCallback: () async {
          networkStopped = true;
        },
      );
      expect(ok, isTrue);

      // 2. An external player claims audio focus with null onStopOther
      final token = await audioService.claimAudioFocus(
        onStopOther: null,
      );
      expect(networkStopped, isTrue,
          reason: 'Prior network audio stop callback must be called');
      expect(audioService.activePlaybackToken, equals(token));

      // 3. Stop called does not throw with null callback
      await audioService.stop();
    });

    test(
        'Completed Station A -> B with distinct UI callbacks: B succeeds and notifies A stop callback',
        () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      bool callbackAFired = false;
      bool callbackBFired = false;
      final playedUrls = <String>[];

      audioService.getFastAudioSourceOverride = (url,
          {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return Future.value(AudioSource.uri(Uri.parse(url)));
      };
      audioService.setAudioSourceOverride = (player, source) async {};
      audioService.onBeforePlayCallback = (token, url) async {
        playedUrls.add(url);
      };

      // 1. Station A plays completely
      final resultA = await audioService.playResilient(
        null,
        isLiveStream: true,
        primaryUrl: 'https://test/stationA',
        onStopCallback: () async {
          callbackAFired = true;
        },
      );
      expect(resultA, isTrue, reason: 'Station A must succeed');
      expect(playedUrls, contains('https://test/stationA'));
      expect(callbackAFired, isFalse,
          reason: 'Callback A must not fire while Station A is active');

      // 2. User plays Station B (normal completed transition)
      final resultB = await audioService.playResilient(
        null,
        isLiveStream: true,
        primaryUrl: 'https://test/stationB',
        onStopCallback: () async {
          callbackBFired = true;
        },
      );

      // 3. Station B must succeed and NOT invalidate itself
      expect(resultB, isTrue,
          reason:
              'Station B must succeed and not be invalidated by prior callback A');
      expect(playedUrls, contains('https://test/stationB'));
      expect(callbackAFired, isTrue,
          reason: 'Station A stop callback must be called when B claims focus');
      expect(callbackBFired, isFalse,
          reason: 'Callback B must not fire while Station B is active');
    });

    test(
        'Delayed setAudioSource race: Request A delayed in setAudioSource is dropped when B arrives',
        () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final completerSetSourceA = Completer<void>();
      final playedUrls = <String>[];

      audioService.getFastAudioSourceOverride = (url,
          {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return Future.value(AudioSource.uri(Uri.parse(url)));
      };

      audioService.setAudioSourceOverride = (player, source) async {
        if (source is UriAudioSource &&
            source.uri.toString().contains('stream_slow_set_source')) {
          await completerSetSourceA.future;
        }
      };

      audioService.onBeforePlayCallback = (token, url) async {
        playedUrls.add(url);
      };

      // 1. Start Request A which hangs in setAudioSource
      final futureA = audioService.playResilient(
        null,
        isLiveStream: true,
        primaryUrl: 'https://test/stream_slow_set_source',
      );

      // Yield event loop so A enters setAudioSource
      await Future<void>.delayed(Duration.zero);

      // 2. Request B starts and completes immediately
      final futureB = audioService.playResilient(
        null,
        isLiveStream: true,
        primaryUrl: 'https://test/stream_fast_b',
      );
      final resultB = await futureB;
      expect(resultB, isTrue, reason: 'Request B should succeed');
      expect(playedUrls, contains('https://test/stream_fast_b'));

      // 3. Request A finally completes setAudioSource
      completerSetSourceA.complete();
      final resultA = await futureA;

      // 4. Request A must be dropped due to token mismatch after setAudioSource
      expect(resultA, isFalse,
          reason:
              'Request A must abort after setAudioSource due to token mismatch');
      expect(playedUrls, isNot(contains('https://test/stream_slow_set_source')),
          reason: 'Request A must never call play()');
    });

    test(
        'Stale callbacks guard: Prior station callbacks do not clobber active station state',
        () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final activeStationLog = <String>[];
      int activeUiSession = 0;

      Future<void> simulateUserTap(String stationId, String url) async {
        final sessionToken = ++activeUiSession;
        activeStationLog.add('START_$stationId');

        await audioService.playResilient(
          null,
          isLiveStream: true,
          primaryUrl: url,
          onStopCallback: () async {
            if (sessionToken == activeUiSession) {
              activeStationLog.add('STOP_ACTIVE_$stationId');
            } else {
              activeStationLog.add('DROPPED_STALE_CALLBACK_$stationId');
            }
          },
        );

        if (sessionToken == activeUiSession) {
          activeStationLog.add('PLAYING_$stationId');
        }
      }

      audioService.getFastAudioSourceOverride = (url,
          {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return Future.value(AudioSource.uri(Uri.parse(url)));
      };
      audioService.setAudioSourceOverride = (player, source) async {};

      // 1. Play station 1
      await simulateUserTap('station1', 'https://test/s1');
      expect(activeStationLog, contains('PLAYING_station1'));

      // 2. Switch to station 2
      await simulateUserTap('station2', 'https://test/s2');
      expect(activeStationLog, contains('DROPPED_STALE_CALLBACK_station1'));
      expect(activeStationLog, contains('PLAYING_station2'));

      // 3. Switch to station 3
      await simulateUserTap('station3', 'https://test/s3');
      expect(activeStationLog, contains('DROPPED_STALE_CALLBACK_station2'));
      expect(activeStationLog, contains('PLAYING_station3'));
      expect(activeStationLog, isNot(contains('STOP_ACTIVE_station1')));
      expect(activeStationLog, isNot(contains('STOP_ACTIVE_station2')));
    });

    test(
        'Natural completion and stop safely clear stale owner and active player',
        () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      await audioService.claimAudioFocus(
        onStopOther: () async {},
      );

      await audioService.stop();
      expect(audioService.player, isNotNull);
    });

    test(
        'C same callback A/B delayed A exits must NOT clear B callback; later other owner must invoke B',
        () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final completerA = Completer<AudioSource>();
      bool callbackInvoked = false;

      // Shared callback tear-off for both sessions
      Future<void> sharedStopCallback() async {
        callbackInvoked = true;
      }

      audioService.getFastAudioSourceOverride = (url,
          {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        if (url == 'https://test/streamA') {
          return completerA.future;
        }
        return Future.value(AudioSource.uri(Uri.parse(url)));
      };
      audioService.setAudioSourceOverride = (player, source) async {};

      // 1. Session A starts with shared callback
      final futureA = audioService.playResilient(
        null,
        isLiveStream: true,
        primaryUrl: 'https://test/streamA',
        onStopCallback: sharedStopCallback,
      );

      // 2. While A is suspended in-flight, Session B starts with THE SAME CALLBACK
      final futureB = audioService.playResilient(
        null,
        isLiveStream: true,
        primaryUrl: 'https://test/streamB',
        onStopCallback: sharedStopCallback,
      );
      final resultB = await futureB;
      expect(resultB, isTrue, reason: 'Session B must succeed');

      // 3. Delayed Session A finally completes and detects itself as stale
      completerA.complete(AudioSource.uri(Uri.parse('https://test/streamA')));
      final resultA = await futureA;
      expect(resultA, isFalse, reason: 'Session A is stale');

      // 4. Session A's exit must NOT have cleared Session B's callback
      callbackInvoked = false;
      await audioService.claimAudioFocus(onStopOther: () async {});

      // 5. Assert: Session B's callback was invoked by the newer owner
      expect(callbackInvoked, isTrue,
          reason: 'Session B callback must remain intact and be invoked');
    });

    test(
        'D Cairo direct play request returns false on Android without network calls',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final audioService = FastAudioService.instance;
        audioService.resetForTesting();

        final ok = await audioService.playResilient(
          null,
          isLiveStream: true,
          primaryUrl: 'https://stream.radiojar.com/8s5u5tpdtwzuv',
        );
        expect(ok, isFalse,
            reason: 'Cairo stream on Android must be rejected immediately');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test(
        'Actual cross-audio focus: NetworkStream <-> Ayah bidirectional interruption with direct stop tear-off',
        () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final ayahPlayer = AudioPlayer();
      addTearDown(() async => await ayahPlayer.dispose());

      audioService.getFastAudioSourceOverride = (url,
          {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return Future.value(AudioSource.uri(Uri.parse(url)));
      };
      audioService.setAudioSourceOverride = (player, source) async {};

      bool networkStopped = false;
      bool ayahStopped = false;

      // 1. NetworkStream starts playback
      final okNetworkStream = await audioService.playResilient(
        null,
        isLiveStream: true,
        primaryUrl: 'https://example.test/audio-a.mp3',
        onStopCallback: () async {
          networkStopped = true;
        },
      );
      expect(okNetworkStream, isTrue);

      // 2. Ayah Audio starts and claims audio focus with its direct player stop tear-off
      final sessionTokenAyah = await audioService.claimAudioFocus(
        player: ayahPlayer,
        onStopOther: () async {
          ayahStopped = true;
          await ayahPlayer.stop();
        },
      );
      expect(sessionTokenAyah, equals(audioService.activePlaybackToken));
      expect(networkStopped, isTrue,
          reason:
              'NetworkStream stop callback must be called when Ayah claims focus');

      // 3. User taps NetworkStream again, claiming focus back
      networkStopped = false;
      final okNetworkStream2 = await audioService.playResilient(
        null,
        isLiveStream: true,
        primaryUrl: 'https://example.test/audio-b.mp3',
        onStopCallback: () async {
          networkStopped = true;
        },
      );
      expect(okNetworkStream2, isTrue);
      expect(ayahStopped, isTrue,
          reason:
              'Ayah player stop tear-off must be called when NetworkStream resumes');
    });

    test(
        'playResilient real ayah path: A/B with identical sameAudioPlayer.stop tearoff, delayed stale A exit preserves active callback for B',
        () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final sameAudioPlayer = AudioPlayer();
      addTearDown(() async => await sameAudioPlayer.dispose());

      int stopTearoffCallCount = 0;
      Future<void> sameAudioPlayerStopTearoff() async {
        stopTearoffCallCount++;
        await sameAudioPlayer.stop();
      }

      final completerA = Completer<AudioSource>();
      audioService.getFastAudioSourceOverride = (url,
          {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        if (url == 'https://everyayah.com/data/Minshawy/001001.mp3') {
          return completerA.future;
        }
        return Future.value(AudioSource.uri(Uri.parse(url)));
      };
      audioService.setAudioSourceOverride = (player, source) async {};

      // 1. Session A starts real ayah playback with sameAudioPlayer and its stop tearoff
      final futureA = audioService.playResilient(
        'https://everyayah.com/data/Minshawy/001001.mp3',
        player: sameAudioPlayer,
        onStopCallback: sameAudioPlayerStopTearoff,
      );

      // 2. While Session A is in-flight, Session B starts for next ayah with the EXACT SAME tearoff
      final futureB = audioService.playResilient(
        'https://everyayah.com/data/Minshawy/001002.mp3',
        player: sameAudioPlayer,
        onStopCallback: sameAudioPlayerStopTearoff,
      );
      final resultB = await futureB;
      expect(resultB, isTrue, reason: 'Session B must succeed');

      // 3. Stale delayed session A completes and exits
      completerA.complete(AudioSource.uri(
          Uri.parse('https://everyayah.com/data/Minshawy/001001.mp3')));
      final resultA = await futureA;
      expect(resultA, isFalse,
          reason: 'Session A is stale and aborted by token guard');

      // 4. Session A delayed exit must NOT have cleared Session B callback
      // When external owner stops audio focus:
      stopTearoffCallCount = 0;
      await audioService.stop();
      expect(stopTearoffCallCount, equals(1),
          reason:
              'Identical stop tearoff for active Session B must be invoked on stop');
    });

    test(
        'Heritage null callback: Playing stream with null onStopCallback handles cross-audio focus safely',
        () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      audioService.getFastAudioSourceOverride = (url,
          {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return Future.value(AudioSource.uri(Uri.parse(url)));
      };
      audioService.setAudioSourceOverride = (player, source) async {};

      // 1. Play with explicit null callback (Egyptian Heritage style)
      final ok = await audioService.playResilient(
        'https://example.test/audio-b.mp3',
        isLiveStream: true,
        onStopCallback: null,
      );
      expect(ok, isTrue);

      // 2. Another service claims focus with null prior callback without throwing
      bool newOwnerCalled = false;
      await audioService.claimAudioFocus(
        onStopOther: () async {
          newOwnerCalled = true;
        },
      );

      await audioService.stop();
      expect(newOwnerCalled, isTrue);
    });
  });
}
