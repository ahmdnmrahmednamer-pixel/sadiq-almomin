import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../audio/fast_audio_service.dart';
import '../audio/islamic_audio_catalog.dart';
import '../audio/islamic_audio_models.dart';

export '../audio/islamic_audio_models.dart';
import 'settings_service.dart';
import 'islamic_audio_file_integrity.dart';
import 'downloaded_adhan_assignments.dart';

class IslamicAudioService extends ChangeNotifier {
  static final IslamicAudioService instance = IslamicAudioService._internal();
  IslamicAudioService._internal()
      : _player = AudioPlayer(),
        _catalog = allTracks,
        _validateFile = validatedAudioFileStat;
  @visibleForTesting
  IslamicAudioService.forTesting(AudioPlayer player, {
    List<IslamicAudioTrack>? catalog,
    Future<FileStat?> Function(IslamicAudioTrack, File)? fileValidator,
  }) : _player = player,
       _catalog = List.unmodifiable(catalog ?? allTracks),
       _validateFile = fileValidator ?? validatedAudioFileStat;

  final List<IslamicAudioTrack> _catalog;
  final Future<FileStat?> Function(IslamicAudioTrack, File) _validateFile;

  /// Exact old catalog recordings held pending source/name review.
  /// The namespaced asset-only section is separate. Sharawi's alarm ID is
  /// deliberately preserved, not certified by this containment boundary.
  static const heldLegacyAdhkarIds = <String>{
    'adhkar_morning', 'adhkar_evening', 'adhkar_post_prayer', 'adhkar_sleep',
    'adhkar_waking', 'adhkar_home_mosque', 'prophetic_duas', 'ruqyah_shariah',
    'dua_khatm_abdulbasit', 'dua_khatm_minshawi', 'dua_qunoot_afasy',
    'dua_faraj_sharawi', 'dua_rizq_sharawi',
    'ibtihal_naqshbandi_mawlay', 'ibtihal_tobar_subhan',
  };
  static bool isHeldLegacyAdhkar(IslamicAudioTrack track) =>
      heldLegacyAdhkarIds.contains(track.id);
  /// Unavailable sources retain their IDs and downloaded bytes.
  /// This affects catalog playback and new assignments, not stored alarm times.
  static const unavailableAdhanSourceReasons = <String, String>{
    'adhan_haza_albalushi': 'التسجيل غير متاح حتى مراجعة الاسم والمصدر.',
    'adhan_azhar': 'رابط التسجيل غير متاح حاليا. لم يثبت مصدر بديل مطابق.',
    'adhan_morocco_qarawiyyin': 'رابط التسجيل غير متاح حاليا. لم يثبت مصدر بديل مطابق.',
    'adhan_tunis_zaytouna': 'رابط التسجيل غير متاح حاليا. لم يثبت مصدر بديل مطابق.',
    'adhan_khalil_aqsa': 'رابط التسجيل غير متاح حاليا. لم يثبت مصدر بديل مطابق.',
    'adhan_fatih_istanbul': 'رابط التسجيل غير متاح حاليا. لم يثبت مصدر بديل مطابق.',
    'adhan_alzamil': 'مصدر التسجيل ينسبه إلى اسم مختلف. الاستماع محجوب حتى مراجعة النسبة.',
    'adhan_fares_abbad': 'مصدر التسجيل ينسبه إلى اسم مختلف. الاستماع محجوب حتى مراجعة النسبة.',
    'adhan_sudais': 'مصدر التسجيل ينسبه إلى اسم مختلف. الاستماع محجوب حتى مراجعة النسبة.',
    'adhan_shuraim': 'مصدر التسجيل ينسبه إلى اسم مختلف. الاستماع محجوب حتى مراجعة النسبة.',
    'adhan_bosnia': 'مصدر التسجيل يذكر بلدا مختلفا. الاستماع محجوب حتى مراجعة المصدر.',
  };

  static String? unavailableRecordingReason(String id) {
    final reason = unavailableAdhanSourceReasons[id];
    return reason == null ? null :
        '$reason اختر تسجيلا آخر بنفسك. مواعيد التذكير محفوظة.';
  }

  static bool isHeldRecording(IslamicAudioTrack track) =>
      isHeldLegacyAdhkar(track) || unavailableRecordingReason(track.id) != null;

  IslamicAudioTrack? _heldLegacyTrack;
  IslamicAudioTrack? get heldLegacyTrack => _heldLegacyTrack;
  Future<void>? _legacyStopPending;
  bool _legacyStopFailed = false;
  bool get legacyStopFailed => _legacyStopFailed;
  bool get _needsLegacyContainment => _legacyStopPending != null ||
      (_currentTrack != null && isHeldRecording(_currentTrack!)) ||
      _queue.any(isHeldRecording);

  /// Removes only held items from the ephemeral queue, never stored files.
  /// Stops a previously active held item before a later play can begin.
  Future<void> containLegacyAdhkarPlayback() async {
    final selectedId = _currentTrack?.id ??
        (_currentIndex >= 0 && _currentIndex < _queue.length
            ? _queue[_currentIndex].id : null);
    final priorIndex = _currentIndex;
    final retained = _queue.where((t) => !isHeldRecording(t)).toList();
    final removed = retained.length != _queue.length;
    if (removed) {
      _heldLegacyTrack ??= _queue.firstWhere(isHeldRecording);
      _queue = retained;
      final index = _queue.indexWhere((t) => t.id == selectedId);
      _currentIndex = _queue.isEmpty ? -1 :
          (index >= 0 ? index : priorIndex.clamp(0, _queue.length - 1));
    }
    final heldCurrent = _currentTrack != null && isHeldRecording(_currentTrack!);
    if (heldCurrent) {
      _heldLegacyTrack = _currentTrack;
      _currentTrack = null;
      _isPlaying = false;
      _isBuffering = false;
      _position = Duration.zero;
      _legacyStopPending ??= disableNativePlayerForTesting
          ? Future<void>.value() : _player.stop();
    }
    if (removed || heldCurrent) notifyListeners();
    final pending = _legacyStopPending;
    if (pending != null) {
      try {
        await pending;
        if (identical(_legacyStopPending, pending)) _legacyStopPending = null;
      } catch (_) {
        _legacyStopFailed = true;
        notifyListeners();
      }
    }
  }

  Future<void> retryLegacyPlaybackStop() async {
    if (!_legacyStopFailed) return;
    _legacyStopFailed = false;
    _legacyStopPending = disableNativePlayerForTesting
        ? Future<void>.value() : _player.stop();
    notifyListeners();
    await containLegacyAdhkarPlayback();
    notifyListeners();
  }
  bool get legacyStopPending => _legacyStopPending != null && !_legacyStopFailed;

  @visibleForTesting
  void seedPlaybackSnapshotForTesting({
    required List<IslamicAudioTrack> queue,
    required int currentIndex,
    required bool playing,
  }) {
    if (!disableNativePlayerForTesting) {
      throw StateError('Snapshot seeding requires disabled native playback');
    }
    if (currentIndex < 0 || currentIndex >= queue.length) {
      throw RangeError.index(currentIndex, queue);
    }
    _queue = List.of(queue);
    _currentIndex = currentIndex;
    _currentTrack = _queue[currentIndex];
    _isPlaying = playing;
    _isBuffering = false;
    _heldLegacyTrack = null;
  }

  final AudioPlayer _player;
  final AudioPlayer _sfxPlayer = AudioPlayer();
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 25),
    receiveTimeout: const Duration(minutes: 10),
  ));

  IslamicAudioTrack? _currentTrack;
  bool _isPlaying = false;
  bool _isBuffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  double _playbackSpeed = 1.0;
  bool _isInitialized = false;
  Future<void>? _initializing;
  bool _isOnlinePreview = false;
  int _onlinePreviewSession = 0;
  Future<void>? _pendingNativeStop;
  bool _stopFailed = false;
  bool get stopFailed => _stopFailed;

  // Queue & Playlist Management
  List<IslamicAudioTrack> _queue = [];
  int _currentIndex = -1;
  PlaybackLoopMode _loopMode = PlaybackLoopMode.off;

  /// Test flag to prevent native AudioPlayer platform calls in unit test environments
  bool disableNativePlayerForTesting = false;
  bool _shuffleEnabled = false;

  // Smart Sleep Timer
  Timer? _sleepTimer;
  DateTime? _sleepTimerEndTime;
  int? _sleepTimerMinutes;
  bool _stopAtTrackEnd = false;

  final Map<String, String> _downloadedLocalPaths = {};
  final Map<String, int> _downloadedFileSizes = {};
  final Map<String, String> _retiredRecordingPaths = {};
  final Map<String, int> _retiredRecordingSizes = {};
  final Map<String, double> _activeProgress = {};
  final Map<String, CancelToken> _cancelTokens = {};
  int _downloadAttemptCounter = 0;
  int _storageGeneration = 0;
  final Map<String, FileStat> _validatedFileStats = {};
  String? _storageDirPath;

  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _bufferedPositionSub;

  IslamicAudioTrack? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  Duration get position => _position;
  Duration get duration => _duration;
  Duration get bufferedPosition => _bufferedPosition;
  double get playbackSpeed => _playbackSpeed;
  AudioPlayer get player => _player;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  List<IslamicAudioTrack> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  PlaybackLoopMode get loopMode => _loopMode;
  bool get shuffleEnabled => _shuffleEnabled;
  int? get sleepTimerMinutes => _sleepTimerMinutes;
  bool get hasNext =>
      _queue.isNotEmpty &&
      (_currentIndex < _queue.length - 1 || _loopMode == PlaybackLoopMode.all);
  bool get hasPrevious =>
      _queue.isNotEmpty &&
      (_currentIndex > 0 ||
          _position.inSeconds > 3 ||
          _loopMode == PlaybackLoopMode.all);
  int? get sleepTimerRemainingSeconds {
    if (_sleepTimerEndTime == null) return null;
    final diff = _sleepTimerEndTime!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  /// Immutable source catalog; kept const here for existing callers.
  static const List<IslamicAudioTrack> allTracks = islamicAudioCatalog;

  Future<void> init() async {
    if (_needsLegacyContainment) await containLegacyAdhkarPlayback();
    if (_isInitialized) return;
    return _initializing ??= _initialize().whenComplete(() => _initializing = null);
  }

  Future<void> _initialize() async {
    await _playerStateSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _bufferedPositionSub?.cancel();
    _playerStateSub = _player.playerStateStream.listen((state) {
      _isPlaying = state.playing && state.processingState != ProcessingState.completed;
      _isBuffering = state.processingState == ProcessingState.buffering ||
          state.processingState == ProcessingState.loading;

      if (_currentTrack != null && isHeldRecording(_currentTrack!)) {
        unawaited(containLegacyAdhkarPlayback());
        return;
      }
      if (state.processingState == ProcessingState.completed) {
        if (_isOnlinePreview) {
          _isOnlinePreview = false;
          _position = Duration.zero;
          _isPlaying = false;
          notifyListeners();
          return;
        }
        if (_stopAtTrackEnd) {
          cancelSleepTimer();
          stop();
        } else if (_loopMode == PlaybackLoopMode.single && _currentTrack != null) {
          seek(Duration.zero);
          unawaited(_player.play().catchError((Object error, StackTrace stack) {
            debugPrint('Audio loop replay error: $error');
          }));
        } else if (_queue.isNotEmpty && hasNext) {
          playNext();
        } else if (_loopMode == PlaybackLoopMode.all && _queue.isNotEmpty) {
          _currentIndex = 0;
          playTrack(_queue.first);
        } else {
          final wasAdhan = _currentTrack?.type == IslamicAudioType.adhan;
          _position = Duration.zero;
          _isPlaying = false;
          if (wasAdhan && SettingsService.instance.playSharawiDuaaAfterAdhan) {
            playTrackById('duaa_sharawi_post_prayer');
            return;
          }
        }
      }
      notifyListeners();
    });

    _positionSub = _player.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _durationSub = _player.durationStream.listen((dur) {
      _duration = dur ?? Duration.zero;
      notifyListeners();
    });

    _bufferedPositionSub = _player.bufferedPositionStream.listen((buf) {
      _bufferedPosition = buf;
      notifyListeners();
    });

    try {
      final dir = await _getAudioDirectory();
      _storageDirPath = dir.path;
      await _scanStorageDirectory(dir);
      _isInitialized = true;
    } catch (e) {
      debugPrint('IslamicAudioService init directory error: $e');
    }
  }

  Future<Directory> _getAudioDirectory() async {
    if (kIsWeb) {
      return Directory('/web_adhkar_audio');
    }
    final appDocDir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${appDocDir.path}/adhkar_audio');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    return audioDir;
  }

  @visibleForTesting
  Future<void> scanDownloadsForTesting(Directory dir) => _scanStorageDirectory(dir);

  Future<void> _scanStorageDirectory(Directory dir) async {
    final generation = ++_storageGeneration;
    final paths = <String, String>{};
    final sizes = <String, int>{};
    final retiredPaths = <String, String>{};
    final retiredSizes = <String, int>{};
    final verified = <String, FileStat>{};
    if (await dir.exists()) {
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        if (entity.path.endsWith('.tmp') || entity.path.endsWith('.part')) {
          // A scan must never delete a download that is still in flight.
          if (_cancelTokens.isEmpty) {
            try { entity.deleteSync(); } catch (_) {}
          }
          continue;
        }
        if (!entity.path.endsWith('.mp3')) continue;
        final filename = entity.uri.pathSegments.last;
        final matching = _catalog.where(
            (track) => downloadFileNameForTrack(track.id) == filename);
        try {
          if (matching.isEmpty) {
            final id = filename.substring(0, filename.length - 4);
            if (reviewedAdhanRecordingRevision.containsKey(id)) {
              retiredPaths[id] = entity.path;
              retiredSizes[id] = entity.lengthSync();
            }
          } else {
            final track = matching.first;
            final stat = entity.statSync();
            if (stat.type != FileSystemEntityType.file) continue;
            // Keep invalid pinned files visible to storage accounting and
            // explicit deletion, but never grant offline eligibility.
            if (track.remoteGitBlobSha1 != null || stat.size > 1000) {
              paths[track.id] = entity.path;
              sizes[track.id] = stat.size;
              final checked = await _validateFile(track, entity);
              if (checked != null) verified[track.id] = checked;
            }
          }
        } on FileSystemException {
          // Files can disappear while the directory is being scanned.
        }
      }
    }
    // A concurrent download/deletion or newer scan owns the current state.
    if (generation != _storageGeneration) return;
    _downloadedLocalPaths..clear()..addAll(paths);
    _downloadedFileSizes..clear()..addAll(sizes);
    _retiredRecordingPaths..clear()..addAll(retiredPaths);
    _retiredRecordingSizes..clear()..addAll(retiredSizes);
    _validatedFileStats..clear()..addAll(verified);
    notifyListeners();
  }

  // --- Offline & Download Management ---

  /// A corrected recording must not reuse an old download under the same ID.
  /// Old files remain on disk, but are not treated as the reviewed recording.
  static const reviewedAdhanRecordingRevision = <String, String>{
    'adhan_hussary': '20261121',
    'adhan_menshawi': '20261121',
    'adhan_naqshbandi': '20261121',
    'adhan_alqatami': '20261121',
    'adhan_wadih_alyamani': '20261121',
  };

  static String downloadFileNameForTrack(String id) {
    final revision = reviewedAdhanRecordingRevision[id];
    return revision == null ? '$id.mp3' : '$id.$revision.mp3';
  }

  bool isDownloaded(String id) {
    if (unavailableRecordingReason(id) != null) return false;
    final matches = _catalog.where((track) => track.id == id);
    if (matches.isEmpty) return false;
    final track = matches.first;
    final path = _downloadedLocalPaths[id];
    if (path == null) return false;
    final file = File(path);
    if (file.uri.pathSegments.last != downloadFileNameForTrack(id)) return false;
    try {
      final current = file.statSync();
      _downloadedFileSizes[id] =
          current.type == FileSystemEntityType.file ? current.size : 0;
      if (current.type != FileSystemEntityType.file || current.size <= 1000) {
        _validatedFileStats.remove(id);
        return false;
      }
      if (track.remoteGitBlobSha1 == null) return true;
      final checked = _validatedFileStats[id];
      if (checked != null && sameAudioFileSnapshot(checked, current)) return true;
    } on FileSystemException {
      _downloadedFileSizes[id] = 0;
    }
    _validatedFileStats.remove(id);
    return false;
  }

  String? getLocalAudioPath(String id) =>
      isDownloaded(id) ? _downloadedLocalPaths[id] : null;

  Future<String?> _validatedLocalAudioPath(String id) async {
    final path = getLocalAudioPath(id);
    if (path == null) return null;
    final track = _catalog.firstWhere((track) => track.id == id);
    if (track.remoteGitBlobSha1 == null) return path;
    // Re-hash canonical catalog bytes at playback, not only during the scan.
    final generation = _storageGeneration;
    final checked = await _validateFile(track, File(path));
    if (generation != _storageGeneration) return null;
    var current = false;
    if (checked != null && _downloadedLocalPaths[id] == path) {
      try {
        current = sameAudioFileSnapshot(checked, File(path).statSync());
      } on FileSystemException {
        current = false;
      }
    }
    if (!current) {
      _validatedFileStats.remove(id);
      notifyListeners();
      return null;
    }
    _validatedFileStats[id] = checked!;
    return path;
  }

  @visibleForTesting
  Future<String?> validateLocalAudioPathForTesting(String id) =>
      _validatedLocalAudioPath(id);

  bool isDownloading(String id) => _activeProgress.containsKey(id);

  double getDownloadProgress(String id) => _activeProgress[id] ?? 0.0;

  /// Downloads all remote Adhan tracks for 100% offline playback
  Future<void> downloadAllAdhanTracks({void Function(int completed, int total)? onProgress}) async {
    final adhanList = _catalog
        .where((t) => t.type == IslamicAudioType.adhan && t.assetPath == null && !isDownloaded(t.id))
        .toList();
    int count = 0;
    for (final track in adhanList) {
      await downloadTrack(track.id);
      count++;
      if (onProgress != null) onProgress(count, adhanList.length);
    }
  }

  Future<bool> downloadTrack(String id) async {
    final matching = _catalog.where((track) => track.id == id);
    if (matching.isEmpty) return false;
    final track = matching.first;
    if (isHeldRecording(track) || track.remoteUrl == null || isDownloading(id)) return false;

    await init();
    if (isDownloading(id)) return false;
    final dirPath = _storageDirPath;
    if (dirPath == null) return false;

    final filePath = '$dirPath/${downloadFileNameForTrack(id)}';
    final attempt = ++_downloadAttemptCounter;
    ++_storageGeneration;
    final tempFilePath = '$filePath.$attempt.tmp';

    final cancelToken = CancelToken();
    _cancelTokens[id] = cancelToken;
    _activeProgress[id] = 0.01;
    notifyListeners();

    try {
      final tempFile = File(tempFilePath);
      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }

      int lastEmitMs = 0;

      await _dio.download(
        track.remoteUrl!,
        tempFilePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0 && _cancelTokens[id] == cancelToken && !cancelToken.isCancelled) {
            final now = DateTime.now().millisecondsSinceEpoch;
            final progress = (received / total).clamp(0.0, 1.0);
            _activeProgress[id] = progress;
            if (now - lastEmitMs > 250 || progress >= 1.0) {
              lastEmitMs = now;
              notifyListeners();
            }
          }
        },
      );

      if (_cancelTokens[id] == cancelToken && !cancelToken.isCancelled) {
        final tempFile = File(tempFilePath);
        if (tempFile.existsSync()) {
          try {
            final checked = await _validateFile(track, tempFile);
            if (_cancelTokens[id] != cancelToken || cancelToken.isCancelled) {
              if (tempFile.existsSync()) tempFile.deleteSync();
              return false;
            }
            if (checked == null ||
                !sameAudioFileSnapshot(checked, tempFile.statSync())) {
              throw const FormatException('Downloaded audio failed source validation');
            }
            tempFile.renameSync(filePath);
            _downloadedLocalPaths[id] = filePath;
            _downloadedFileSizes[id] = checked.size;
            _validatedFileStats[id] = File(filePath).statSync();
            ++_storageGeneration;
            _activeProgress.remove(id);
            _cancelTokens.remove(id);
            notifyListeners();
            return true;
          } catch (e) {
            debugPrint('Failed to publish downloaded file for $id: $e');
            try {
              tempFile.deleteSync();
            } catch (_) {}
          }
        }
        if (_cancelTokens[id] == cancelToken) {
          _activeProgress.remove(id);
          _cancelTokens.remove(id);
          notifyListeners();
        }
        return false;
      } else {
        final tempFile = File(tempFilePath);
        if (tempFile.existsSync()) {
          for (int i = 0; i < 5; i++) {
            try {
              tempFile.deleteSync();
              break;
            } catch (_) {
              if (i < 4) {
                await Future<void>.delayed(const Duration(milliseconds: 50));
              }
            }
          }
        }
        return false;
      }
    } catch (e) {
      debugPrint('Adhkar download error for $id: $e');
      if (_cancelTokens[id] == cancelToken) {
        _activeProgress.remove(id);
        _cancelTokens.remove(id);
        notifyListeners();
      }
      final tempFile = File(tempFilePath);
      if (tempFile.existsSync()) {
        for (int i = 0; i < 5; i++) {
          try {
            tempFile.deleteSync();
            break;
          } catch (_) {
            if (i < 4) {
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          }
        }
      }
      return false;
    }
  }

  void cancelDownload(String id) {
    final token = _cancelTokens[id];
    if (token != null && !token.isCancelled) {
      token.cancel('Cancelled by user');
    }
    _activeProgress.remove(id);
    _cancelTokens.remove(id);
    notifyListeners();
  }

  bool _deletionBlockedByAdhanProtection = false;
  bool get deletionBlockedByAdhanProtection =>
      _deletionBlockedByAdhanProtection;
  String? _lastDeletionError;
  String? get lastDeletionError => _lastDeletionError;
  static const _assignedDownloadMessage =
      'احتفظنا بتسجيل أذان معيّن أو قد تستخدمه جدولة سابقة. اختر تسجيلاً آخر وطبّق إعدادات التنبيهات أولاً، ثم أعد الحذف.';
  static const _unverifiedProtectionMessage =
      'تعذر التأكد من تسجيلات الأذان المستخدمة في التنبيهات. احتفظنا بها لتجنب فقد صوت الأذان.';

  Future<bool> deleteDownloadedTrack(String id) async {
    _lastDeletionError = null;
    _deletionBlockedByAdhanProtection = false;
    if (DownloadedAdhanAssignments.isPinnedId(id)) {
      try {
        final protected = await DownloadedAdhanAssignments.protectedIds();
        if (protected.contains(id) ||
            DownloadedAdhanAssignments.isPending(id)) {
          _deletionBlockedByAdhanProtection = true;
          _lastDeletionError = _assignedDownloadMessage;
          return false;
        }
      } catch (_) {
        _deletionBlockedByAdhanProtection = true;
        _lastDeletionError = _unverifiedProtectionMessage;
        return false;
      }
    }
    // No await between this final pending check, cancellation and deletion.
    if (DownloadedAdhanAssignments.isPending(id)) {
      _deletionBlockedByAdhanProtection = true;
      _lastDeletionError = _assignedDownloadMessage;
      return false;
    }
    ++_storageGeneration;
    if (isDownloading(id)) cancelDownload(id);
    final paths = [
      if (_downloadedLocalPaths[id] != null) _downloadedLocalPaths[id]!,
      if (_retiredRecordingPaths[id] != null) _retiredRecordingPaths[id]!,
    ];
    if (paths.isEmpty) return false;
    try {
      for (final path in paths) {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      }
      _validatedFileStats.remove(id);
      _downloadedLocalPaths.remove(id);
      _downloadedFileSizes.remove(id);
      _retiredRecordingPaths.remove(id);
      _retiredRecordingSizes.remove(id);
      notifyListeners();
      return true;
    } catch (e) {
      _lastDeletionError = 'تعذر حذف الملف من مساحة التخزين.';
      debugPrint('Delete track error: $e');
      return false;
    }
  }

  Future<bool> deleteAllDownloadedTracks() async {
    _lastDeletionError = null;
    _deletionBlockedByAdhanProtection = false;
    var protected = <String>{};
    final pinned = {
      ..._downloadedLocalPaths.keys,
      ..._retiredRecordingPaths.keys,
    }.where(DownloadedAdhanAssignments.isPinnedId).toSet();
    if (pinned.isNotEmpty) {
      try {
        protected = await DownloadedAdhanAssignments.protectedIds();
      } catch (_) {
        protected = pinned;
        _deletionBlockedByAdhanProtection = true;
        _lastDeletionError = _unverifiedProtectionMessage;
      }
    }
    ++_storageGeneration;
    for (final id in _cancelTokens.keys.toList()) {
      cancelDownload(id);
    }
    void deleteEntries(Map<String, String> paths, Map<String, int> sizes) {
      for (final entry in paths.entries.toList()) {
        if (protected.contains(entry.key) ||
            DownloadedAdhanAssignments.isPending(entry.key)) {
          _deletionBlockedByAdhanProtection = true;
          _lastDeletionError ??= _assignedDownloadMessage;
          continue;
        }
        try {
          final file = File(entry.value);
          if (file.existsSync()) {
            file.deleteSync();
          }
          _validatedFileStats.remove(entry.key);
          paths.remove(entry.key);
          sizes.remove(entry.key);
        } catch (_) {
          _lastDeletionError ??= 'تعذر حذف بعض الملفات من مساحة التخزين.';
        }
      }
    }

    deleteEntries(_downloadedLocalPaths, _downloadedFileSizes);
    deleteEntries(_retiredRecordingPaths, _retiredRecordingSizes);
    notifyListeners();
    return _downloadedLocalPaths.isEmpty && _retiredRecordingPaths.isEmpty;
  }

  List<IslamicAudioTrack> getDownloadedTracks() {
    return _catalog.where((t) => isDownloaded(t.id)).toList();
  }

  int get unverifiedRecordingCount => _catalog.where((track) =>
      track.remoteGitBlobSha1 != null &&
      unavailableRecordingReason(track.id) == null &&
      _downloadedLocalPaths.containsKey(track.id) &&
      File(_downloadedLocalPaths[track.id]!).existsSync() &&
      !isDownloaded(track.id)).length;

  int get retiredRecordingCount => _retiredRecordingPaths.length;

  int get unavailableRecordingCount => _downloadedLocalPaths.keys
      .where((id) => unavailableRecordingReason(id) != null)
      .length;

  int get totalDownloadedBytes {
    int total = 0;
    for (final size in [..._downloadedFileSizes.values, ..._retiredRecordingSizes.values]) {
      total += size;
    }
    return total;
  }

  String get formattedTotalDownloadedStorage {
    final bytes = totalDownloadedBytes;
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb < 0.1) {
      final kb = bytes / 1024;
      return '${kb.toStringAsFixed(1)} KB';
    }
    if (mb >= 1024) {
      final gb = mb / 1024;
      return '${gb.toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  // --- Playback ---

  Future<void> playTrackById(String trackId) async {
    final normalizedId = trackId == 'adhan_cairo'
        ? 'adhan_cairo_refaat'
        : (trackId == 'iqamah_makkah' ? 'iqamah_full' : trackId);
    final track = _catalog.firstWhere(
      (t) => t.id == normalizedId || t.rawNotificationSound == trackId,
      orElse: () => _catalog.first,
    );
    await playTrack(track);
  }

  /// Preview must stream, even when a bundled or downloaded copy exists.
  /// This never falls back to a local file or silently downloads a preview.
  Future<bool> playOnlinePreview(IslamicAudioTrack track) async {
    if (track.type != IslamicAudioType.adhan && track.type != IslamicAudioType.iqamah) return false;
    if (_needsLegacyContainment) await containLegacyAdhkarPlayback();
    if (_legacyStopFailed || isHeldRecording(track)) return false;
    final url = track.remoteUrl;
    if (url == null || url.isEmpty) return false;
    final session = ++_onlinePreviewSession;
    _isOnlinePreview = true;
    _currentTrack = track;
    _isBuffering = true;
    _isPlaying = false;
    notifyListeners();
    try {
      await init();
      await _pendingNativeStop;
      if (session != _onlinePreviewSession) return false;
      final ok = await FastAudioService.instance.playResilient(
        url,
        player: _player,
        primaryUrl: url,
        fallbackUrls: track.fallbackUrls,
        isLiveStream: true, // bypass both disk cache and background prefetch
        onStopCallback: stop,
      );
      if (session != _onlinePreviewSession) return false;
      _isBuffering = false;
      _isPlaying = ok;
      if (!ok) { _currentTrack = null; _isOnlinePreview = false; }
      notifyListeners();
      return ok;
    } catch (_) {
      if (session == _onlinePreviewSession) {
        _isBuffering = false;
        _isPlaying = false;
        _currentTrack = null;
        _isOnlinePreview = false;
        notifyListeners();
      }
      return false;
    }
  }

  Future<void> playTrack(IslamicAudioTrack track) async {
    if (isHeldRecording(track)) {
      if (_needsLegacyContainment) await containLegacyAdhkarPlayback();
      if (_legacyStopFailed) return;
      _heldLegacyTrack = track;
      notifyListeners();
      return;
    }
    final priorTrack = _currentTrack;
    _isOnlinePreview = false;
    final session = ++_onlinePreviewSession;
    final focus = FastAudioService.instance;
    int? focusToken;
    bool isCurrent() =>
        session == _onlinePreviewSession &&
        (focusToken == null || focusToken == focus.activePlaybackToken);
    void reportPlayFailure(Object error) {
      debugPrint('Error playing ${track.id}: $error');
      _isBuffering = false;
      _isPlaying = _player.playing;
      _currentTrack = _isPlaying ? priorTrack : null;
      notifyListeners();
    }

    // just_audio play completes at playback end, so observe rejection without
    // waiting for completion. An old request cannot alter a newer session/owner.
    void startPlayback() {
      unawaited(_player.play().catchError((Object error, StackTrace stack) {
        if (!isCurrent()) return;
        reportPlayFailure(error);
      }));
    }

    if (_needsLegacyContainment) await containLegacyAdhkarPlayback();
    if (!isCurrent() || _legacyStopFailed) return;
    _heldLegacyTrack = null;
    if (_currentTrack?.id == track.id && _isPlaying) {
      await pause();
      return;
    }

    _currentTrack = track;
    if (!_queue.any((t) => t.id == track.id)) {
      _queue = [track];
      _currentIndex = 0;
    } else {
      _currentIndex = _queue.indexWhere((t) => t.id == track.id);
    }
    _isBuffering = true;
    notifyListeners();

    if (disableNativePlayerForTesting) {
      _isPlaying = true;
      _isBuffering = false;
      notifyListeners();
      return;
    }

    try {
      await init();
      if (!isCurrent()) return;
      await _pendingNativeStop;
      if (!isCurrent()) return;
      focusToken =
          await focus.claimAudioFocus(player: _player, onStopOther: stop);
      if (!isCurrent()) return;
      _stopFailed = false;
      await _player.setVolume(1.0);
      if (!isCurrent()) return;
      // 1. Check if user explicitly downloaded the HD file (offline HD playback)
      final localPath = await _validatedLocalAudioPath(track.id);
      if (!isCurrent()) return;
      if (localPath != null) {
        await _player.setFilePath(localPath);
        if (!isCurrent()) return;
        await _player.setSpeed(_playbackSpeed);
        if (!isCurrent()) return;
        startPlayback();
      }
      // 2. If a Studio HD remote stream exists, try resilient HD streaming & disk caching first,
      //    and fall back to the remastered 44.1kHz Stereo bundled asset if offline!
      else if (track.remoteUrl != null) {
        final cacheKey = 'audio_hd_${track.id}';
        final playback = focus.playResilient(
          track.remoteUrl!,
          player: _player,
          onStopCallback: stop,
          primaryUrl: track.remoteUrl!,
          fallbackUrls: track.fallbackUrls,
          cacheKey: cacheKey,
        );
        // playResilient claims synchronously before its first await.
        focusToken = focus.activePlaybackToken;
        final success = await playback;
        if (!isCurrent()) return;
        if (success) {
          await _player.setSpeed(_playbackSpeed);
          if (!isCurrent()) return;
        } else if (track.assetPath != null) {
          // A false result may mean a failed physical stop, not a network
          // error. Reconfirm silence before any bundled fallback.
          focusToken =
              await focus.claimAudioFocus(player: _player, onStopOther: stop);
          if (!isCurrent()) return;
          if (!kIsWeb && File(track.assetPath!).existsSync()) {
            await _player.setFilePath(track.assetPath!);
          } else {
            await _player.setAsset(track.assetPath!);
          }
          if (!isCurrent()) return;
          await _player.setSpeed(_playbackSpeed);
          if (!isCurrent()) return;
          startPlayback();
        } else {
          throw Exception('Failed to stream audio track ${track.id}');
        }
      }
      // 3. Local bundled 44.1kHz Stereo asset
      else if (track.assetPath != null) {
        if (!kIsWeb && File(track.assetPath!).existsSync()) {
          await _player.setFilePath(track.assetPath!);
        } else {
          await _player.setAsset(track.assetPath!);
        }
        if (!isCurrent()) return;
        await _player.setSpeed(_playbackSpeed);
        if (!isCurrent()) return;
        startPlayback();
      } else {
        throw Exception('No playable audio source found for ${track.id}');
      }
    } catch (e) {
      if (session != _onlinePreviewSession) return;
      reportPlayFailure(e);
    } finally {
      if (session == _onlinePreviewSession && !isCurrent()) {
        _isBuffering = false;
        _isPlaying = _player.playing;
        if (!_isPlaying) _currentTrack = null;
        notifyListeners();
      }
    }
  }

  Future<void> pause() async {
    if (disableNativePlayerForTesting) {
      _isPlaying = false;
      notifyListeners();
      return;
    }
    try {
      await _player.pause();
    } catch (e) {
      debugPrint('Audio pause error: $e');
    }
  }

  Future<void> resume() async {
    if (_needsLegacyContainment) await containLegacyAdhkarPlayback();
    if (_legacyStopFailed || _currentTrack == null) return;
    if (disableNativePlayerForTesting) {
      _isPlaying = true;
      notifyListeners();
      return;
    }
    final session = _onlinePreviewSession;
    final track = _currentTrack;
    try {
      await _pendingNativeStop;
      if (session != _onlinePreviewSession || track != _currentTrack) return;
      final focus = FastAudioService.instance;
      final token =
          await focus.claimAudioFocus(player: _player, onStopOther: stop);
      if (session != _onlinePreviewSession ||
          track != _currentTrack ||
          token != focus.activePlaybackToken) return;
      unawaited(_player.play().catchError((Object error, StackTrace stack) {
        debugPrint('Audio resume error: $error');
      }));
    } catch (error) {
      debugPrint('Audio resume error: $error');
    }
  }

  Future<void> stop() async {
    final session = ++_onlinePreviewSession;
    FastAudioService.instance.releaseAudioFocusFor(_player);
    _isOnlinePreview = false;
    _isBuffering = false;
    _stopFailed = false;
    if (disableNativePlayerForTesting) {
      _isPlaying = false;
      _currentTrack = null;
      _position = Duration.zero;
      notifyListeners();
      return;
    }
    final priorStop = _pendingNativeStop;
    final stopping = () async {
      await priorStop;
      await _player.stop();
      if (_player.playing) throw StateError('Audio stop was not confirmed');
    }();
    // New starts wait for this native stop, including a stop which ultimately
    // fails. Focus admission then checks the physical owner again.
    _pendingNativeStop = stopping.catchError((Object _) {});
    try {
      await stopping;
    } catch (error) {
      if (session != _onlinePreviewSession) return;
      _stopFailed = true;
      _isPlaying = _player.playing;
      notifyListeners();
      debugPrint('Audio stop error: $error');
      return;
    }
    if (session != _onlinePreviewSession) return;
    _isPlaying = false;
    _currentTrack = null;
    _position = Duration.zero;
    notifyListeners();
  }

  Future<void> seek(Duration newPosition) async {
    try {
      await _player.seek(newPosition);
    } catch (e) {
      debugPrint('Audio seek error: $e');
    }
  }

  Future<void> seekForward({int seconds = 10}) async {
    final target = _position + Duration(seconds: seconds);
    await seek(target > _duration ? _duration : target);
  }

  Future<void> seekBackward({int seconds = 10}) async {
    final target = _position - Duration(seconds: seconds);
    await seek(target < Duration.zero ? Duration.zero : target);
  }

  Future<void> playQueue(List<IslamicAudioTrack> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    final selected = tracks[startIndex.clamp(0, tracks.length - 1)];
    _queue = List.from(tracks);
    _currentIndex = startIndex.clamp(0, _queue.length - 1);
    if (_needsLegacyContainment) await containLegacyAdhkarPlayback();
    if (_queue.isEmpty) return;
    if (isHeldRecording(selected)) {
      _heldLegacyTrack = selected;
      notifyListeners();
      return;
    }
    _currentIndex = _queue.indexWhere((t) => t.id == selected.id);
    await playTrack(selected);
  }

  Future<void> playNext() async {
    final hadHeldCurrent = _currentTrack != null && isHeldRecording(_currentTrack!);
    final remainingAfter = _currentIndex >= 0 && _currentIndex < _queue.length
        ? _queue.skip(_currentIndex + 1).where((t) => !isHeldRecording(t)).toList() : <IslamicAudioTrack>[];
    if (_needsLegacyContainment) await containLegacyAdhkarPlayback();
    if (hadHeldCurrent && remainingAfter.isNotEmpty) {
      await playTrack(remainingAfter.first);
      return;
    }
    if (_queue.isEmpty) return;
    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      await playTrack(_queue[_currentIndex]);
    } else if (_loopMode == PlaybackLoopMode.all) {
      _currentIndex = 0;
      await playTrack(_queue[_currentIndex]);
    }
  }

  Future<void> playPrevious() async {
    final hadHeldCurrent = _currentTrack != null && isHeldRecording(_currentTrack!);
    final remainingBefore = _currentIndex > 0 && _currentIndex <= _queue.length
        ? _queue.take(_currentIndex).where((t) => !isHeldRecording(t)).toList() : <IslamicAudioTrack>[];
    if (_needsLegacyContainment) await containLegacyAdhkarPlayback();
    if (hadHeldCurrent && remainingBefore.isNotEmpty) {
      await playTrack(remainingBefore.last);
      return;
    }
    if (_queue.isEmpty) return;
    if (_position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    if (_currentIndex > 0) {
      _currentIndex--;
      await playTrack(_queue[_currentIndex]);
    } else if (_loopMode == PlaybackLoopMode.all) {
      _currentIndex = _queue.length - 1;
      await playTrack(_queue[_currentIndex]);
    }
  }

  void toggleLoopMode() {
    switch (_loopMode) {
      case PlaybackLoopMode.off:
        _loopMode = PlaybackLoopMode.all;
        break;
      case PlaybackLoopMode.all:
        _loopMode = PlaybackLoopMode.single;
        break;
      case PlaybackLoopMode.single:
        _loopMode = PlaybackLoopMode.off;
        break;
    }
    notifyListeners();
  }

  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    notifyListeners();
  }

  void setSleepTimer(int minutes, {bool stopAtTrackEnd = false}) {
    _sleepTimer?.cancel();
    _sleepTimerMinutes = minutes;
    _stopAtTrackEnd = stopAtTrackEnd;
    _sleepTimerEndTime = DateTime.now().add(Duration(minutes: minutes));

    _sleepTimer = Timer(Duration(minutes: minutes), () {
      stop();
      _sleepTimer = null;
      _sleepTimerEndTime = null;
      _sleepTimerMinutes = null;
      _stopAtTrackEnd = false;
      notifyListeners();
    });
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEndTime = null;
    _sleepTimerMinutes = null;
    _stopAtTrackEnd = false;
    notifyListeners();
  }

  Future<void> playSurahTrack({
    required int surahId,
    required String surahName,
    required String reciterId,
    required String reciterName,
    required String url,
    String? localPath,
  }) async {
    final track = IslamicAudioTrack(
      id: 'quran_${reciterId}_$surahId',
      title: 'سورة $surahName',
      subtitle: 'بصوت القارئ $reciterName',
      type: IslamicAudioType.quran,
      remoteUrl: url,
      assetPath: localPath,
      durationFormatted: 'تلاوة كاملة',
      quality: 'مرتل عالي النقاء 192kbps',
      categoryAr: 'القرآن الكريم',
      surahNumber: surahId,
      reciterId: reciterId,
    );
    await playTrack(track);
  }

  Future<void> playStoryTrack({
    required String id,
    required String title,
    required String scholarName,
    required String url,
    String? localPath,
  }) async {
    final track = IslamicAudioTrack(
      id: id,
      title: title,
      subtitle: scholarName,
      type: IslamicAudioType.story,
      remoteUrl: url,
      assetPath: localPath,
      durationFormatted: 'حلقة كاملة',
      quality: 'عالي النقاء HD',
      categoryAr: 'قصص ودروس',
    );
    await playTrack(track);
  }

  Future<void> playCustomTrack(IslamicAudioTrack track) async {
    await playTrack(track);
  }

  /// Plays a queue of scholar lessons starting at [initialTrack]
  Future<void> playLessonQueue({
    required List<IslamicAudioTrack> tracks,
    required IslamicAudioTrack initialTrack,
  }) async {
    if (tracks.isEmpty) {
      await playTrack(initialTrack);
      return;
    }
    final idx = tracks.indexWhere((t) => t.id == initialTrack.id);
    await playQueue(tracks, startIndex: idx >= 0 ? idx : 0);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    await _player.setSpeed(speed);
    notifyListeners();
  }

  Future<void> playTasbihClick() async {
    try {
      await _sfxPlayer.setAsset('assets/audio/tasbih_click.mp3');
      await _sfxPlayer.play();
    } catch (_) {}
  }

  Future<void> playTakbeeratShort() async {
    try {
      await _sfxPlayer.setAsset('assets/audio/takbeerat.mp3');
      await _sfxPlayer.play();
    } catch (_) {}
  }

  /// Plays authentic approaching prayer voice alert ("اقتربت صلاة كذا.. يرجى الاستعداد والتطهر")
  Future<void> playApproachingPrayerAudio(String prayerName) async {
    String assetName = 'approaching_dhuhr';
    if (prayerName.contains('فجر') || prayerName.contains('الفجر')) {
      assetName = 'approaching_fajr';
    } else if (prayerName.contains('عصر') || prayerName.contains('العصر')) {
      assetName = 'approaching_asr';
    } else if (prayerName.contains('مغرب') || prayerName.contains('المغرب')) {
      assetName = 'approaching_maghrib';
    } else if (prayerName.contains('عشاء') || prayerName.contains('العشاء')) {
      assetName = 'approaching_isha';
    }

    try {
      await _sfxPlayer.stop();
      await _sfxPlayer.setAsset('assets/audio/$assetName.mp3');
      await _sfxPlayer.play();
    } catch (_) {}
  }

  /// Plays authentic reminder audio (qiyam, duha, sunrise, salawat, istighfar, iqamah)
  Future<void> playReminderAudio(String reminderKey) async {
    String assetName = 'reminder_$reminderKey';
    if (reminderKey == 'iqamah') {
      assetName = 'iqamah';
    }
    try {
      await _sfxPlayer.stop();
      await _sfxPlayer.setAsset('assets/audio/$assetName.mp3');
      await _sfxPlayer.play();
    } catch (_) {}
  }

  Future<void> stopSfx() async {
    try {
      await _sfxPlayer.stop();
    } catch (_) {}
  }

  List<IslamicAudioTrack> getTracksByType(IslamicAudioType type) {
    return _catalog.where((t) => t.type == type).toList();
  }

  @override
  void dispose() {
    _onlinePreviewSession++;
    ++_storageGeneration;
    for (final token in _cancelTokens.values) {
      token.cancel('Audio service disposed');
    }
    _cancelTokens.clear();
    _activeProgress.clear();
    FastAudioService.instance.releaseAudioFocusFor(_player);
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferedPositionSub?.cancel();
    _player.dispose();
    _sfxPlayer.dispose();
    super.dispose();
  }
}
