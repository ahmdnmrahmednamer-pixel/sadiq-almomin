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
  Stream<PlayerState>? get playerStateStreamOverride => _playerStateStreamOverride;
  @visibleForTesting
  set playerStateStreamOverride(Stream<PlayerState>? stream) {
    _playerStateStreamOverride = stream;
    _setupPlayerStateListener();
  }

  Future<void> _stopPlayer() async {
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
        currentPlayingKey.value = null;
        isPlaying.value = false;
        if (finishedKey != null && SettingsService.instance.autoPlayNextAyah) {
          _advanceToNextAyahIfPossible(finishedKey, sessionId);
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

  Future<void> _advanceToNextAyahIfPossible(String finishedKey, int sessionId) async {
    int currentSessionToken = sessionId;
    try {
      if (currentSessionToken != _activePlaySessionId) return;
      final parts = finishedKey.split(':');
      if (parts.length != 2) return;
      final surahId = int.tryParse(parts[0]);
      final ayahNumber = int.tryParse(parts[1]);
      if (surahId == null || ayahNumber == null) return;

      final surahs = await (loadSurahsRunner ?? QuranRepository.loadSurahs)();
      if (currentSessionToken != _activePlaySessionId) return;

      final surah = surahs.where((s) => s.id == surahId).firstOrNull;
      if (surah != null && ayahNumber < surah.ayahCount) {
        final nextAyah = ayahNumber + 1;
        final reciter = SettingsService.instance.currentReciter;
        final primaryUrl = SettingsService.instance.getAyahAudioUrl(surahId, nextAyah);
        final sStr = surahId.toString().padLeft(3, '0');
        final aStr = nextAyah.toString().padLeft(3, '0');
        final fallbackAyahUrls = [
          'https://everyayah.com/data/Minshawy_Murattal_128kbps/$sStr$aStr.mp3',
          'https://everyayah.com/data/Husary_128kbps/$sStr$aStr.mp3',
          'https://everyayah.com/data/Alafasy_128kbps/$sStr$aStr.mp3',
        ].where((u) => u != primaryUrl).toList();

        currentSessionToken = ++_activePlaySessionId;
        currentPlayingKey.value = '$surahId:$nextAyah';
        _playingReciterId = reciter.id;
        isPlaying.value = true;

        final cacheKey = 'ayah_${reciter.id}_${surahId}_$nextAyah';
        final ok = await (playResilientRunner ?? FastAudioService.instance.playResilient)(
          primaryUrl,
          player: _player,
          primaryUrl: primaryUrl,
          fallbackUrls: fallbackAyahUrls,
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
          final prefetchUrl = SettingsService.instance.getAyahAudioUrl(surahId, nextAyah + 1);
          final prefetchKey = 'ayah_${reciter.id}_${surahId}_${nextAyah + 1}';
          if (prefetchAudioRunner != null) {
            prefetchAudioRunner!(prefetchUrl, prefetchKey);
          } else {
            unawaited(FastAudioService.instance.prefetchAudio(prefetchUrl, prefetchKey));
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

  Future<void> playAyah(BuildContext context, int surahId, int ayahNumber, {String? surahName}) async {
    final key = '$surahId:$ayahNumber';
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

      final primaryUrl = SettingsService.instance.getAyahAudioUrl(surahId, ayahNumber);
      final sStr = surahId.toString().padLeft(3, '0');
      final aStr = ayahNumber.toString().padLeft(3, '0');
      // Authentic verse-by-verse fallbacks for the EXACT requested ayah (never whole surah!)
      final fallbackAyahUrls = [
        'https://everyayah.com/data/Minshawy_Murattal_128kbps/$sStr$aStr.mp3',
        'https://everyayah.com/data/Husary_128kbps/$sStr$aStr.mp3',
        'https://everyayah.com/data/Alafasy_128kbps/$sStr$aStr.mp3',
      ].where((u) => u != primaryUrl).toList();

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
      final ok = await (playResilientRunner ?? FastAudioService.instance.playResilient)(
        primaryUrl,
        player: _player,
        primaryUrl: primaryUrl,
        fallbackUrls: fallbackAyahUrls,
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
        final nextUrl = SettingsService.instance.getAyahAudioUrl(surahId, ayahNumber + 1);
        final nextCacheKey = 'ayah_${reciter.id}_${surahId}_${ayahNumber + 1}';
        if (prefetchAudioRunner != null) {
          prefetchAudioRunner!(nextUrl, nextCacheKey);
        } else {
          unawaited(FastAudioService.instance.prefetchAudio(nextUrl, nextCacheKey));
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
              content: Text('تعذر تشغيل صوت القارئ ${reciter.nameAr}. يرجى التحقق من الاتصال بالإنترنت.'),
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

      final ok = await (playResilientRunner ?? FastAudioService.instance.playResilient)(
        surahUrl,
        player: _player,
        primaryUrl: surahUrl,
        fallbackUrls: [ayahUrl],
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

  Future<void> stop() async {
    _activePlaySessionId++;
    try {
      await _stopPlayer();
    } catch (_) {}
    currentPlayingKey.value = null;
    isPlaying.value = false;
  }

  void dispose() {
    _playerStateSub?.cancel();
    _playerStateSub = null;
    _player.dispose();
  }
}
