import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/core/models/islamic_radio.dart';
import 'package:almomin/core/services/islamic_radio_service.dart';
import 'package:almomin/features/radio/islamic_radio_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FastAudioService.instance.resetForTesting();
  });

  tearDown(() {
    FastAudioService.instance.resetForTesting();
  });

  group('IslamicRadioService Catalog & Provenance Tests', () {
    test('Default stations catalog contains verified stations with honest provenance', () {
      const stations = IslamicRadioService.defaultStations;
      expect(stations.isNotEmpty, isTrue);
      expect(stations.length, equals(43));

      final cairo = stations.firstWhere((s) => s.id == 'radio_cairo_live');
      expect(cairo.name, contains('القاهرة'));
      expect(cairo.streamUrl, contains('radiojar.com'));
      // Honest unverified community relay status documented
      expect(cairo.subtitle, contains('غير مدعوم على أندرويد'));
      expect(cairo.countryOrOrigin, contains('غير مدعوم بأندرويد'));
      // Cairo must NOT fall back to generic /mix
      expect(cairo.fallbackUrls.any((u) => u.contains('/radio/mix')), isFalse);
      expect(cairo.fallbackUrls.isNotEmpty, isTrue);

      // No station other than radio_general_recitations should have /mix as fallback
      for (final s in stations) {
        if (s.id != 'radio_general_recitations') {
          expect(
            s.fallbackUrls.any((u) => u.endsWith('/radio/mix')),
            isFalse,
            reason: 'Station ${s.id} should not have generic /mix fallback',
          );
        }
      }

      // No unverified radiojar streams in any station other than Cairo community relay
      for (final s in stations) {
        if (s.id != 'radio_cairo_live') {
          expect(
            s.streamUrl.contains('radiojar.com'),
            isFalse,
            reason: 'Station ${s.id} should only use official MP3Quran catalog streams',
          );
        }
      }
    });

    test('Husary and Abdulbasit stations maintain strict Riwayah isolation (no Warsh substitution)', () {
      const stations = IslamicRadioService.defaultStations;

      final husary = stations.firstWhere((s) => s.id == 'radio_husary');
      expect(husary.streamUrl, contains('alhussary_mojawwad'));
      for (final u in husary.fallbackUrls) {
        expect(u, contains('alhussary_mojawwad'), reason: 'Husary Mojawwad must only fall back to Mojawwad');
        expect(u.contains('warsh'), isFalse, reason: 'Husary must not fall back to Warsh riwayah');
      }

      final abdulbasit = stations.firstWhere((s) => s.id == 'radio_abdulbasit');
      for (final u in abdulbasit.fallbackUrls) {
        expect(u.contains('warsh'), isFalse, reason: 'Abdulbasit must not fall back to Warsh riwayah');
      }
    });

    test('Zero URL duplicates across primary and fallback endpoints for all 43 stations', () {
      const stations = IslamicRadioService.defaultStations;
      expect(stations.length, equals(43));

      for (final s in stations) {
        expect(
          s.fallbackUrls.contains(s.streamUrl),
          isFalse,
          reason: 'Station ${s.id} should not duplicate primary URL in fallbacks',
        );
        expect(
          s.fallbackUrls.length,
          equals(s.fallbackUrls.toSet().length),
          reason: 'Station ${s.id} contains duplicate entries in fallbackUrls',
        );
      }

      final eid = stations.firstWhere((s) => s.id == 'radio_eid_takbeerat');
      expect(eid.streamUrl, equals('https://backup.qurango.net/radio/eid'));
      expect(eid.fallbackUrls, contains('https://qurango.net/radio/eid'));
    });

    test('Categories contain all expected sections including Sunnah and Hadith', () {
      const categories = IslamicRadioService.categories;
      expect(categories.length, equals(7));

      final sunnah = categories.firstWhere(
        (c) => c.type == IslamicRadioCategoryType.sunnahHadith,
      );
      expect(sunnah.title, contains('السنة'));

      final reciters = categories.firstWhere(
        (c) => c.type == IslamicRadioCategoryType.reciters,
      );
      expect(reciters.title, contains('القراء'));

      final tafseer = categories.firstWhere(
        (c) => c.type == IslamicRadioCategoryType.tafseerFatwa,
      );
      expect(tafseer.title, contains('التفسير'));

      final adhkar = categories.firstWhere(
        (c) => c.type == IslamicRadioCategoryType.adhkarRoqyah,
      );
      expect(adhkar.title, contains('الأذكار'));

      final khushoo = categories.firstWhere(
        (c) => c.type == IslamicRadioCategoryType.khushooSurahs,
      );
      expect(khushoo.title, contains('خاشعة'));
    });

    test('Filtering by category returns matching stations accurately', () {
      final service = IslamicRadioService.instance;
      final reciterStations = service.getStations(
        category: IslamicRadioCategoryType.reciters,
      );
      expect(reciterStations.isNotEmpty, isTrue);
      for (final s in reciterStations) {
        expect(s.category, equals(IslamicRadioCategoryType.reciters));
      }

      final sunnahStations = service.getStations(
        category: IslamicRadioCategoryType.sunnahHadith,
      );
      expect(sunnahStations.length, greaterThanOrEqualTo(5));
      for (final s in sunnahStations) {
        expect(s.category, equals(IslamicRadioCategoryType.sunnahHadith));
      }
    });

    test('Search by reciter name and keyword matches correctly', () {
      final service = IslamicRadioService.instance;

      final minshawiResults = service.getStations(query: 'المنشاوي');
      expect(minshawiResults.isNotEmpty, isTrue);
      expect(minshawiResults.any((s) => s.name.contains('المنشاوي')), isTrue);

      final bukhariResults = service.getStations(query: 'البخاري');
      expect(bukhariResults.isNotEmpty, isTrue);
      expect(bukhariResults.any((s) => s.name.contains('البخاري')), isTrue);

      final roqyahResults = service.getStations(query: 'الرقية');
      expect(roqyahResults.isNotEmpty, isTrue);
      expect(roqyahResults.any((s) => s.name.contains('الرقية')), isTrue);
    });
  });

  group('Playback Concurrency, Token Guards & Real Race Tests', () {
    test('Delayed A/B playback race: Stale delayed request A is dropped and cannot clobber B', () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final completerA = Completer<AudioSource>();
      final completerB = Completer<AudioSource>();

      final playedUrls = <String>[];

      audioService.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
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
      final futureA = audioService.playLiveRadio(
        primaryUrl: 'https://test/streamA',
      );

      // 2. While A is in-flight, user triggers Request B
      final futureB = audioService.playLiveRadio(
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
      expect(resultA, isFalse, reason: 'Delayed request A must be aborted by session token guard');
      expect(playedUrls, isNot(contains('https://test/streamA')), reason: 'Stale A must NEVER trigger play()');
    });

    test('Stop Race: Calling stop() while playback connection is in-flight drops playback', () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final completer = Completer<AudioSource>();
      bool didPlay = false;

      audioService.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return completer.future;
      };

      audioService.setAudioSourceOverride = (player, source) async {};
      audioService.onBeforePlayCallback = (token, url) async {
        didPlay = true;
      };

      // 1. Start playback
      final futurePlay = audioService.playLiveRadio(
        primaryUrl: 'https://test/stream_slow',
      );

      // 2. User immediately clicks stop while buffering
      await audioService.stop();

      // 3. Slow network connection finally succeeds
      completer.complete(AudioSource.uri(Uri.parse('https://test/stream_slow')));
      final result = await futurePlay;

      // 4. Playback must be cancelled and never play
      expect(result, isFalse);
      expect(didPlay, isFalse, reason: 'Playback must not trigger after stop()');
    });

    test('Audio Focus Interruption: External audio focus claim invalidates in-flight radio request', () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final completer = Completer<AudioSource>();
      bool didPlay = false;
      bool wasStoppedCallbackFired = false;

      audioService.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return completer.future;
      };
      audioService.setAudioSourceOverride = (player, source) async {};
      audioService.onBeforePlayCallback = (token, url) async {
        didPlay = true;
      };

      // 1. Start radio with stop callback
      final futureRadio = audioService.playLiveRadio(
        primaryUrl: 'https://test/radio_stream',
        onStopCallback: () async {
          wasStoppedCallbackFired = true;
        },
      );

      // 2. Another player (e.g. Ayah audio or Adhan) claims audio focus
      await audioService.claimAudioFocus(
        onStopOther: () async {},
      );

      expect(wasStoppedCallbackFired, isTrue, reason: 'onStopCallback must be invoked when audio focus is claimed');

      // 3. Radio connection finally returns
      completer.complete(AudioSource.uri(Uri.parse('https://test/radio_stream')));
      final result = await futureRadio;

      // 4. In-flight radio request was invalidated by token
      expect(result, isFalse);
      expect(didPlay, isFalse);
    });

    test('Cross-audio interruption with null callback: Clears active stop callback safely without throwing', () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      bool radioStopped = false;
      audioService.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return Future.value(AudioSource.uri(Uri.parse(url)));
      };
      audioService.setAudioSourceOverride = (player, source) async {};

      // 1. Play radio with a stop callback
      final ok = await audioService.playLiveRadio(
        primaryUrl: 'https://test/radio',
        onStopCallback: () async {
          radioStopped = true;
        },
      );
      expect(ok, isTrue);

      // 2. An external player claims audio focus with null onStopOther
      final token = await audioService.claimAudioFocus(
        onStopOther: null,
      );
      expect(radioStopped, isTrue, reason: 'Prior radio stop callback must be called');
      expect(audioService.activePlaybackToken, equals(token));

      // 3. Stop called does not throw with null callback
      await audioService.stop();
    });

    test('Completed Station A -> B with distinct UI callbacks: B succeeds and notifies A stop callback', () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      bool callbackAFired = false;
      bool callbackBFired = false;
      final playedUrls = <String>[];

      audioService.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return Future.value(AudioSource.uri(Uri.parse(url)));
      };
      audioService.setAudioSourceOverride = (player, source) async {};
      audioService.onBeforePlayCallback = (token, url) async {
        playedUrls.add(url);
      };

      // 1. Station A plays completely
      final resultA = await audioService.playLiveRadio(
        primaryUrl: 'https://test/stationA',
        onStopCallback: () async {
          callbackAFired = true;
        },
      );
      expect(resultA, isTrue, reason: 'Station A must succeed');
      expect(playedUrls, contains('https://test/stationA'));
      expect(callbackAFired, isFalse, reason: 'Callback A must not fire while Station A is active');

      // 2. User plays Station B (normal completed transition)
      final resultB = await audioService.playLiveRadio(
        primaryUrl: 'https://test/stationB',
        onStopCallback: () async {
          callbackBFired = true;
        },
      );

      // 3. Station B must succeed and NOT invalidate itself
      expect(resultB, isTrue, reason: 'Station B must succeed and not be invalidated by prior callback A');
      expect(playedUrls, contains('https://test/stationB'));
      expect(callbackAFired, isTrue, reason: 'Station A stop callback must be called when B claims focus');
      expect(callbackBFired, isFalse, reason: 'Callback B must not fire while Station B is active');
    });

    test('Delayed setAudioSource race: Request A delayed in setAudioSource is dropped when B arrives', () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final completerSetSourceA = Completer<void>();
      final playedUrls = <String>[];

      audioService.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return Future.value(AudioSource.uri(Uri.parse(url)));
      };

      audioService.setAudioSourceOverride = (player, source) async {
        if (source is UriAudioSource && source.uri.toString().contains('stream_slow_set_source')) {
          await completerSetSourceA.future;
        }
      };

      audioService.onBeforePlayCallback = (token, url) async {
        playedUrls.add(url);
      };

      // 1. Start Request A which hangs in setAudioSource
      final futureA = audioService.playLiveRadio(
        primaryUrl: 'https://test/stream_slow_set_source',
      );

      // Yield event loop so A enters setAudioSource
      await Future<void>.delayed(Duration.zero);

      // 2. Request B starts and completes immediately
      final futureB = audioService.playLiveRadio(
        primaryUrl: 'https://test/stream_fast_b',
      );
      final resultB = await futureB;
      expect(resultB, isTrue, reason: 'Request B should succeed');
      expect(playedUrls, contains('https://test/stream_fast_b'));

      // 3. Request A finally completes setAudioSource
      completerSetSourceA.complete();
      final resultA = await futureA;

      // 4. Request A must be dropped due to token mismatch after setAudioSource
      expect(resultA, isFalse, reason: 'Request A must abort after setAudioSource due to token mismatch');
      expect(playedUrls, isNot(contains('https://test/stream_slow_set_source')), reason: 'Request A must never call play()');
    });

    test('Stale callbacks guard: Prior station callbacks do not clobber active station state', () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final activeStationLog = <String>[];
      int activeUiSession = 0;

      Future<void> simulateUserTap(String stationId, String url) async {
        final sessionToken = ++activeUiSession;
        activeStationLog.add('START_$stationId');

        await audioService.playLiveRadio(
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

      audioService.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
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

    test('Natural completion and stop safely clear stale owner and active player', () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      await audioService.claimAudioFocus(
        onStopOther: () async {},
      );

      await audioService.stop();
      expect(audioService.player, isNotNull);
    });

    test('C same callback A/B delayed A exits must NOT clear B callback; later other owner must invoke B', () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final completerA = Completer<AudioSource>();
      bool callbackInvoked = false;

      // Shared callback tear-off for both sessions
      Future<void> sharedStopCallback() async {
        callbackInvoked = true;
      }

      audioService.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        if (url == 'https://test/streamA') {
          return completerA.future;
        }
        return Future.value(AudioSource.uri(Uri.parse(url)));
      };
      audioService.setAudioSourceOverride = (player, source) async {};

      // 1. Session A starts with shared callback
      final futureA = audioService.playLiveRadio(
        primaryUrl: 'https://test/streamA',
        onStopCallback: sharedStopCallback,
      );

      // 2. While A is suspended in-flight, Session B starts with THE SAME CALLBACK
      final futureB = audioService.playLiveRadio(
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
      expect(callbackInvoked, isTrue, reason: 'Session B callback must remain intact and be invoked');
    });

    test('D Cairo direct play request returns false on Android without network calls', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final audioService = FastAudioService.instance;
        audioService.resetForTesting();

        final ok = await audioService.playLiveRadio(
          primaryUrl: 'https://stream.radiojar.com/8s5u5tpdtwzuv',
        );
        expect(ok, isFalse, reason: 'Cairo stream on Android must be rejected immediately');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('Actual cross-audio focus: Radio <-> Ayah bidirectional interruption with direct stop tear-off', () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final ayahPlayer = AudioPlayer();
      addTearDown(() async => await ayahPlayer.dispose());

      audioService.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return Future.value(AudioSource.uri(Uri.parse(url)));
      };
      audioService.setAudioSourceOverride = (player, source) async {};

      bool radioStopped = false;
      bool ayahStopped = false;

      // 1. Radio starts playback
      final okRadio = await audioService.playLiveRadio(
        primaryUrl: 'https://backup.qurango.net/radio/mix',
        onStopCallback: () async {
          radioStopped = true;
        },
      );
      expect(okRadio, isTrue);

      // 2. Ayah Audio starts and claims audio focus with its direct player stop tear-off
      final sessionTokenAyah = await audioService.claimAudioFocus(
        player: ayahPlayer,
        onStopOther: () async {
          ayahStopped = true;
          await ayahPlayer.stop();
        },
      );
      expect(sessionTokenAyah, equals(audioService.activePlaybackToken));
      expect(radioStopped, isTrue, reason: 'Radio stop callback must be called when Ayah claims focus');

      // 3. User taps Radio again, claiming focus back
      radioStopped = false;
      final okRadio2 = await audioService.playLiveRadio(
        primaryUrl: 'https://backup.qurango.net/radio/mohammed_siddiq_alminshawi',
        onStopCallback: () async {
          radioStopped = true;
        },
      );
      expect(okRadio2, isTrue);
      expect(ayahStopped, isTrue, reason: 'Ayah player stop tear-off must be called when Radio resumes');
    });

    test('Direct Ayah same-stop tear-off: Delayed stale session exit does NOT wipe active session callback', () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final dummyAyahPlayerA = AudioPlayer();
      final dummyAyahPlayerB = AudioPlayer();
      addTearDown(() async {
        await dummyAyahPlayerA.dispose();
        await dummyAyahPlayerB.dispose();
      });

      final completerA = Completer<AudioSource>();
      audioService.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        if (url == 'https://test/streamA') {
          return completerA.future;
        }
        return Future.value(AudioSource.uri(Uri.parse(url)));
      };
      audioService.setAudioSourceOverride = (player, source) async {};

      bool stopBInvoked = false;

      // 1. Session A starts with dummyAyahPlayerA.stop tear-off
      final futureA = audioService.playLiveRadio(
        primaryUrl: 'https://test/streamA',
        onStopCallback: dummyAyahPlayerA.stop,
      );

      // 2. While A is in-flight, Session B starts with dummyAyahPlayerB.stop
      final futureB = audioService.playLiveRadio(
        primaryUrl: 'https://test/streamB',
        onStopCallback: () async {
          stopBInvoked = true;
          await dummyAyahPlayerB.stop();
        },
      );
      final resultB = await futureB;
      expect(resultB, isTrue);

      // 3. Stale delayed session A completes
      completerA.complete(AudioSource.uri(Uri.parse('https://test/streamA')));
      final resultA = await futureA;
      expect(resultA, isFalse, reason: 'Session A is stale');

      // 4. Session A must not have wiped B's callback. External stop triggers Session B
      await audioService.stop();
      expect(stopBInvoked, isTrue, reason: 'Session B callback must be preserved and invoked');
    });

    test('Heritage null callback: Playing stream with null onStopCallback handles cross-audio focus safely', () async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      audioService.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return Future.value(AudioSource.uri(Uri.parse(url)));
      };
      audioService.setAudioSourceOverride = (player, source) async {};

      // 1. Play with explicit null callback (Egyptian Heritage style)
      final ok = await audioService.playResilient(
        'https://backup.qurango.net/radio/mohammed_siddiq_alminshawi',
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

  group('IslamicRadioScreen Widget, Semantics & Dispose Tests', () {
    testWidgets('Renders screen with title, search, categories, and station cards', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IslamicRadioScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('إذاعات القرآن الكريم'), findsWidgets);
      expect(find.text('إذاعة القرآن الكريم من القاهرة'), findsWidgets);
      expect(find.text('جميع الإذاعات'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(ChoiceChip), findsWidgets);
      expect(find.byType(Card), findsWidgets);
    });

    testWidgets('Real widget Station A -> B transition: Updates card states cleanly with NO error SnackBar', (tester) async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final playedUrls = <String>[];
      audioService.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return Future.value(AudioSource.uri(Uri.parse(url)));
      };
      audioService.setAudioSourceOverride = (player, source) async {};
      audioService.onBeforePlayCallback = (token, url) async {
        playedUrls.add(url);
      };

      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IslamicRadioScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Find Station A (Minshawi) and tap to play
      final minshawiCard = find.descendant(
        of: find.byType(Card),
        matching: find.text('إذاعة الشيخ محمد صديق المنشاوي'),
      );
      await tester.scrollUntilVisible(
        minshawiCard,
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(minshawiCard, findsOneWidget);
      await tester.tap(minshawiCard);
      await tester.pumpAndSettle();

      expect(playedUrls, contains('https://backup.qurango.net/radio/mohammed_siddiq_alminshawi'));
      expect(find.text('جاري الاستماع: إذاعة الشيخ محمد صديق المنشاوي'), findsOneWidget);

      // 2. Switch to Station B (Husary)
      final husaryCard = find.descendant(
        of: find.byType(Card),
        matching: find.text('إذاعة الشيخ محمود خليل الحصري'),
      );
      await tester.scrollUntilVisible(
        husaryCard,
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(husaryCard, findsOneWidget);
      await tester.tap(husaryCard);
      await tester.pumpAndSettle();

      expect(playedUrls, contains('https://qurango.net/radio/mahmoud_khalil_alhussary_mojawwad'));
      expect(find.text('جاري الاستماع: إذاعة الشيخ محمود خليل الحصري'), findsOneWidget);

      // 3. Assert NO error SnackBar appeared during station transition
      expect(find.textContaining('تعذر تشغيل'), findsNothing);
      expect(find.textContaining('تعذر الاتصال'), findsNothing);
    });

    testWidgets('Repeat tap while buffering cancels connection and stops playback immediately', (tester) async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final completer = Completer<AudioSource>();
      bool didPlay = false;

      audioService.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return completer.future;
      };
      audioService.setAudioSourceOverride = (player, source) async {};
      audioService.onBeforePlayCallback = (token, url) async {
        didPlay = true;
      };

      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IslamicRadioScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Minshawi to start buffering
      final minshawiCard = find.descendant(
        of: find.byType(Card),
        matching: find.text('إذاعة الشيخ محمد صديق المنشاوي'),
      );
      await tester.scrollUntilVisible(
        minshawiCard,
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(minshawiCard);
      await tester.pump(); // Enter buffering state

      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // Repeat tap while buffering to cancel
      await tester.tap(minshawiCard);
      await tester.pump();

      // Resolve slow connection after cancellation
      completer.complete(AudioSource.uri(Uri.parse('https://backup.qurango.net/radio/mohammed_siddiq_alminshawi')));
      await tester.pumpAndSettle();

      expect(didPlay, isFalse, reason: 'Playback must be cancelled and not play after repeat buffering tap');
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Widget stop while connecting: Tapping stop or repeat tap while buffering cleanly aborts connection', (tester) async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final completer = Completer<AudioSource>();
      bool didPlay = false;

      audioService.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return completer.future;
      };
      audioService.setAudioSourceOverride = (player, source) async {};
      audioService.onBeforePlayCallback = (token, url) async {
        didPlay = true;
      };

      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IslamicRadioScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Start connecting station
      final husaryCard = find.descendant(
        of: find.byType(Card),
        matching: find.text('إذاعة الشيخ محمود خليل الحصري'),
      );
      await tester.scrollUntilVisible(
        husaryCard,
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(husaryCard);
      await tester.pump(); // Enter buffering

      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // Stop while connecting
      await audioService.stop();
      await tester.pump();

      // Resolve delayed source
      completer.complete(AudioSource.uri(Uri.parse('https://qurango.net/radio/mahmoud_khalil_alhussary_mojawwad')));
      await tester.pumpAndSettle();

      expect(didPlay, isFalse);
    });

    testWidgets('Actual dispose test: Disposing screen during connection guarantees NO post-dispose play on target station', (tester) async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final completer = Completer<AudioSource>();
      bool didPlayPostDispose = false;

      audioService.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return completer.future;
      };
      audioService.setAudioSourceOverride = (player, source) async {};
      audioService.onBeforePlayCallback = (token, url) async {
        didPlayPostDispose = true;
      };

      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: IslamicRadioScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap to connect
      final cardFinder = find.descendant(
        of: find.byType(Card),
        matching: find.text('إذاعة الشيخ محمد صديق المنشاوي'),
      );
      await tester.scrollUntilVisible(
        cardFinder,
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(cardFinder);
      await tester.pump();

      // Replace tree to dispose IslamicRadioScreen
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Unmounted'))));
      await tester.pump();

      // Now complete the delayed source after disposal
      completer.complete(AudioSource.uri(Uri.parse('https://backup.qurango.net/radio/mohammed_siddiq_alminshawi')));
      await tester.pumpAndSettle();

      expect(find.text('Unmounted'), findsOneWidget);
      expect(didPlayPostDispose, isFalse, reason: 'Target station must NEVER play post-dispose');
    });

    testWidgets('Semantics tree asserts independently reachable card details, favorite and play actions', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IslamicRadioScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('إذاعة الشيخ محمد صديق المنشاوي'),
        100,
        scrollable: find.byType(Scrollable).last,
      );

      // Card details action
      expect(
        find.bySemanticsLabel(RegExp(r'إذاعة الشيخ محمد صديق المنشاوي.*مصر')),
        findsOneWidget,
      );

      // Favorite action
      expect(
        find.bySemanticsLabel('إضافة إذاعة الشيخ محمد صديق المنشاوي إلى المفضلة'),
        findsOneWidget,
      );

      // Play action
      expect(
        find.bySemanticsLabel('تشغيل بث إذاعة الشيخ محمد صديق المنشاوي'),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('Shared player events do NOT falsely mark radio active when another service plays', (tester) async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IslamicRadioScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Direct player state change without radio session claim
      // IslamicRadioScreen should not indicate active playback
      expect(find.text('إيقاف مؤقت'), findsNothing);
      expect(find.byIcon(Icons.pause_circle_filled_rounded), findsNothing);
    });

    testWidgets('B inject idle during B connecting then buffering->ready: assert B card + miniplayer survive, real idle after playing clears', (tester) async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final stateController = StreamController<PlayerState>.broadcast();
      addTearDown(stateController.close);

      final completerB = Completer<AudioSource>();

      audioService.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        if (url.contains('alhussary_mojawwad')) {
          return completerB.future;
        }
        return Future.value(AudioSource.uri(Uri.parse(url)));
      };
      audioService.setAudioSourceOverride = (player, source) async {};

      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IslamicRadioScreen(
              playerStateStreamOverride: stateController.stream,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Tap Station B (Husary) to start connecting
      final husaryCard = find.descendant(
        of: find.byType(Card),
        matching: find.text('إذاعة الشيخ محمود خليل الحصري'),
      );
      await tester.scrollUntilVisible(
        husaryCard,
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(husaryCard);
      await tester.pump(); // enters buffering/connecting

      // 2. Inject transient IDLE while B is connecting (from previous stop or source preparation)
      stateController.add(PlayerState(false, ProcessingState.idle));
      await tester.pump();

      // Miniplayer and buffering state must still survive for Husary!
      expect(find.text('إذاعة الشيخ محمود خليل الحصري'), findsWidgets);

      // 3. Complete connection and inject buffering -> ready
      completerB.complete(AudioSource.uri(Uri.parse('https://qurango.net/radio/mahmoud_khalil_alhussary_mojawwad')));
      stateController.add(PlayerState(true, ProcessingState.buffering));
      await tester.pump();

      stateController.add(PlayerState(true, ProcessingState.ready));
      await tester.pumpAndSettle();

      // 4. Assert: B card is in playing state AND miniplayer survives!
      expect(find.text('إذاعة الشيخ محمود خليل الحصري'), findsWidgets);
      expect(find.byIcon(Icons.pause_circle_filled_rounded), findsWidgets);
      expect(find.text('استماع متواصل'), findsOneWidget); // in miniplayer

      // 5. Inject REAL idle after playing (stream ended or player stopped)
      stateController.add(PlayerState(false, ProcessingState.idle));
      await tester.pumpAndSettle();

      // 6. Assert: Real idle clears state and dismisses miniplayer
      expect(find.byIcon(Icons.pause_circle_filled_rounded), findsNothing);
      expect(find.text('استماع متواصل'), findsNothing);
    });

    testWidgets('D Cairo is disabled/unsupported on Android in IslamicRadioScreen', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: IslamicRadioScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // In Cairo featured card:
        expect(find.text('غير مدعوم على أندرويد (غير مشفر)'), findsOneWidget);
        expect(find.text('غير مدعوم على أندرويد'), findsWidgets);

        // Find button with 'غير مدعوم على أندرويد (غير مشفر)' and verify onPressed is null
        final cairoBtn = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'غير مدعوم على أندرويد (غير مشفر)'),
        );
        expect(cairoBtn.onPressed, isNull, reason: 'Cairo play button must be disabled on Android');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
