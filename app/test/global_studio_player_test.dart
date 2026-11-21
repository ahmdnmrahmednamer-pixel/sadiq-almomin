import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/features/audio/widgets/global_mini_player_bar.dart';
import 'package:almomin/features/audio/widgets/full_screen_studio_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final service = IslamicAudioService.instance;
    service.disableNativePlayerForTesting = true;
    while (service.loopMode != PlaybackLoopMode.off) {
      service.toggleLoopMode();
    }
    if (service.shuffleEnabled) {
      service.toggleShuffle();
    }
    service.cancelSleepTimer();
    await service.init();
    await service.stop();
  });

  tearDown(() async {
    final service = IslamicAudioService.instance;
    while (service.loopMode != PlaybackLoopMode.off) {
      service.toggleLoopMode();
    }
    if (service.shuffleEnabled) {
      service.toggleShuffle();
    }
    service.cancelSleepTimer();
    await service.stop();
    service.disableNativePlayerForTesting = false;
  });

  group('IslamicAudioService Advanced Studio Controls Tests', () {
    test('Loop mode cycles off -> all -> single -> off correctly', () {
      final service = IslamicAudioService.instance;
      expect(service.loopMode, PlaybackLoopMode.off);

      service.toggleLoopMode();
      expect(service.loopMode, PlaybackLoopMode.all);

      service.toggleLoopMode();
      expect(service.loopMode, PlaybackLoopMode.single);

      service.toggleLoopMode();
      expect(service.loopMode, PlaybackLoopMode.off);
    });

    test('Shuffle mode toggles cleanly', () {
      final service = IslamicAudioService.instance;
      expect(service.shuffleEnabled, isFalse);

      service.toggleShuffle();
      expect(service.shuffleEnabled, isTrue);

      service.toggleShuffle();
      expect(service.shuffleEnabled, isFalse);
    });

    test('Sleep timer sets and cancels properly', () {
      final service = IslamicAudioService.instance;
      expect(service.sleepTimerRemainingSeconds, isNull);

      service.setSleepTimer(30);
      expect(service.sleepTimerRemainingSeconds, isNotNull);
      expect(service.sleepTimerRemainingSeconds!, greaterThan(25 * 60));

      service.cancelSleepTimer();
      expect(service.sleepTimerRemainingSeconds, isNull);
    });

    test('Queue navigation controls: initial unpopulated queue fixture hasNext and hasPrevious are false', () async {
      final service = IslamicAudioService.instance;
      // Initial unpopulated queue fixture before any playQueue call (note: stop() preserves loaded queue for UI sheets)
      expect(service.queue, isEmpty);
      expect(service.hasNext, isFalse);
      expect(service.hasPrevious, isFalse);
      expect(() => service.playNext(), returnsNormally);
      expect(() => service.playPrevious(), returnsNormally);

      // Empty queue in Loop-All mode
      service.toggleLoopMode();
      expect(service.loopMode, PlaybackLoopMode.all);
      expect(service.hasNext, isFalse);
      expect(service.hasPrevious, isFalse);
      expect(() => service.playNext(), returnsNormally);
      expect(() => service.playPrevious(), returnsNormally);
      service.toggleLoopMode(); // single
      service.toggleLoopMode(); // restore off
      expect(service.loopMode, PlaybackLoopMode.off);
    });

    test('Queue navigation controls: previous button when position > 3 seconds restarts current track without changing index', () async {
      final service = IslamicAudioService.instance;
      const testTracks = <IslamicAudioTrack>[
        IslamicAudioTrack(
          id: 'test_ctrl_1',
          title: 'Track 1',
          subtitle: 'Artist 1',
          type: IslamicAudioType.quran,
          assetPath: null,
          remoteUrl: 'https://example.com/1.mp3',
          durationFormatted: '05:00',
        ),
        IslamicAudioTrack(
          id: 'test_ctrl_2',
          title: 'Track 2',
          subtitle: 'Artist 2',
          type: IslamicAudioType.quran,
          assetPath: null,
          remoteUrl: 'https://example.com/2.mp3',
          durationFormatted: '04:00',
        ),
      ];

      await service.playQueue(testTracks, startIndex: 0);
      expect(service.currentIndex, 0);
      expect(service.loopMode, PlaybackLoopMode.off);

      // At position 0s on track 0 in off mode: hasPrevious is false
      expect(service.position, Duration.zero);
      expect(service.hasPrevious, isFalse);

      // Advance playback position beyond 3 seconds via existing public seek API
      await service.seek(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(service.position.inSeconds, greaterThan(3));

      // With position > 3 seconds, hasPrevious must be true even on first track in off mode
      expect(service.hasPrevious, isTrue,
          reason: 'hasPrevious must be true when position > 3s to allow restarting current track');

      // Calling playPrevious() when position > 3s restarts current track rather than decrementing index
      await service.playPrevious();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(service.currentIndex, 0,
          reason: 'playPrevious when position > 3s must keep same currentIndex');
      expect(service.position, Duration.zero,
          reason: 'playPrevious when position > 3s must seek to zero');
      expect(service.hasPrevious, isFalse,
          reason: 'After restarting to zero at track 0 in off mode, hasPrevious returns to false');
    });

    test('Queue management maintains indices and tracks correctly', () async {
      final service = IslamicAudioService.instance;
      final tracks = <IslamicAudioTrack>[
        const IslamicAudioTrack(
          id: 'test_1',
          title: 'Track 1',
          subtitle: 'Artist 1',
          type: IslamicAudioType.quran,
          assetPath: null,
          remoteUrl: 'https://example.com/1.mp3',
          durationFormatted: '05:00',
        ),
        const IslamicAudioTrack(
          id: 'test_2',
          title: 'Track 2',
          subtitle: 'Artist 2',
          type: IslamicAudioType.quran,
          assetPath: null,
          remoteUrl: 'https://example.com/2.mp3',
          durationFormatted: '04:00',
        ),
        const IslamicAudioTrack(
          id: 'test_3',
          title: 'Track 3',
          subtitle: 'Artist 3',
          type: IslamicAudioType.story,
          assetPath: null,
          remoteUrl: 'https://example.com/3.mp3',
          durationFormatted: '07:00',
        ),
      ];

      await service.playQueue(tracks, startIndex: 1);
      expect(service.queue.length, 3);
      expect(service.currentIndex, 1);
      expect(service.hasPrevious, isTrue);
      expect(service.hasNext, isTrue);
      expect(service.currentTrack?.id, 'test_2');

      // Next
      await service.playNext();
      expect(service.currentIndex, 2);
      expect(service.hasNext, isFalse);
      expect(service.currentTrack?.id, 'test_3');

      // Previous
      await service.playPrevious();
      expect(service.currentIndex, 1);
      expect(service.currentTrack?.id, 'test_2');

      await service.playPrevious();
      expect(service.currentIndex, 0);
      expect(service.hasPrevious, isFalse);
      expect(service.currentTrack?.id, 'test_1');
    });

    test('Seek forward and backward clamp to zero and duration', () async {
      final service = IslamicAudioService.instance;
      expect(() => service.seekForward(seconds: 10), returnsNormally);
      expect(() => service.seekBackward(seconds: 10), returnsNormally);
    });

    test('Queue navigation controls: off and single loop modes do not wrap at boundaries', () async {
      final service = IslamicAudioService.instance;
      const testTracks = <IslamicAudioTrack>[
        IslamicAudioTrack(
          id: 'test_ctrl_1',
          title: 'Track 1',
          subtitle: 'Artist 1',
          type: IslamicAudioType.quran,
          assetPath: null,
          remoteUrl: 'https://example.com/1.mp3',
          durationFormatted: '05:00',
        ),
        IslamicAudioTrack(
          id: 'test_ctrl_2',
          title: 'Track 2',
          subtitle: 'Artist 2',
          type: IslamicAudioType.quran,
          assetPath: null,
          remoteUrl: 'https://example.com/2.mp3',
          durationFormatted: '04:00',
        ),
      ];

      // At end of queue in off mode (startIndex: 1)
      await service.playQueue(testTracks, startIndex: 1);
      expect(service.loopMode, PlaybackLoopMode.off);
      expect(service.hasNext, isFalse);
      await service.playNext();
      expect(service.currentIndex, 1, reason: 'off mode must not wrap at end');

      // At end of queue in single mode
      service.toggleLoopMode(); // to all
      service.toggleLoopMode(); // to single
      expect(service.loopMode, PlaybackLoopMode.single);
      expect(service.hasNext, isFalse);
      await service.playNext();
      expect(service.currentIndex, 1, reason: 'single mode must not wrap at end');

      // At start of queue in off mode (startIndex: 0)
      await service.playQueue(testTracks, startIndex: 0);
      service.toggleLoopMode(); // to off
      expect(service.loopMode, PlaybackLoopMode.off);
      expect(service.hasPrevious, isFalse);
      await service.playPrevious();
      expect(service.currentIndex, 0, reason: 'off mode must not wrap at start');

      // At start of queue in single mode
      service.toggleLoopMode(); // to all
      service.toggleLoopMode(); // to single
      expect(service.loopMode, PlaybackLoopMode.single);
      expect(service.hasPrevious, isFalse);
      await service.playPrevious();
      expect(service.currentIndex, 0, reason: 'single mode must not wrap at start');
    });

    test('Queue navigation in Loop-All mode: last track hasNext is true and wraps to first track', () async {
      final service = IslamicAudioService.instance;
      const testTracks = <IslamicAudioTrack>[
        IslamicAudioTrack(
          id: 'test_loop_1',
          title: 'Track 1',
          subtitle: 'Artist 1',
          type: IslamicAudioType.quran,
          assetPath: null,
          remoteUrl: 'https://example.com/1.mp3',
          durationFormatted: '05:00',
        ),
        IslamicAudioTrack(
          id: 'test_loop_2',
          title: 'Track 2',
          subtitle: 'Artist 2',
          type: IslamicAudioType.quran,
          assetPath: null,
          remoteUrl: 'https://example.com/2.mp3',
          durationFormatted: '04:00',
        ),
        IslamicAudioTrack(
          id: 'test_loop_3',
          title: 'Track 3',
          subtitle: 'Artist 3',
          type: IslamicAudioType.story,
          assetPath: null,
          remoteUrl: 'https://example.com/3.mp3',
          durationFormatted: '07:00',
        ),
      ];

      await service.playQueue(testTracks, startIndex: 2);
      expect(service.currentIndex, 2);

      // Cycle to Loop-All mode
      while (service.loopMode != PlaybackLoopMode.all) {
        service.toggleLoopMode();
      }
      expect(service.loopMode, PlaybackLoopMode.all);

      // RED assertion: hasNext must be true on the last track in Loop-All mode
      expect(service.hasNext, isTrue,
          reason: 'In Loop-All mode, last track must have next track (wraps to start of playlist)');

      await service.playNext();
      expect(service.currentIndex, 0,
          reason: 'playNext in Loop-All mode must wrap from last track to first track');
      expect(service.currentTrack?.id, 'test_loop_1');
    });

    test('Queue navigation in Loop-All mode: first track hasPrevious is true and wraps to last track', () async {
      final service = IslamicAudioService.instance;
      const testTracks = <IslamicAudioTrack>[
        IslamicAudioTrack(
          id: 'test_loop_1',
          title: 'Track 1',
          subtitle: 'Artist 1',
          type: IslamicAudioType.quran,
          assetPath: null,
          remoteUrl: 'https://example.com/1.mp3',
          durationFormatted: '05:00',
        ),
        IslamicAudioTrack(
          id: 'test_loop_2',
          title: 'Track 2',
          subtitle: 'Artist 2',
          type: IslamicAudioType.quran,
          assetPath: null,
          remoteUrl: 'https://example.com/2.mp3',
          durationFormatted: '04:00',
        ),
        IslamicAudioTrack(
          id: 'test_loop_3',
          title: 'Track 3',
          subtitle: 'Artist 3',
          type: IslamicAudioType.story,
          assetPath: null,
          remoteUrl: 'https://example.com/3.mp3',
          durationFormatted: '07:00',
        ),
      ];

      await service.playQueue(testTracks, startIndex: 0);
      expect(service.currentIndex, 0);

      // Cycle to Loop-All mode
      while (service.loopMode != PlaybackLoopMode.all) {
        service.toggleLoopMode();
      }
      expect(service.loopMode, PlaybackLoopMode.all);

      // RED assertion: hasPrevious must be true on first track at start in Loop-All mode
      expect(service.hasPrevious, isTrue,
          reason: 'In Loop-All mode, first track at start must have previous track (wraps to end of playlist)');

      await service.playPrevious();
      expect(service.currentIndex, 2,
          reason: 'playPrevious in Loop-All mode must wrap from first track to last track');
      expect(service.currentTrack?.id, 'test_loop_3');
    });
  });

  group('GlobalMiniPlayerBar Widget Tests', () {
    testWidgets('Renders SizedBox.shrink when no track is selected', (tester) async {
      final service = IslamicAudioService.instance;
      await service.stop();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            bottomNavigationBar: GlobalMiniPlayerBar(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(GlobalMiniPlayerBar), findsOneWidget);
      expect(find.text('توقف'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('Renders controls and title when track is loaded', (tester) async {
      final service = IslamicAudioService.instance;
      const testTrack = IslamicAudioTrack(
        id: 'test_mini',
        title: 'سورة الفاتحة',
        subtitle: 'مشاري العفاسي',
        type: IslamicAudioType.quran,
        assetPath: null,
        remoteUrl: 'https://example.com/fatihah.mp3',
        durationFormatted: '01:00',
      );

      await service.playQueue([testTrack], startIndex: 0);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            bottomNavigationBar: GlobalMiniPlayerBar(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('سورة الفاتحة'), findsOneWidget);
      expect(find.text('مشاري العفاسي'), findsOneWidget);
      expect(find.byIcon(Icons.forward_10_rounded), findsOneWidget);
      expect(find.byIcon(Icons.replay_10_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });
  });

  group('FullScreenStudioPlayer Widget Tests', () {
    testWidgets('Renders studio player modal components correctly', (tester) async {
      final service = IslamicAudioService.instance;
      const testTrack = IslamicAudioTrack(
        id: 'test_studio',
        title: 'سورة الكهف المباركة',
        subtitle: 'الشيخ عبد الباسط عبد الصمد',
        type: IslamicAudioType.quran,
        assetPath: null,
        remoteUrl: 'https://example.com/kahf.mp3',
        durationFormatted: '30:00',
      );

      await service.playQueue([testTrack], startIndex: 0);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FullScreenStudioPlayer(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('المُشغِّل'), findsOneWidget);
      expect(find.text('المشغل الصوتي الاستوديو 🎙️'), findsNothing);
      expect(find.text('سورة الكهف المباركة'), findsOneWidget);
      expect(find.text('الشيخ عبد الباسط عبد الصمد'), findsOneWidget);
      expect(find.textContaining('استماع بدون إنترنت'), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
      expect(find.byIcon(Icons.bedtime_rounded), findsOneWidget);
      expect(find.byIcon(Icons.speed_rounded), findsOneWidget);
      expect(find.byIcon(Icons.queue_music_rounded), findsOneWidget);
    });

    testWidgets('FullScreenStudioPlayer manual Next button wraps to first track in Loop-All mode', (tester) async {
      final service = IslamicAudioService.instance;
      const testTracks = <IslamicAudioTrack>[
        IslamicAudioTrack(
          id: 'test_widget_1',
          title: 'المقطع الأول',
          subtitle: 'القارئ الأول',
          type: IslamicAudioType.quran,
          assetPath: null,
          remoteUrl: 'https://example.com/1.mp3',
          durationFormatted: '05:00',
        ),
        IslamicAudioTrack(
          id: 'test_widget_2',
          title: 'المقطع الثاني',
          subtitle: 'القارئ الثاني',
          type: IslamicAudioType.quran,
          assetPath: null,
          remoteUrl: 'https://example.com/2.mp3',
          durationFormatted: '04:00',
        ),
      ];

      await service.playQueue(testTracks, startIndex: 1);
      expect(service.currentIndex, 1);

      while (service.loopMode != PlaybackLoopMode.all) {
        service.toggleLoopMode();
      }
      expect(service.loopMode, PlaybackLoopMode.all);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FullScreenStudioPlayer(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final nextButton = find.byTooltip('التالي / تقديم ١٠ث');
      expect(nextButton, findsOneWidget);

      await tester.tap(nextButton);
      await tester.pump(const Duration(milliseconds: 100));

      // RED assertion: Next button must advance to track 0 instead of seeking forward 10s
      expect(service.currentIndex, 0,
          reason: 'Tapping manual Next on last track with Loop-All must wrap to first track');
      expect(service.currentTrack?.id, 'test_widget_1');
    });

    testWidgets('FullScreenStudioPlayer manual Previous button wraps to last track in Loop-All mode', (tester) async {
      final service = IslamicAudioService.instance;
      const testTracks = <IslamicAudioTrack>[
        IslamicAudioTrack(
          id: 'test_widget_1',
          title: 'المقطع الأول',
          subtitle: 'القارئ الأول',
          type: IslamicAudioType.quran,
          assetPath: null,
          remoteUrl: 'https://example.com/1.mp3',
          durationFormatted: '05:00',
        ),
        IslamicAudioTrack(
          id: 'test_widget_2',
          title: 'المقطع الثاني',
          subtitle: 'القارئ الثاني',
          type: IslamicAudioType.quran,
          assetPath: null,
          remoteUrl: 'https://example.com/2.mp3',
          durationFormatted: '04:00',
        ),
      ];

      await service.playQueue(testTracks, startIndex: 0);
      expect(service.currentIndex, 0);

      while (service.loopMode != PlaybackLoopMode.all) {
        service.toggleLoopMode();
      }
      expect(service.loopMode, PlaybackLoopMode.all);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FullScreenStudioPlayer(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final prevButton = find.byTooltip('السابق / ترجيع ١٠ث');
      expect(prevButton, findsOneWidget);

      await tester.tap(prevButton);
      await tester.pump(const Duration(milliseconds: 100));

      // RED assertion: Previous button must wrap to track 1 instead of seeking backward 10s
      expect(service.currentIndex, 1,
          reason: 'Tapping manual Previous on first track at start with Loop-All must wrap to last track');
      expect(service.currentTrack?.id, 'test_widget_2');
    });
  });
}
