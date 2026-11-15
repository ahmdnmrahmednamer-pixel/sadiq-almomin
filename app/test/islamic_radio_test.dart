import 'dart:async';
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
      expect(stations.length, greaterThanOrEqualTo(35));

      final cairo = stations.firstWhere((s) => s.id == 'radio_cairo_live');
      expect(cairo.name, contains('القاهرة'));
      expect(cairo.streamUrl, contains('radiojar.com'));
      // Honest unverified community relay status documented
      expect(cairo.subtitle, contains('غير معتمد'));
      expect(cairo.countryOrOrigin, contains('ترحيل مجتمعي'));
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

      audioService.setAudioSourceOverride = (player, source) async {
        // Track which source is actually set on player
      };

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
  });

  group('IslamicRadioScreen Widget, Semantics & Dispose Tests', () {
    testWidgets('Renders screen with title, search, categories, and station cards with Semantics', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: IslamicRadioScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('الإذاعات الإسلامية والبث المباشر'), findsOneWidget);
      expect(find.text('إذاعة القرآن الكريم من القاهرة'), findsWidgets);
      expect(find.text('جميع الإذاعات'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(ChoiceChip), findsWidgets);
      expect(find.byType(Card), findsWidgets);
    });

    testWidgets('Dispose Race: Disposing screen while station connection is in-flight does not throw', (tester) async {
      final audioService = FastAudioService.instance;
      audioService.resetForTesting();

      final completer = Completer<AudioSource>();
      audioService.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, bool isLiveStream = false}) {
        return completer.future;
      };
      audioService.setAudioSourceOverride = (player, source) async {};

      await tester.pumpWidget(
        const MaterialApp(
          home: IslamicRadioScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap station card to trigger connection
      final cardFinder = find.byType(InkWell).first;
      await tester.tap(cardFinder);
      await tester.pump();

      // Dispose widget tree while connection is pending
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Done'))));
      await tester.pump();

      // Now complete the delayed connection
      completer.complete(AudioSource.uri(Uri.parse('https://test/delayed')));
      await tester.pumpAndSettle();

      // Successfully disposed without throwing setState after dispose
      expect(find.text('Done'), findsOneWidget);
    });
  });
}
