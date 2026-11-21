import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/surah.dart';
import '../services/quran_repository.dart';
import '../services/settings_service.dart';
import 'fast_audio_service.dart';

typedef PlayResilientFn = Future<bool> Function(
  String? positionalPrimaryUrl, {
  AudioPlayer? player,
  String? primaryUrl,
  List<String> fallbackUrls,
  String? cacheKey,
  String? localDownloadedPath,
  Future<void> Function()? onStopCallback,
});

typedef LoadSurahsFn = Future<List<Surah>> Function();
typedef PrefetchAudioFn = void Function(String url, String cacheKey);

class AyahAudioPlayer {
  static final AyahAudioPlayer instance = AyahAudioPlayer._internal();
  StreamSubscription<PlayerState>? _playerStateSub;
  int _activePlaySessionId = 0;

  /// Identifies the current request, including a start that is still loading.
  int get activeRequestId => _activePlaySessionId;

  /// Cancel only work still owned by the caller, never a newer request.
  Future<void> stopRequestIfCurrent(int requestId) async {
    if (requestId != _activePlaySessionId) return;
    await stop();
  }

  @visibleForTesting
  PlayResilientFn? playResilientRunner;

  @visibleForTesting
  Future<void> Function()? stopPlayerRunner;

  @visibleForTesting
  bool Function()? isPlayerPlayingOverride;

  @visibleForTesting
  LoadSurahsFn? loadSurahsRunner;

  @visibleForTesting
  PrefetchAudioFn? prefetchAudioRunner;

  bool get _isPlayerPlaying => isPlayerPlayingOverride != null
      ? isPlayerPlayingOverride!()
      : _player.playing;

  Stream<PlayerState>? _playerStateStreamOverride;
  @visibleForTesting
  Stream<PlayerState>? get playerStateStreamOverride =>
      _playerStateStreamOverride;
  @visibleForTesting
  set playerStateStreamOverride(Stream<PlayerState>? stream) {
    _playerStateStreamOverride = stream;
    _setupPlayerStateListener();
  }

  Future<void> _stopPlayer() async {
    // Revoke this player's pending central-engine start before any await.
    // Another player's focus must remain untouched.
    FastAudioService.instance.releaseAudioFocusFor(_player);
    if (stopPlayerRunner != null) {
      await stopPlayerRunner!();
    } else {
      await _player.stop();
    }
  }

  void _setupPlayerStateListener() {
    _playerStateSub?.cancel();
    final stream = playerStateStreamOverride ?? _player.playerStateStream;
    _playerStateSub = stream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        final finishedKey = currentPlayingKey.value;
        final sessionId = _activePlaySessionId;
        final finishedReciterId =
            _playingReciterId ?? SettingsService.instance.selectedReciterId;
        final focusToken = FastAudioService.instance.activePlaybackToken;
        currentPlayingKey.value = null;
        isPlaying.value = false;
        if (finishedKey != null && SettingsService.instance.autoPlayNextAyah) {
          _advanceToNextAyahIfPossible(
              finishedKey, sessionId, finishedReciterId, focusToken);
        }
      } else {
        isPlaying.value = state.playing;
      }
    });
  }

  @visibleForTesting
  void resetForTesting() {
    playResilientRunner = null;
    stopPlayerRunner = null;
    isPlayerPlayingOverride = null;
    loadSurahsRunner = null;
    prefetchAudioRunner = null;
    _playerStateStreamOverride = null;
    currentPlayingKey.value = null;
    isPlaying.value = false;
    _lastSurahName = null;
    _playingReciterId = null;
    _activePlaySessionId = 0;
    _setupPlayerStateListener();
  }

  AyahAudioPlayer._internal() {
    _setupPlayerStateListener();
  }

  final AudioPlayer _player = AudioPlayer();
  final ValueNotifier<String?> currentPlayingKey = ValueNotifier<String?>(null);
  final ValueNotifier<bool> isPlaying = ValueNotifier<bool>(false);
  String? _lastSurahName;
  String? _playingReciterId;

  Future<void> _advanceToNextAyahIfPossible(String finishedKey, int sessionId,
      String finishedReciterId, int focusToken) async {
    int currentSessionToken = sessionId;
    try {
      if (currentSessionToken != _activePlaySessionId) return;
      final parts = finishedKey.split(':');
      if (parts.length != 2) return;
      final surahId = int.tryParse(parts[0]);
      final ayahNumber = int.tryParse(parts[1]);
      if (surahId == null || ayahNumber == null) return;

      final surahs = await (loadSurahsRunner ?? QuranRepository.loadSurahs)();
      if (currentSessionToken != _activePlaySessionId ||
          focusToken != FastAudioService.instance.activePlaybackToken) return;

      final surah = surahs.where((s) => s.id == surahId).firstOrNull;
      if (surah != null && ayahNumber < surah.ayahCount) {
        final nextAyah = ayahNumber + 1;
        // Automatic continuation belongs to the recording that just finished,
        // not a newly browsed or externally saved preference.
        final selectedId = finishedReciterId;
        final reciter = SettingsService.resolveReciter(finishedReciterId);
        final primaryUrl = SettingsService.instance
            .getAyahAudioUrl(surahId, nextAyah, selectedId);

        currentSessionToken = ++_activePlaySessionId;
        currentPlayingKey.value = '$surahId:$nextAyah';
        _playingReciterId = reciter.id;
        isPlaying.value = true;

        final cacheKey = 'ayah_${reciter.id}_${surahId}_$nextAyah';
        final ok = await (playResilientRunner ??
            FastAudioService.instance.playResilient)(
          primaryUrl,
          player: _player,
          primaryUrl: primaryUrl,
          fallbackUrls: const [],
          cacheKey: cacheKey,
          onStopCallback: stop,
        );

        if (currentSessionToken != _activePlaySessionId) return;

        if (!ok) {
          currentPlayingKey.value = null;
          isPlaying.value = false;
          return;
        }

        if (nextAyah < surah.ayahCount) {
          final prefetchUrl = SettingsService.instance
              .getAyahAudioUrl(surahId, nextAyah + 1, selectedId);
          final prefetchKey = 'ayah_${reciter.id}_${surahId}_${nextAyah + 1}';
          if (prefetchAudioRunner != null) {
            prefetchAudioRunner!(prefetchUrl, prefetchKey);
          } else {
            unawaited(FastAudioService.instance
                .prefetchAudio(prefetchUrl, prefetchKey));
          }
        }
      }
    } catch (_) {
      if (currentSessionToken == _activePlaySessionId) {
        currentPlayingKey.value = null;
        isPlaying.value = false;
      }
    }
  }

  Future<void> playAyah(BuildContext context, int surahId, int ayahNumber,
      {String? surahName}) async {
    final key = '$surahId:$ayahNumber';
    final selectedId = SettingsService.instance.selectedReciterId;
    final reciter = SettingsService.instance.currentReciter;
    if (surahName != null) _lastSurahName = surahName;

    // Only toggle pause if the EXACT same ayah AND the EXACT same reciter is currently playing
    if (currentPlayingKey.value == key &&
        _playingReciterId == reciter.id &&
        _isPlayerPlaying) {
      await _player.pause();
      isPlaying.value = false;
      return;
    }

    final sessionId = ++_activePlaySessionId;

    try {
      currentPlayingKey.value = key;
      _playingReciterId = reciter.id;
      isPlaying.value = true;

      await _stopPlayer();
      if (sessionId != _activePlaySessionId) return;

      final primaryUrl = SettingsService.instance
          .getAyahAudioUrl(surahId, ayahNumber, selectedId);

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.volume_up, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تلاوة ${surahName ?? _lastSurahName ?? "السورة"} (آية $ayahNumber) — القارئ: ${reciter.nameAr}',
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFF1B4332),
          ),
        );
      }

      final cacheKey = 'ayah_${reciter.id}_${surahId}_$ayahNumber';
      final ok = await (playResilientRunner ??
          FastAudioService.instance.playResilient)(
        primaryUrl,
        player: _player,
        primaryUrl: primaryUrl,
        fallbackUrls: const [],
        cacheKey: cacheKey,
        onStopCallback: stop,
      );

      if (sessionId != _activePlaySessionId) return;

      if (!ok) {
        throw Exception('Could not stream reciter ${reciter.id}');
      }

      final surahs = await (loadSurahsRunner ?? QuranRepository.loadSurahs)();
      final surah = surahs.where((s) => s.id == surahId).firstOrNull;
      if (surah == null || ayahNumber < surah.ayahCount) {
        final nextUrl = SettingsService.instance
            .getAyahAudioUrl(surahId, ayahNumber + 1, selectedId);
        final nextCacheKey = 'ayah_${reciter.id}_${surahId}_${ayahNumber + 1}';
        if (prefetchAudioRunner != null) {
          prefetchAudioRunner!(nextUrl, nextCacheKey);
        } else {
          unawaited(
              FastAudioService.instance.prefetchAudio(nextUrl, nextCacheKey));
        }
      }
    } catch (e) {
      if (sessionId == _activePlaySessionId) {
        currentPlayingKey.value = null;
        isPlaying.value = false;
        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e is VerseRecordingUnavailable
                  ? e.message
                  : 'تعذر تشغيل صوت القارئ ${reciter.nameAr}. تحقق من الاتصال أو اختر تسجيلاً آخر بنفسك؛ لم يتغير اختيارك المحفوظ.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  /// Plays a quick voice preview of any Reciter (Surah Al-Fatihah) so the user hears that exact Sheikh's voice
  Future<bool> playReciterPreview(ReciterInfo reciter) async {
    if (_playingReciterId == reciter.id &&
        currentPlayingKey.value == 'preview_${reciter.id}' &&
        _isPlayerPlaying) {
      await stop();
      return false;
    }

    final sessionId = ++_activePlaySessionId;

    try {
      await _stopPlayer();
      if (sessionId != _activePlaySessionId) return false;

      _playingReciterId = reciter.id;
      currentPlayingKey.value = 'preview_${reciter.id}';
      isPlaying.value = true;

      final surahUrl = SettingsService.instance.getSurahAudioUrl(1, reciter.id);
      final ayahUrl =
          'https://everyayah.com/data/${reciter.subfolder}/001002.mp3';

      final ok = await (playResilientRunner ??
          FastAudioService.instance.playResilient)(
        surahUrl,
        player: _player,
        primaryUrl: surahUrl,
        fallbackUrls: reciter.hasVerseAudio ? [ayahUrl] : const [],
        cacheKey: 'preview_reciter_${reciter.id}',
        onStopCallback: stop,
      );

      if (sessionId != _activePlaySessionId) return false;

      if (!ok) {
        currentPlayingKey.value = null;
        isPlaying.value = false;
      }
      return ok;
    } catch (_) {
      if (sessionId == _activePlaySessionId) {
        currentPlayingKey.value = null;
        isPlaying.value = false;
      }
      return false;
    }
  }

  /// User-triggered preview feedback, without reporting stale or stopped work
  /// as a failed current request.
  Future<void> previewReciterWithFeedback(
      BuildContext context, ReciterInfo reciter) async {
    final togglingOff = _playingReciterId == reciter.id &&
        currentPlayingKey.value == 'preview_${reciter.id}' &&
        _isPlayerPlaying;
    final pending = playReciterPreview(reciter);
    final sessionId = _activePlaySessionId;
    final ok = await pending;
    if (ok ||
        togglingOff ||
        sessionId != _activePlaySessionId ||
        !context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'تعذر تشغيل عينة القارئ ${reciter.nameAr}. تحقق من الاتصال أو اختر قارئاً آخر بنفسك؛ لم يتم تشغيل قارئ بديل.'),
    ));
  }

  Future<void> stop() async {
    final sessionId = ++_activePlaySessionId;
    try {
      await _stopPlayer();
    } catch (_) {}
    if (sessionId != _activePlaySessionId) return;
    currentPlayingKey.value = null;
    isPlaying.value = false;
  }

  void dispose() {
    _playerStateSub?.cancel();
    _playerStateSub = null;
    _player.dispose();
  }
}
