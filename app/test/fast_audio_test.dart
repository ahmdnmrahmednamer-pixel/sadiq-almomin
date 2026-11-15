import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory isolatedTempDir;
  late FastAudioService service;

  setUp(() {
    isolatedTempDir = Directory.systemTemp.createTempSync('almomin_fast_audio_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getTemporaryDirectory') {
          return isolatedTempDir.path;
        }
        return null;
      },
    );

    service = FastAudioService.instance;
    service.resetForTesting();
  });

  tearDown(() {
    service.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );

    if (isolatedTempDir.existsSync()) {
      try {
        isolatedTempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('FastAudioService High-Speed Audio Engine & Cache Isolation Tests', () {
    test('Fast streaming headers contain keep-alive and identity encoding', () {
      const headers = FastAudioService.fastStreamingHeaders;
      expect(headers['Connection'], 'keep-alive');
      expect(headers['Accept-Encoding'], 'identity');
      expect(headers['User-Agent'], contains('High-Speed-Audio-Engine'));
    });

    test('Cache initialization creates isolated v11 cache directory and purges legacy v3 cache', () async {
      // 1. Pre-create legacy v3 folder to verify automatic cleanup
      final legacyDir = Directory('${isolatedTempDir.path}/fast_audio_cache_v3');
      legacyDir.createSync(recursive: true);
      final legacyFile = File('${legacyDir.path}/stale_scholar_audio.mp3');
      legacyFile.writeAsStringSync('stale legacy audio content');
      expect(legacyDir.existsSync(), isTrue);

      // 2. Initialize engine
      await service.init();

      expect(service.isInitialized, isTrue);
      expect(service.cacheDir, isNotNull);
      expect(service.cacheDir!.existsSync(), isTrue);
      expect(service.cacheDir!.path, endsWith('fast_audio_cache_v11_isolated'));

      // 3. Verify legacy v3 folder was purged
      expect(legacyDir.existsSync(), isFalse);
    });

    test('getFastAudioSource returns UriAudioSource with streaming headers for remote URL', () async {
      const remoteUrl = 'https://server8.mp3quran.net/afs/001.mp3';
      final source = await service.getFastAudioSource(
        remoteUrl,
        cacheKey: 'test_surah_001',
      );

      expect(source, isA<UriAudioSource>());
      final uriSource = source as UriAudioSource;
      expect(uriSource.uri.toString(), equals(remoteUrl));
      expect(uriSource.headers, isNotNull);
      expect(uriSource.headers?['Connection'], equals('keep-alive'));
      expect(uriSource.headers?['Accept-Encoding'], equals('identity'));
    });

    test('getFastAudioSource returns ProgressiveAudioSource file source for valid local offline file', () async {
      final localFile = File('${isolatedTempDir.path}/downloaded_ayah.mp3');
      await localFile.writeAsBytes(List.filled(2048, 7));

      final source = await service.getFastAudioSource(
        'https://server8.mp3quran.net/afs/001.mp3',
        cacheKey: 'test_surah_local',
        localDownloadedPath: localFile.path,
      );

      expect(source, isA<ProgressiveAudioSource>());
      final uriSource = source as UriAudioSource;
      expect(uriSource.uri.scheme, equals('file'));
      expect(uriSource.uri.toFilePath().replaceAll(r'\', '/'), equals(localFile.path.replaceAll(r'\', '/')));
    });

    test('getFastAudioSource returns UriAudioSource asset scheme for asset paths', () async {
      const assetPath = 'assets/audio/takbeerat.mp3';
      final source = await service.getFastAudioSource(
        assetPath,
        cacheKey: 'test_asset',
      );

      expect(source, isA<UriAudioSource>());
      final uriSource = source as UriAudioSource;
      expect(uriSource.uri.scheme, equals('asset'));
      expect(uriSource.uri.path, contains('assets/audio/takbeerat.mp3'));
    });

    test('getFastAudioSource for live stream bypasses cache and removes any stale cached file', () async {
      await service.init();
      const liveStreamUrl = 'https://backup.qurango.net/radio/mix';
      const liveCacheKey = 'live_radio_mix';

      // Pre-seed a stale cache file in the isolated cache directory
      final boundKey = service.buildUrlBoundCacheKey(liveCacheKey, liveStreamUrl);
      final staleCacheFile = File('${service.cacheDir!.path}/$boundKey.mp3');
      staleCacheFile.writeAsStringSync('stale stream segment that should be purged');
      expect(staleCacheFile.existsSync(), isTrue);

      final source = await service.getFastAudioSource(
        liveStreamUrl,
        cacheKey: liveCacheKey,
        isLiveStream: true,
      );

      expect(source, isA<UriAudioSource>());
      final uriSource = source as UriAudioSource;
      expect(uriSource.uri.toString(), equals(liveStreamUrl));
      // Stale cache file must be deleted on live stream playback
      expect(staleCacheFile.existsSync(), isFalse);
    });

    test('getCachedFile and getFastAudioSource return file source when valid cached file exists', () async {
      await service.init();
      const targetUrl = 'https://server8.mp3quran.net/afs/002.mp3';
      const baseKey = 'surah_baqarah';
      final boundKey = service.buildUrlBoundCacheKey(baseKey, targetUrl);

      // Write valid cached file (> 4096 bytes)
      final cacheFile = File('${service.cacheDir!.path}/$boundKey.mp3');
      await cacheFile.writeAsBytes(List.filled(5000, 3));

      // 1. getCachedFile must detect it
      final detected = service.getCachedFile(boundKey);
      expect(detected, isNotNull);
      expect(detected!.path, equals(cacheFile.path));

      // 2. getFastAudioSource must return file source pointing to cached file
      final source = await service.getFastAudioSource(
        targetUrl,
        cacheKey: baseKey,
      );
      expect(source, isA<ProgressiveAudioSource>());
      final uriSource = source as UriAudioSource;
      expect(uriSource.uri.scheme, equals('file'));
      expect(uriSource.uri.toFilePath().replaceAll(r'\', '/'), equals(cacheFile.path.replaceAll(r'\', '/')));
    });

    test('getCachedFile returns null for missing or undersized (< 4096 bytes) cache files', () async {
      await service.init();

      // Non-existent key
      expect(service.getCachedFile('non_existent_key_12345'), isNull);

      // Undersized file (e.g. 512 bytes)
      const undersizedKey = 'undersized_partial_audio';
      final undersizedFile = File('${service.cacheDir!.path}/$undersizedKey.mp3');
      await undersizedFile.writeAsBytes(List.filled(512, 0));

      expect(service.getCachedFile(undersizedKey), isNull);
    });
  });
}
