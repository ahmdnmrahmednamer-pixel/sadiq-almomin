import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

/// Centralized High-Performance Audio Engine & Smart Cache (محرك الصوت فائق السرعة v11)
/// Ensures strict Sheikh/Muezzin audio fidelity:
/// - Immediately stops any previous audio stream when switching Sheikhs/tracks.
/// - Hashes the exact target URL into every disk cache filename so two different URLs never collide.
/// - Purges legacy cache directories (`fast_audio_cache_v3`) to prevent stale cached files.
/// - Never substitutes a different Sheikh's audio as a fallback.
class FastAudioService {
  static final FastAudioService instance = FastAudioService._internal();
  FastAudioService._internal() {
    _setupSharedPlayerListener();
  }

  /// Builds a collision-resistant isolated cache key bound to both track ID and exact URL
  static String buildIsolatedCacheKey(String trackId, String url) =>
      '${trackId}_${url.hashCode.abs()}';

  Directory? _cacheDir;
  bool _isInitialized = false;
  AudioPlayer? _activePlayer;
  final AudioPlayer _sharedPlayer = AudioPlayer();
  StreamSubscription<PlayerState>? _sharedPlayerStateSub;
  Future<void> Function()? _activeCustomStopCallback;
  int _activeCallbackToken = 0;

  /// Shared AudioPlayer instance for direct service playback
  AudioPlayer get player => _sharedPlayer;

  @visibleForTesting
  Stream<PlayerState>? playerStateStreamOverride;

  /// Stream of player states for observing shared playback
  Stream<PlayerState> get playerStateStream =>
      playerStateStreamOverride ?? _sharedPlayer.playerStateStream;

  int _activePlaybackToken = 0;

  /// Returns current monotonic playback request token
  int get activePlaybackToken => _activePlaybackToken;

  void _setupSharedPlayerListener() {
    _sharedPlayerStateSub?.cancel();
    _sharedPlayerStateSub = _sharedPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (_activePlayer == _sharedPlayer) {
          _activePlayer = null;
          _activeCustomStopCallback = null;
        }
      }
    });
  }

  @visibleForTesting
  Future<AudioSource> Function(
    String url, {
    required String cacheKey,
    String? localDownloadedPath,
    bool isLiveStream,
  })? getFastAudioSourceOverride;

  @visibleForTesting
  Future<void> Function(int token, String url)? onBeforePlayCallback;

  @visibleForTesting
  Future<void> Function(AudioPlayer player, AudioSource source)? setAudioSourceOverride;

  @visibleForTesting
  Directory? get cacheDir => _cacheDir;

  @visibleForTesting
  bool get isInitialized => _isInitialized;

  @visibleForTesting
  void resetForTesting() {
    _activePlaybackToken = 0;
    _activeCallbackToken = 0;
    _activeCustomStopCallback = null;
    _activePlayer = null;
    getFastAudioSourceOverride = null;
    onBeforePlayCallback = null;
    setAudioSourceOverride = null;
    playerStateStreamOverride = null;
    _isInitialized = false;
    _cacheDir = null;
    _setupSharedPlayerListener();
  }

  /// Stops whichever player is currently active across the app and releases callbacks
  Future<void> stop() async {
    _activePlaybackToken++;
    _activeCallbackToken = 0;
    final cb = _activeCustomStopCallback;
    _activeCustomStopCallback = null;
    final ap = _activePlayer;
    _activePlayer = null;
    try {
      if (_sharedPlayer.playing) {
        await _sharedPlayer.stop();
      }
    } catch (_) {}
    if (ap != null && ap != _sharedPlayer) {
      try {
        if (ap.playing) {
          await ap.stop();
        }
      } catch (_) {}
    }
    if (cb != null) {
      try {
        await cb();
      } catch (_) {}
    }
  }

  /// Synchronously registers audio focus ownership and returns the newly assigned session token.
  int registerAudioFocus({
    AudioPlayer? player,
    Future<void> Function()? onStopOther,
  }) {
    final token = ++_activePlaybackToken;
    _activeCustomStopCallback = onStopOther;
    _activeCallbackToken = token;
    _activePlayer = player ?? _sharedPlayer;
    return token;
  }

  /// Invalidates pending starts only for this player. Never stops another owner.
  void releaseAudioFocusFor(AudioPlayer player) {
    if (_activePlayer != player) return;
    _activePlaybackToken++;
    _activeCallbackToken = 0;
    _activeCustomStopCallback = null;
    _activePlayer = null;
  }

  /// Coordinates audio players across the app so only one audio stream plays at a time.
  /// Synchronously registers focus and returns the assigned token after stopping prior audio.
  Future<int> claimAudioFocus({
    AudioPlayer? player,
    Future<void> Function()? onStopOther,
  }) async {
    final priorCallback = _activeCustomStopCallback;
    final priorPlayer = _activePlayer;
    final sessionToken = registerAudioFocus(player: player, onStopOther: onStopOther);

    if (player != null) {
      try {
        if (player.playing) {
          await player.stop();
        }
      } catch (_) {}
    }
    if (_sharedPlayer != player) {
      try {
        if (_sharedPlayer.playing) {
          await _sharedPlayer.stop();
        }
      } catch (_) {}
    }
    if (priorPlayer != null && priorPlayer != player && priorPlayer != _sharedPlayer) {
      try {
        if (priorPlayer.playing) {
          await priorPlayer.stop();
        }
      } catch (_) {}
    }
    if (priorCallback != null && priorCallback != onStopOther) {
      try {
        await priorCallback();
      } catch (_) {}
    }

    return sessionToken;
  }

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    followRedirects: true,
    maxRedirects: 6,
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 AlMominApp/11.0 (Isolated-Scholar-Audio-Engine)',
      'Connection': 'keep-alive',
      'Accept-Encoding': 'identity',
    },
  ));

  final Set<String> _activePrefetches = {};

  static const Map<String, String> fastStreamingHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 AlMominApp/11.0 (High-Speed-Audio-Engine Isolated-Scholar-Audio-Engine)',
    'Connection': 'keep-alive',
    'Accept-Encoding': 'identity',
  };

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      if (!kIsWeb) {
        final tempDir = await getTemporaryDirectory();
        // Clean up legacy v3 cache folder if it exists so old cross-scholar files are removed
        final legacyFolder = Directory('${tempDir.path}/fast_audio_cache_v3');
        if (await legacyFolder.exists()) {
          try {
            await legacyFolder.delete(recursive: true);
          } catch (_) {}
        }

        final cacheFolder =
            Directory('${tempDir.path}/fast_audio_cache_v11_isolated');
        if (!await cacheFolder.exists()) {
          await cacheFolder.create(recursive: true);
        }
        _cacheDir = cacheFolder;
      }
      _isInitialized = true;
    } catch (e) {
      debugPrint('FastAudioService init error: $e');
    }
  }

  /// Builds a deterministic, collision-free cache key bound to the exact URL
  String buildUrlBoundCacheKey(String baseKey, String url) {
    final sanitizedBase = baseKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final urlHash = url.trim().hashCode.abs();
    return '${sanitizedBase}_$urlHash';
  }

  /// Returns the cache file for a specific audio key if it exists
  File? getCachedFile(String cacheKey) {
    if (_cacheDir == null) return null;
    final file = File('${_cacheDir!.path}/$cacheKey.mp3');
    if (file.existsSync() && file.lengthSync() > 4096) {
      return file;
    }
    return null;
  }

  /// Resolves the fastest possible AudioSource for the exact requested URL and cacheKey
  Future<AudioSource> getFastAudioSource(
    String url, {
    required String cacheKey,
    String? localDownloadedPath,
    List<String> fallbackUrls = const [],
    bool isLiveStream = false,
  }) async {
    await init();

    // 0. Live stream bypass: NEVER serve or lookup cached file for live broadcast streams
    if (isLiveStream) {
      if (!kIsWeb && _cacheDir != null) {
        try {
          final urlBoundKey = buildUrlBoundCacheKey(cacheKey, url);
          final staleFile = File('${_cacheDir!.path}/$urlBoundKey.mp3');
          if (staleFile.existsSync()) {
            staleFile.deleteSync();
          }
        } catch (_) {}
      }
      return AudioSource.uri(Uri.parse(url), headers: fastStreamingHeaders);
    }

    // 1. Explicitly downloaded user offline file
    if (localDownloadedPath != null) {
      final f = File(localDownloadedPath);
      if (f.existsSync() && f.lengthSync() > 1000) {
        return AudioSource.file(localDownloadedPath);
      }
    }

    // 2. Bundled asset path support if passed as asset:/// or assets/
    if (url.startsWith('assets/')) {
      return AudioSource.asset(url);
    }

    // 3. Previously cached stream file bound to this exact URL
    final urlBoundKey = buildUrlBoundCacheKey(cacheKey, url);
    final cached = getCachedFile(urlBoundKey);
    if (cached != null) {
      return AudioSource.file(cached.path);
    }

    // 4. Direct URI AudioSource (handles 302 redirects on Archive.org, IslamHouse, Islamway, Piped natively)
    return AudioSource.uri(Uri.parse(url), headers: fastStreamingHeaders);
  }

  /// Resilient playback that ONLY plays the requested Sheikh/track candidates and NEVER substitutes a different Sheikh.
  Future<bool> playResilient(
    String? positionalPrimaryUrl, {
    AudioPlayer? player,
    String? primaryUrl,
    List<String> fallbackUrls = const [],
    String? cacheKey,
    String? localDownloadedPath,
    bool isLiveStream = false,
    Future<void> Function()? onStopCallback,
  }) async {
    final targetPlayer = player ?? _sharedPlayer;
    final mainUrl = (primaryUrl ?? positionalPrimaryUrl ?? '').trim();
    if (mainUrl.isEmpty && fallbackUrls.isEmpty && localDownloadedPath == null) {
      return false;
    }

    // Android disallows cleartext HTTP traffic. This known Cairo relay redirects to cleartext HTTP.
    // Note: iOS App Transport Security (ATS) carries inferred cleartext risk for this relay unless exception is set.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (mainUrl.contains('radiojar.com/8s5u5tpdtwzuv') || mainUrl.contains('8s5u5tpdtwzuv')) {
        return false;
      }
    }

    // 1. Explicitly claim audio focus, returning the assigned session token
    final sessionToken = await claimAudioFocus(
      player: targetPlayer,
      onStopOther: onStopCallback,
    );
    if (sessionToken != _activePlaybackToken) {
      return false;
    }

    try {
      await targetPlayer.stop();
    } catch (_) {}
    if (sessionToken != _activePlaybackToken) {
      return false;
    }

    final effectiveCacheKey =
        cacheKey ?? 'stream_${mainUrl.hashCode.abs()}';

    final candidateUrls = <String>[
      if (mainUrl.isNotEmpty) mainUrl,
      ...fallbackUrls.where((u) => u.trim().isNotEmpty),
    ];

    for (int i = 0; i < candidateUrls.length; i++) {
      if (sessionToken != _activePlaybackToken) {
        return false;
      }
      final targetUrl = candidateUrls[i].trim();
      if (targetUrl.isEmpty) continue;

      if (targetUrl.startsWith('assets/')) {
        try {
          await targetPlayer.setAsset(targetUrl);
          if (sessionToken != _activePlaybackToken) {
            return false;
          }
          unawaited(targetPlayer.play());
          return true;
        } catch (e) {
          debugPrint('Asset playback failed for $targetUrl: $e');
          continue;
        }
      }

      final urlBoundKey = buildUrlBoundCacheKey(effectiveCacheKey, targetUrl);

      // Tier 1: Fast cached local file or direct native URI streaming (supports 302 redirects & m4a/mp3/ogg)
      try {
        final source = getFastAudioSourceOverride != null
            ? await getFastAudioSourceOverride!(
                targetUrl,
                cacheKey: effectiveCacheKey,
                localDownloadedPath: i == 0 ? localDownloadedPath : null,
                isLiveStream: isLiveStream,
              )
            : await getFastAudioSource(
                targetUrl,
                cacheKey: effectiveCacheKey,
                localDownloadedPath: i == 0 ? localDownloadedPath : null,
                isLiveStream: isLiveStream,
              );
        if (sessionToken != _activePlaybackToken) {
          return false;
        }

        if (setAudioSourceOverride != null) {
          await setAudioSourceOverride!(targetPlayer, source);
        } else {
          await targetPlayer.setAudioSource(source);
        }
        if (sessionToken != _activePlaybackToken) {
          return false;
        }

        if (onBeforePlayCallback != null) {
          await onBeforePlayCallback!(sessionToken, targetUrl);
        }
        if (sessionToken != _activePlaybackToken) {
          return false;
        }

        unawaited(targetPlayer.play());
        // Prefetch in background for offline reuse (NEVER for live streams)
        if (!isLiveStream) {
          unawaited(prefetchAudio(targetUrl, urlBoundKey));
        }
        return true;
      } catch (e) {
        debugPrint('Tier 1 playback failed for URL $i ($targetUrl): $e');
      }

      // Tier 2: LockCachingAudioSource fallback if direct URI source threw (ONLY for static tracks, NOT for live streams)
      if (!isLiveStream && !kIsWeb && _cacheDir != null) {
        try {
          if (sessionToken != _activePlaybackToken) {
            return false;
          }
          final targetCacheFile = File('${_cacheDir!.path}/$urlBoundKey.mp3');
          final lockSource = LockCachingAudioSource(
            Uri.parse(targetUrl),
            cacheFile: targetCacheFile,
            headers: fastStreamingHeaders,
          );
          if (sessionToken != _activePlaybackToken) {
            return false;
          }
          await targetPlayer.setAudioSource(lockSource);
          if (sessionToken != _activePlaybackToken) {
            return false;
          }
          unawaited(targetPlayer.play());
          return true;
        } catch (e) {
          debugPrint('Tier 2 LockCaching failed for URL $i ($targetUrl): $e');
        }
      }
    }

    if (sessionToken == _activePlaybackToken && sessionToken == _activeCallbackToken) {
      _activeCustomStopCallback = null;
    }
    return false;
  }

  /// Specialized zero-latency player for 24/7 Islamic Live Radios & Maspero broadcasts
  /// Strictly guarantees no disk caching, no lock freezing, and resilient multi-mirror switching.
  Future<bool> playLiveRadio({
    required String primaryUrl,
    List<String> fallbackUrls = const [],
    String? cacheKey,
    Future<void> Function()? onStopCallback,
  }) async {
    return playResilient(
      primaryUrl,
      fallbackUrls: fallbackUrls,
      cacheKey: cacheKey,
      isLiveStream: true,
      onStopCallback: onStopCallback,
    );
  }

  /// Pre-warms/prefetches an audio track in background
  Future<void> prefetchAudio(String url, String cacheKey) async {
    if (kIsWeb || url.startsWith('assets/')) return;
    await init();

    final urlBoundKey = cacheKey.contains('${url.trim().hashCode.abs()}')
        ? cacheKey
        : buildUrlBoundCacheKey(cacheKey, url);

    if (_activePrefetches.contains(urlBoundKey)) return;
    if (getCachedFile(urlBoundKey) != null) return;

    _activePrefetches.add(urlBoundKey);
    try {
      final targetFile = File('${_cacheDir?.path}/$urlBoundKey.mp3.part');
      final response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: fastStreamingHeaders,
        ),
      );

      if (response.data != null && response.data!.length > 4096) {
        await targetFile.writeAsBytes(response.data!);
        final finalFile = File('${_cacheDir?.path}/$urlBoundKey.mp3');
        if (targetFile.existsSync()) {
          await targetFile.rename(finalFile.path);
        }
      }
    } catch (e) {
      debugPrint('Background audio prefetch skipped for $urlBoundKey: $e');
    } finally {
      _activePrefetches.remove(urlBoundKey);
    }
  }

  /// Sets up audio player and triggers play with minimum buffering latency
  Future<void> playWithZeroDelay(
    AudioPlayer player,
    AudioSource source, {
    double speed = 1.0,
    Duration? initialPosition,
    Future<void> Function()? onStopCallback,
  }) async {
    await claimAudioFocus(player: player, onStopOther: onStopCallback);
    try {
      await player.stop();
    } catch (_) {}

    await player.setAudioSource(
      source,
      initialPosition: initialPosition,
      preload: true,
    );
    if (speed != 1.0) {
      await player.setSpeed(speed);
    }
    unawaited(player.play());
  }
}
