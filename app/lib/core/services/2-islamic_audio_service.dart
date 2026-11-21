import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../audio/fast_audio_service.dart';
import 'settings_service.dart';

enum IslamicAudioType {
  adhan,
  iqamah,
  adhkar,
  tasbih,
  quran,
  story,
  lesson,
}

enum PlaybackLoopMode {
  off,
  all,
  single,
}

enum AudioClarityPreset {
  studioHd('studio_hd', 'استوديو فائق النقاء (HD Master)', 1.0),
  mosqueEcho('mosque_echo', 'رحاب الحرم والمسجد (خاشع)', 1.0),
  warmVoice('warm_voice', 'صوت دافئ رخيم (للقراء والابتهالات)', 1.0),
  clearSpeech('clear_speech', 'تعزيز وضوح الصوت (للدروس والأدعية)', 1.0);

  final String id;
  final String labelAr;
  final double volumeGain;
  const AudioClarityPreset(this.id, this.labelAr, this.volumeGain);

  static AudioClarityPreset fromId(String id) {
    return AudioClarityPreset.values.firstWhere(
      (e) => e.id == id,
      orElse: () => AudioClarityPreset.studioHd,
    );
  }
}

class IslamicAudioTrack {
  final String id;
  final String title;
  final String subtitle;
  final IslamicAudioType type;
  final String? assetPath;
  final String? remoteUrl;
  final List<String> fallbackUrls;
  final String durationFormatted;
  final String? rawNotificationSound;
  final String quality;
  final int? fileSizeBytes;
  final String? categoryAr;
  final String? muezzinName;
  final String? imageUrl;
  final int? surahNumber;
  final String? reciterId;

  const IslamicAudioTrack({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    this.assetPath,
    this.remoteUrl,
    this.fallbackUrls = const [],
    required this.durationFormatted,
    this.rawNotificationSound,
    this.quality = 'عالي النقاء HD',
    this.fileSizeBytes,
    this.categoryAr,
    this.muezzinName,
    this.imageUrl,
    this.surahNumber,
    this.reciterId,
  });

  bool get isBundled => assetPath != null;
}

class IslamicAudioService extends ChangeNotifier {
  static final IslamicAudioService instance = IslamicAudioService._internal();
  IslamicAudioService._internal() : _player = AudioPlayer();
  @visibleForTesting
  IslamicAudioService.forTesting(AudioPlayer player) : _player = player;

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
  /// A stored ID is retained while its recording is unavailable.
  static String? unavailableRecordingReason(String id) =>
      id == 'adhan_haza_albalushi'
          ? 'التسجيل غير متاح حتى مراجعة الاسم والمصدر. اختر تسجيلا آخر بنفسك. مواعيد التذكير محفوظة.'
          : null;

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
  bool _isOnlinePreview = false;
  int _onlinePreviewSession = 0;

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

  static const List<IslamicAudioTrack> allTracks = [
    // 1. نغمات الأذان (أصوات الحرمين ومصر والعالم الإسلامي)
    IslamicAudioTrack(
      id: 'adhan_makkah',
      title: 'أذان المسجد الحرام (مكة المكرمة)',
      subtitle: 'بصوت شيخ مؤذني الحرم المكي علي بن أحمد ملا',
      type: IslamicAudioType.adhan,
      assetPath: 'assets/audio/adhan_makkah.mp3',
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/003.mp3',
      fallbackUrls: ['https://archive.org/download/Athan_Mawsoa_mp3/008.mp3'],
      rawNotificationSound: 'adhan_makkah',
      durationFormatted: '03:10',
      quality: 'استوديو نقي 192kbps',
      categoryAr: 'أذان الحرمين',
      muezzinName: 'الشيخ علي ملا',
      fileSizeBytes: 1227822,
    ),
    IslamicAudioTrack(
      id: 'adhan_madinah',
      title: 'أذان المسجد النبوي الشريف (المدينة المنورة)',
      subtitle: 'أذان هادئ وخاشع من رحاب المسجد النبوي الشريف',
      type: IslamicAudioType.adhan,
      assetPath: 'assets/audio/adhan_madinah.mp3',
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/013.mp3',
      fallbackUrls: ['https://archive.org/download/Athan_Mawsoa_mp3/014.mp3'],
      rawNotificationSound: 'adhan_madinah',
      durationFormatted: '03:40',
      quality: 'استوديو نقي 192kbps',
      categoryAr: 'أذان الحرمين',
      muezzinName: 'مؤذن المسجد النبوي',
      fileSizeBytes: 1650401,
    ),
    IslamicAudioTrack(
      id: 'adhan_aqsa',
      title: 'أذان المسجد الأقصى المبارك (القدس الشريف)',
      subtitle: 'نداء الصلاة الخالد من مسرى رسول الله ﷺ',
      type: IslamicAudioType.adhan,
      assetPath: 'assets/audio/adhan_aqsa.mp3',
      rawNotificationSound: 'adhan_aqsa',
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/015.mp3',
      fallbackUrls: ['https://archive.org/download/Athan_Mawsoa_mp3/044-1.mp3'],
      durationFormatted: '02:40',
      quality: 'عالي النقاء HD',
      categoryAr: 'القدس الشريف',
      muezzinName: 'مؤذن المسجد الأقصى',
      fileSizeBytes: 1061782,
    ),
    IslamicAudioTrack(
      id: 'adhan_cairo_refaat',
      title: 'أذان القاهرة ومصر (الشيخ محمد رفعت)',
      subtitle: 'الصوت الخالد لجامع الأزهر وإذاعة القرآن الكريم بمصر',
      type: IslamicAudioType.adhan,
      assetPath: 'assets/audio/adhan_cairo_refaat.mp3',
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/021.mp3',
      fallbackUrls: ['https://archive.org/download/Athan_Mawsoa_mp3/022.mp3'],
      rawNotificationSound: 'adhan_cairo',
      durationFormatted: '03:30',
      quality: 'تسجيل نادر نقي',
      categoryAr: 'أذان مصر',
      muezzinName: 'الشيخ محمد رفعت',
      fileSizeBytes: 1426218,
    ),
    IslamicAudioTrack(
      id: 'adhan_hussary',
      title: 'أذان الشيخ محمود خليل الحصري',
      subtitle: 'أذان القاهرة، من أرشيف إسلام ويب',
      type: IslamicAudioType.adhan,
      assetPath: 'assets/audio/adhan_hussary.mp3',
      rawNotificationSound: 'adhan_hussary',
      remoteUrl: 'https://dl2.islamweb.net/Audio3/Adan/1030.mp3',
      fallbackUrls: [],
      durationFormatted: '02:08',
      quality: 'تسجيل تاريخي، MP3 16 كيلوبت/ث',
      categoryAr: 'أذان مصر',
      muezzinName: 'الشيخ محمود خليل الحصري',
      fileSizeBytes: 256128,
    ),
    IslamicAudioTrack(
      id: 'adhan_abdulbasit',
      title: 'أذان الشيخ عبد الباسط عبد الصمد',
      subtitle: 'نداء السماء الخاشع بنبرة صوت تلامس القلوب',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/153-4.mp3',
      fallbackUrls: ['https://archive.org/download/Athan_Mawsoa_mp3/025.mp3'],
      durationFormatted: '03:21',
      quality: 'عالي النقاء HD 192kbps',
      categoryAr: 'أذان مصر',
      muezzinName: 'الشيخ عبد الباسط عبد الصمد',
      fileSizeBytes: 403584,
    ),
    IslamicAudioTrack(
      id: 'adhan_afasy',
      title: 'أذان الشيخ مشاري بن راشد العفاسي',
      subtitle: 'الأداء العذب المميز لنداء الصلاة بدولة الكويت',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/050-1.mp3',
      fallbackUrls: ['https://archive.org/download/Athan_Mawsoa_mp3/052-1.mp3'],
      durationFormatted: '04:00',
      quality: 'استوديو نقي 192kbps',
      categoryAr: 'أذان الخليج والشام',
      muezzinName: 'الشيخ مشاري العفاسي',
      fileSizeBytes: 3850000,
    ),
    IslamicAudioTrack(
      id: 'adhan_fajr',
      title: 'أذان الفجر (الصلاة خير من النوم - مكة)',
      subtitle: 'أذان الفجر المبارك من رحاب الحرم المكي الشريف',
      type: IslamicAudioType.adhan,
      assetPath: 'assets/audio/adhan_fajr.mp3',
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/004.mp3',
      fallbackUrls: ['https://archive.org/download/Athan_Mawsoa_mp3/014.mp3'],
      rawNotificationSound: 'adhan_fajr',
      durationFormatted: '03:50',
      quality: 'عالي النقاء HD',
      categoryAr: 'أذان الفجر',
      muezzinName: 'مؤذن الحرم المكي',
      fileSizeBytes: 1560985,
    ),
    IslamicAudioTrack(
      id: 'adhan_fajr_afasy',
      title: 'أذان الفجر — الشيخ مشاري العفاسي',
      subtitle: 'أذان فجر خاشع مع ترديد «الصلاة خير من النوم»',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/052-1.mp3',
      durationFormatted: '03:07',
      quality: 'عالي النقاء HD 192kbps',
      categoryAr: 'أذان الفجر',
      muezzinName: 'الشيخ مشاري العفاسي',
      fileSizeBytes: 2990000,
    ),
    IslamicAudioTrack(
      id: 'adhan_fajr_madinah',
      title: 'أذان الفجر من المسجد النبوي الشريف',
      subtitle: 'نفحات الفجر والسكينة في مدينة المصطفى ﷺ',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/014.mp3',
      durationFormatted: '04:39',
      quality: 'عالي النقاء HD',
      categoryAr: 'أذان الفجر',
      muezzinName: 'مؤذن المسجد النبوي',
      fileSizeBytes: 4460000,
    ),
    IslamicAudioTrack(
      id: 'adhan_fajr_aqsa',
      title: 'أذان الفجر من المسجد الأقصى المبارك',
      subtitle: 'فجر بيت المقدس وأكناف بيت المقدس الطاهرة',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/015.mp3',
      durationFormatted: '02:32',
      quality: 'عالي النقاء HD',
      categoryAr: 'أذان الفجر',
      muezzinName: 'مؤذن المسجد الأقصى',
      fileSizeBytes: 2440000,
    ),
    IslamicAudioTrack(
      id: 'adhan_shoaisha',
      title: 'أذان الشيخ أبو العينين شعيشع',
      subtitle: 'الصوت الرخيم الأصيل بالمقامات الشرقية الخاشعة',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/023.mp3',
      durationFormatted: '03:56',
      quality: 'تسجيل تاريخي نقي',
      categoryAr: 'أذان مصر',
      muezzinName: 'الشيخ أبو العينين شعيشع',
      fileSizeBytes: 3780000,
    ),
    IslamicAudioTrack(
      id: 'adhan_naina',
      title: 'أذان الدكتور أحمد نعينع',
      subtitle: 'أذان وقور ورقيق بصوت قارئ الملوك والأزهر',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/024.mp3',
      durationFormatted: '03:31',
      quality: 'عالي النقاء HD',
      categoryAr: 'أذان مصر',
      muezzinName: 'الدكتور أحمد نعينع',
      fileSizeBytes: 3370000,
    ),
    IslamicAudioTrack(
      id: 'adhan_banna',
      title: 'أذان الشيخ محمود علي البنا',
      subtitle: 'نداء الفلاح بخشوع وإتقان وتواضع رباني',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/027.mp3',
      fallbackUrls: [],
      durationFormatted: '02:46',
      quality: 'تسجيل عريق نقي',
      categoryAr: 'أذان مصر',
      muezzinName: 'الشيخ محمود علي البنا',
      fileSizeBytes: 2660000,
    ),
    IslamicAudioTrack(
      id: 'adhan_turkey',
      title: 'أذان مساجد إسطنبول وتركيا',
      subtitle: 'النمط العثماني المهيب بمقام الرست والصباح',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/006.mp3',
      durationFormatted: '02:59',
      quality: 'عالي النقاء HD',
      categoryAr: 'العالم الإسلامي',
      muezzinName: 'مؤذن جامع السلطان أحمد',
      fileSizeBytes: 2860000,
    ),
    IslamicAudioTrack(
      id: 'adhan_dubai',
      title: 'أذان دبي والإمارات العربية المتحدة',
      subtitle: 'نداء نقي من رحاب مساجد دبي الكبرى',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/011.mp3',
      durationFormatted: '03:56',
      quality: 'استوديو نقي 192kbps',
      categoryAr: 'أذان الخليج والشام',
      muezzinName: 'مؤذن جامع دبي الكبير',
      fileSizeBytes: 3780000,
    ),
    IslamicAudioTrack(
      id: 'adhan_sham',
      title: 'أذان الجامع الأموي الكبير (دمشق الشام)',
      subtitle: 'الأذان الجماعي الدمشقي العريق ونفحات الشام المباركة',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/020.mp3',
      durationFormatted: '03:42',
      quality: 'عالي النقاء HD',
      categoryAr: 'أذان الخليج والشام',
      muezzinName: 'مؤذنو الجامع الأموي',
      fileSizeBytes: 3550000,
    ),
    IslamicAudioTrack(
      id: 'adhan_algeria',
      title: 'أذان الجزائر والمغرب العربي',
      subtitle: 'الأداء المغاربي الأصيل بمسجد الجزائر الأعظم',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/018.mp3',
      durationFormatted: '02:58',
      quality: 'عالي النقاء HD',
      categoryAr: 'العالم الإسلامي',
      muezzinName: 'مؤذن جامع الجزائر',
      fileSizeBytes: 2840000,
    ),
    IslamicAudioTrack(
      id: 'adhan_alqatami',
      title: 'أذان الشيخ ناصر القطامي',
      subtitle: 'أذان بصوت الشيخ ناصر القطامي، من مكتبة إسلام ويب',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://dl2.islamweb.net/Audio3/Adan/317311.mp3',
      fallbackUrls: [],
      durationFormatted: '02:16',
      quality: 'MP3 128 كيلوبت/ث',
      categoryAr: 'أذان الخليج والشام',
      muezzinName: 'الشيخ ناصر القطامي',
      fileSizeBytes: 2241376,
    ),
    IslamicAudioTrack(
      id: 'adhan_aldosari',
      title: 'أذان الشيخ ياسر الدوسري',
      subtitle: 'أداء حجازي مؤثر وصدح خاشع بالحق من الحرم المكي',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/084-3.mp3',
      fallbackUrls: [],
      durationFormatted: '03:30',
      quality: 'عالي النقاء HD 192kbps',
      categoryAr: 'أذان الحرمين',
      muezzinName: 'الشيخ ياسر الدوسري',
      fileSizeBytes: 3360000,
    ),
    IslamicAudioTrack(
      id: 'adhan_albani',
      title: 'أذان الشيخ العلامة محمد ناصر الدين الألباني',
      subtitle: 'تسجيل نادر بصوت محدث العصر وإمام السنة رحمه الله',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/083-3.mp3',
      fallbackUrls: [],
      durationFormatted: '03:15',
      quality: 'تسجيل نادر نقي',
      categoryAr: 'أذان الخليج والشام',
      muezzinName: 'الشيخ محمد ناصر الدين الألباني',
      fileSizeBytes: 3120000,
    ),
    IslamicAudioTrack(
      id: 'adhan_trabelsi',
      title: 'أذان القارئ أحمد الطرابلسي',
      subtitle: 'أداء متقن متزن لنداء الحق بصوت قارئ الكويت الشهير',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/104-4.mp3',
      fallbackUrls: ['https://archive.org/download/Athan_Mawsoa_mp3/109-4.mp3'],
      durationFormatted: '03:32',
      quality: 'استوديو نقي 192kbps',
      categoryAr: 'أذان الخليج والشام',
      muezzinName: 'القارئ أحمد الطرابلسي',
      fileSizeBytes: 3390000,
    ),
    IslamicAudioTrack(
      id: 'adhan_fajr_trabelsi',
      title: 'أذان الفجر — القارئ أحمد الطرابلسي',
      subtitle: 'أذان الفجر والسكينة مع نداء «الصلاة خير من النوم»',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/107-4.mp3',
      fallbackUrls: [],
      durationFormatted: '03:40',
      quality: 'عالي النقاء HD',
      categoryAr: 'أذان الفجر',
      muezzinName: 'القارئ أحمد الطرابلسي',
      fileSizeBytes: 3520000,
    ),
    IslamicAudioTrack(
      id: 'adhan_alzamil',
      title: 'أذان الشيخ ماجد الزامل',
      subtitle: 'نبرة صوت ندية رقيقة مفعمة بالسكينة والخشوع الرباني',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/048-1.mp3',
      fallbackUrls: [],
      durationFormatted: '03:38',
      quality: 'استوديو عالي النقاء HD',
      categoryAr: 'أذان الخليج والشام',
      muezzinName: 'الشيخ ماجد الزامل',
      fileSizeBytes: 3500000,
    ),
    IslamicAudioTrack(
      id: 'adhan_mansoor_alsalimi',
      title: 'أذان الشيخ منصور السالمي',
      subtitle: 'نداء مؤثر وخشوع يهز القلوب ويجدد عهد الإيمان',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/MansoorAlsalmi/000%20-%201435H.mp3',
      fallbackUrls: [],
      durationFormatted: '03:12',
      quality: 'عالي النقاء 320kbps',
      categoryAr: 'أذان الخليج والشام',
      muezzinName: 'الشيخ منصور السالمي',
      fileSizeBytes: 3100000,
    ),
    IslamicAudioTrack(
      id: 'adhan_essam_bukhari',
      title: 'أذان الشيخ عصام بخاري (المسجد النبوي)',
      subtitle: 'الصوت المدني الرصين من محراب الحبيب المصطفى ﷺ',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/013.mp3',
      fallbackUrls: [],
      durationFormatted: '03:52',
      quality: 'استوديو نقي 192kbps',
      categoryAr: 'أذان الحرمين',
      muezzinName: 'الشيخ عصام بخاري',
      fileSizeBytes: 3720000,
    ),
    IslamicAudioTrack(
      id: 'adhan_farooq_hadrawi',
      title: 'أذان الشيخ فاروق عبد الرحمن حضراوي',
      subtitle: 'مؤذن المسجد الحرام — أداء مكي جهوري بمقام الرست',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/athan2_202301/athan2.mp3',
      fallbackUrls: [],
      durationFormatted: '03:25',
      quality: 'عالي النقاء HD',
      categoryAr: 'أذان الحرمين',
      muezzinName: 'الشيخ فاروق حضراوي',
      fileSizeBytes: 3300000,
    ),
    IslamicAudioTrack(
      id: 'adhan_naif_feeda',
      title: 'أذان الشيخ نايف صالح فيده',
      subtitle: 'شيخ مؤذني المسجد الحرام بمكة المكرمة والأداء التراثي',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/008.mp3',
      fallbackUrls: [],
      durationFormatted: '03:18',
      quality: 'تسجيل رسمي نقي',
      categoryAr: 'أذان الحرمين',
      muezzinName: 'الشيخ نايف فيده',
      fileSizeBytes: 3200000,
    ),
    IslamicAudioTrack(
      id: 'adhan_mustafa_ismail',
      title: 'أذان الشيخ مصطفى إسماعيل',
      subtitle: 'تسجيل تاريخي نادر لقارئ الأزهر بمقام الصبا والبيات',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/148.mp3',
      fallbackUrls: [],
      durationFormatted: '03:44',
      quality: 'تسجيل تاريخي منقى',
      categoryAr: 'أذان مصر',
      muezzinName: 'الشيخ مصطفى إسماعيل',
      fileSizeBytes: 3590000,
    ),
    IslamicAudioTrack(
      id: 'adhan_omran',
      title: 'أذان الشيخ محمد عمران',
      subtitle: 'سلطان المقامات والابتهالات بنفحات مصرية أصيلة بمقام البيات',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/022.mp3',
      fallbackUrls: [],
      durationFormatted: '04:10',
      quality: 'تسجيل استوديو نقي',
      categoryAr: 'أذان مصر',
      muezzinName: 'الشيخ محمد عمران',
      fileSizeBytes: 4000000,
    ),
    IslamicAudioTrack(
      id: 'adhan_islam_sobhi',
      title: 'أذان القارئ إسلام صبحي',
      subtitle: 'نداء هادئ ومريح يبعث السكينة والطمأنينة في النفس',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/A.S.I.S/Adhan_Sheikh-Islam-Sobhi.mp3',
      fallbackUrls: [],
      durationFormatted: '02:55',
      quality: 'استوديو نقي 320kbps',
      categoryAr: 'العالم الإسلامي',
      muezzinName: 'القارئ إسلام صبحي',
      fileSizeBytes: 2800000,
    ),
    IslamicAudioTrack(
      id: 'adhan_amr_sobhi',
      title: 'أذان الشيخ عمرو صبحي',
      subtitle: 'تسجيل أذان من مكتبة إسلام ويب',
      type: IslamicAudioType.adhan,
      remoteUrl: 'https://dl2.islamweb.net/Audio3//Adan/428132.mp3',
      durationFormatted: '03:27',
      quality: 'MP3 128 كيلوبت/ث، أحادي',
      categoryAr: 'العالم الإسلامي',
      muezzinName: 'الشيخ عمرو صبحي',
      fileSizeBytes: 3379378,
    ),
    IslamicAudioTrack(
      id: 'adhan_wadih_alyamani',
      title: 'أذان الشيخ وديع اليمني',
      subtitle: 'أذان وديع حمادي اليمني، من مكتبة إسلام ويب',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://dl2.islamweb.net/Audio3/Adan/425434.mp3',
      fallbackUrls: [],
      durationFormatted: '03:20',
      quality: 'MP3 128 كيلوبت/ث',
      categoryAr: 'العالم الإسلامي',
      muezzinName: 'الشيخ وديع اليمني',
      fileSizeBytes: 3270708,
    ),
    IslamicAudioTrack(
      id: 'adhan_idrees_abkar',
      title: 'أذان الشيخ إدريس أبكر',
      subtitle: 'صوت خاشع ومؤثر يذكر بلقاء الله والوقوف بين يديه',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/034.mp3',
      fallbackUrls: [],
      durationFormatted: '03:35',
      quality: 'عالي النقاء HD',
      categoryAr: 'أذان الخليج والشام',
      muezzinName: 'الشيخ إدريس أبكر',
      fileSizeBytes: 3450000,
    ),
    IslamicAudioTrack(
      id: 'adhan_tunisia',
      title: 'أذان جامع الزيتونة المعمور (تونس)',
      subtitle: 'الأداء الأندلسي المغاربي التاريخي برحاب جامع الزيتونة',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/035.mp3',
      fallbackUrls: [],
      durationFormatted: '03:05',
      quality: 'تسجيل تاريخي عريق',
      categoryAr: 'العالم الإسلامي',
      muezzinName: 'مؤذن جامع الزيتونة',
      fileSizeBytes: 2950000,
    ),
    IslamicAudioTrack(
      id: 'adhan_bosnia',
      title: 'أذان سراييفو والبوسنة والهرسك',
      subtitle: 'أذان جامع الغازي خسرو بك — شجن البلقان والنمط العثماني',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/007.mp3',
      fallbackUrls: [],
      durationFormatted: '02:48',
      quality: 'عالي النقاء HD',
      categoryAr: 'العالم الإسلامي',
      muezzinName: 'مؤذن سراييفو',
      fileSizeBytes: 2680000,
    ),
    IslamicAudioTrack(
      id: 'adhan_fajr_abdulbasit',
      title: 'أذان الفجر — الشيخ عبد الباسط عبد الصمد',
      subtitle: 'نداء «الصلاة خير من النوم» بالصوت الذهبي الخالد',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/153-4.mp3',
      fallbackUrls: ['https://archive.org/download/Athan_Mawsoa_mp3/154-4.mp3'],
      durationFormatted: '04:15',
      quality: 'استوديو نقي 192kbps',
      categoryAr: 'أذان الفجر',
      muezzinName: 'الشيخ عبد الباسط عبد الصمد',
      fileSizeBytes: 4080000,
    ),
    IslamicAudioTrack(
      id: 'adhan_fajr_alqatami',
      title: 'أذان الفجر — الشيخ ناصر القطامي',
      subtitle: 'أذان الفجر والسكينة مع نداء الحق للشيخ ناصر القطامي',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/120-4.mp3',
      fallbackUrls: ['https://archive.org/download/Athan_Mawsoa_mp3/076-3.mp3'],
      durationFormatted: '03:42',
      quality: 'استوديو عالي النقاء HD',
      categoryAr: 'أذان الفجر',
      muezzinName: 'الشيخ ناصر القطامي',
      fileSizeBytes: 3550000,
    ),
    IslamicAudioTrack(
      id: 'adhan_haza_albalushi',
      title: 'أذان القارئ هزاع البلوشي',
      subtitle: 'التسجيل غير متاح حتى مراجعة الاسم والمصدر',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: null,
      fallbackUrls: [],
      durationFormatted: '03:20',
      quality: 'غير متاح',
      categoryAr: 'العالم الإسلامي',
      muezzinName: 'القارئ هزاع البلوشي',
      fileSizeBytes: 3200000,
    ),
    IslamicAudioTrack(
      id: 'adhan_kabara_rast',
      title: 'أذان الشيخ محمد صلاح الدين كبارة (مقام رست 1957)',
      subtitle: 'تسجيل تاريخي ونادر بمقام الرست الأصيل',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/093-3.mp3',
      fallbackUrls: ['https://archive.org/download/Athan_Mawsoa_mp3/094-3.mp3'],
      durationFormatted: '03:48',
      quality: 'تسجيل تاريخي نقي',
      categoryAr: 'أذان الخليج والشام',
      muezzinName: 'الشيخ محمد صلاح الدين كبارة',
      fileSizeBytes: 3650000,
    ),
    IslamicAudioTrack(
      id: 'adhan_doukali',
      title: 'أذان الشيخ الدوكالي العالم (ليبيا)',
      subtitle: 'أداء مغاربي أصيل مفعم بالسكينة والوقار الرباني',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/058-2.mp3',
      fallbackUrls: [],
      durationFormatted: '03:15',
      quality: 'عالي النقاء HD',
      categoryAr: 'العالم الإسلامي',
      muezzinName: 'الشيخ الدوكالي العالم',
      fileSizeBytes: 3120000,
    ),
    IslamicAudioTrack(
      id: 'adhan_tokhi',
      title: 'أذان الجمعة من جامع الرفاعي — الشيخ محمود الطوخي',
      subtitle: 'أذان الجمعة المهيب من قلب القاهرة الفاطمية ومسجد الرفاعي',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/070-2.mp3',
      fallbackUrls: [],
      durationFormatted: '04:02',
      quality: 'تسجيل استوديو نقي',
      categoryAr: 'أذان مصر',
      muezzinName: 'الشيخ محمود الطوخي',
      fileSizeBytes: 3880000,
    ),
    IslamicAudioTrack(
      id: 'adhan_walid_mehsas',
      title: 'أذان الشيخ وليد مهساس (الجزائر)',
      subtitle: 'الأداء الجزائري الرقيق بنفحات السكينة والطمأنينة',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/171-4.mp3',
      fallbackUrls: [],
      durationFormatted: '03:08',
      quality: 'عالي النقاء HD',
      categoryAr: 'العالم الإسلامي',
      muezzinName: 'الشيخ وليد مهساس',
      fileSizeBytes: 3010000,
    ),
    IslamicAudioTrack(
      id: 'adhan_fakhro',
      title: 'أذان أحمد فخرو (جامع الإمام محمد بن عبد الوهاب)',
      subtitle: 'نداء الفلاح بصوت مؤذن جامع قطر الكبير بالدوحة',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/039-13.mp3',
      fallbackUrls: [],
      durationFormatted: '03:36',
      quality: 'استوديو نقي 192kbps',
      categoryAr: 'أذان الخليج والشام',
      muezzinName: 'أحمد فخرو',
      fileSizeBytes: 3460000,
    ),
    IslamicAudioTrack(
      id: 'adhan_emadi',
      title: 'أذان أحمد العمادي (قطر)',
      subtitle: 'نبرة صوت خليجية عذبة ترقى بها الأرواح',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/064-2.mp3',
      fallbackUrls: [],
      durationFormatted: '03:22',
      quality: 'عالي النقاء HD',
      categoryAr: 'أذان الخليج والشام',
      muezzinName: 'أحمد العمادي',
      fileSizeBytes: 3240000,
    ),
    IslamicAudioTrack(
      id: 'adhan_marroush',
      title: 'أذان القارئ كمال محمد المروش (المغرب)',
      subtitle: 'نداء الصلاة بالأداء المغربي الأصيل والتراث الفاسي',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/071-2.mp3',
      fallbackUrls: [],
      durationFormatted: '03:10',
      quality: 'عالي النقاء HD',
      categoryAr: 'العالم الإسلامي',
      muezzinName: 'القارئ كمال محمد المروش',
      fileSizeBytes: 3040000,
    ),
    IslamicAudioTrack(
      id: 'adhan_palestine_sohaib',
      title: 'أذان من فلسطين — بصوت صهيب هاني',
      subtitle: 'نداء الصلاة الخاشع من أرض فلسطين الطاهرة',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/044-1.mp3',
      fallbackUrls: [],
      durationFormatted: '03:28',
      quality: 'عالي النقاء HD',
      categoryAr: 'القدس الشريف',
      muezzinName: 'صهيب هاني',
      fileSizeBytes: 3330000,
    ),
    IslamicAudioTrack(
      id: 'adhan_iraq_assaf',
      title: 'أذان العشاء من بغداد — القارئ ياسين العساف',
      subtitle: 'أذان العشاء العراقي الشجي من مساجد بغداد العريقة',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/101-3.mp3',
      fallbackUrls: [],
      durationFormatted: '03:45',
      quality: 'عالي النقاء HD',
      categoryAr: 'أذان الخليج والشام',
      muezzinName: 'القارئ ياسين العساف',
      fileSizeBytes: 3600000,
    ),
    IslamicAudioTrack(
      id: 'adhan_fajr_iraq_assaf',
      title: 'أذان الفجر من العراق — القارئ ياسين العساف',
      subtitle: 'أذان فجر خاشع بنفحات المقام العراقي الشجي',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/079-3.mp3',
      fallbackUrls: [],
      durationFormatted: '03:38',
      quality: 'عالي النقاء HD',
      categoryAr: 'أذان الفجر',
      muezzinName: 'القارئ ياسين العساف',
      fileSizeBytes: 3490000,
    ),
    IslamicAudioTrack(
      id: 'adhan_kuwait',
      title: 'أذان دولة الكويت الرسمي',
      subtitle: 'نداء الصلاة الخاشع من مساجد دولة الكويت الكبرى',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/001.mp3',
      fallbackUrls: [],
      durationFormatted: '03:35',
      quality: 'استوديو نقي 192kbps',
      categoryAr: 'أذان الخليج والشام',
      muezzinName: 'مؤذن مساجد الكويت',
      fileSizeBytes: 3450000,
    ),
    IslamicAudioTrack(
      id: 'adhan_fajr_kuwait',
      title: 'أذان الفجر من دولة الكويت',
      subtitle: 'نداء الفجر الخاشع مع الصلاة خير من النوم من مساجد الكويت',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/002.mp3',
      fallbackUrls: [],
      durationFormatted: '03:40',
      quality: 'استوديو نقي 192kbps',
      categoryAr: 'أذان الفجر',
      muezzinName: 'مؤذن مساجد الكويت',
      fileSizeBytes: 3520000,
    ),
    IslamicAudioTrack(
      id: 'adhan_oman',
      title: 'أذان مسقط وسلطنة عمان',
      subtitle: 'نداء الفلاح من رحاب مساجد سلطنة عمان ومسقط',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/031.mp3',
      fallbackUrls: [],
      durationFormatted: '03:20',
      quality: 'عالي النقاء HD',
      categoryAr: 'أذان الخليج والشام',
      muezzinName: 'مؤذن مساجد سلطنة عمان',
      fileSizeBytes: 3200000,
    ),
    IslamicAudioTrack(
      id: 'takbeerat',
      title: 'تكبيرات الأذان والعيدين',
      subtitle: 'الله أكبر الله أكبر ولله الحمد — نداء الفرح والتعظيم',
      type: IslamicAudioType.adhan,
      assetPath: 'assets/audio/takbeerat.mp3',
      rawNotificationSound: 'takbeerat',
      durationFormatted: '00:15',
      quality: 'نغمة سريعة مدمجة',
      categoryAr: 'تكبيرات',
      fileSizeBytes: 150559,
    ),

    // --- باقة أصوات الأذان الموسعة (جودة استوديو فائقة 320kbps HD) ---
    IslamicAudioTrack(
      id: 'adhan_menshawi',
      title: 'أذان الشيخ محمد صديق المنشاوي',
      subtitle: 'تسجيل أذان من مكتبة السبيل، محمد صديق المنشاوي',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://media.assabile.com/assabile/adhan_3435370/a2b25725149e.mp3',
      fallbackUrls: [],
      durationFormatted: '04:07',
      quality: 'MP3 128 كيلوبت/ث، تسجيل تاريخي',
      categoryAr: 'أذان مصر',
      muezzinName: 'الشيخ محمد صديق المنشاوي',
      fileSizeBytes: 3955074,
    ),
    IslamicAudioTrack(
      id: 'adhan_naqshbandi',
      title: 'أذان الشيخ سيد النقشبندي',
      subtitle: 'الأذان بصوت الشيخ سيد النقشبندي، مكتبة الهدى والنور',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://media.myhuda.com/download/files/media/11-Anasheed/2-Naqshab_Tawasheeh/11.mp3',
      fallbackUrls: [],
      durationFormatted: '02:38',
      quality: 'MP3 128 كيلوبت/ث، تسجيل تاريخي',
      categoryAr: 'أذان مصر',
      muezzinName: 'الشيخ سيد النقشبندي',
      fileSizeBytes: 2528903,
    ),
    IslamicAudioTrack(
      id: 'adhan_fares_abbad',
      title: 'أذان الشيخ فارس عباد',
      subtitle: 'صدح ندي خاشع يأسر القلوب لنداء الحق من اليمن والخليج',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/076-3.mp3',
      fallbackUrls: [],
      durationFormatted: '02:41',
      quality: 'استوديو نقي 192kbps HD',
      categoryAr: 'أذان الخليج والشام',
      muezzinName: 'الشيخ فارس عباد',
      fileSizeBytes: 2275000,
    ),
    IslamicAudioTrack(
      id: 'adhan_ali_jaber',
      title: 'أذان الشيخ علي جابر (رحمه الله)',
      subtitle: 'الصوت المكي الرخيم لإمام الحرم المكي الشريف',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/030.mp3',
      fallbackUrls: [],
      durationFormatted: '03:25',
      quality: 'عالي النقاء 320kbps HD',
      categoryAr: 'أذان الحرمين',
      muezzinName: 'الشيخ علي جابر',
      fileSizeBytes: 3300000,
    ),
    IslamicAudioTrack(
      id: 'adhan_sudais',
      title: 'أذان الشيخ عبد الرحمن السديس',
      subtitle: 'نداء الحق بنبرة إمام وخطيب المسجد الحرام بمكة المكرمة',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/032.mp3',
      fallbackUrls: [],
      durationFormatted: '03:15',
      quality: 'استوديو نقي 320kbps HD',
      categoryAr: 'أذان الحرمين',
      muezzinName: 'الشيخ عبد الرحمن السديس',
      fileSizeBytes: 3100000,
    ),
    IslamicAudioTrack(
      id: 'adhan_shuraim',
      title: 'أذان الشيخ سعود الشريم',
      subtitle: 'أداء وقور مفعم بالسكينة والإخبات من رحاب الكعبة المشرفة',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/033.mp3',
      fallbackUrls: [],
      durationFormatted: '03:30',
      quality: 'عالي النقاء 320kbps HD',
      categoryAr: 'أذان الحرمين',
      muezzinName: 'الشيخ سعود الشريم',
      fileSizeBytes: 3350000,
    ),
    IslamicAudioTrack(
      id: 'adhan_ghamdi',
      title: 'أذان الشيخ سعد الغامدي',
      subtitle: 'الصوت الشجي المألوف بمشاعر الخشوع والرهبة الربانية',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/034.mp3',
      fallbackUrls: [],
      durationFormatted: '03:40',
      quality: 'استوديو نقي 320kbps HD',
      categoryAr: 'أذان الخليج والشام',
      muezzinName: 'الشيخ سعد الغامدي',
      fileSizeBytes: 3500000,
    ),
    IslamicAudioTrack(
      id: 'adhan_maher',
      title: 'أذان الشيخ ماهر المعيقلي',
      subtitle: 'نبرة صوت ندية رقراقة من محراب المسجد الحرام',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/035.mp3',
      fallbackUrls: [],
      durationFormatted: '03:35',
      quality: 'استوديو نقي 320kbps HD',
      categoryAr: 'أذان الحرمين',
      muezzinName: 'الشيخ ماهر المعيقلي',
      fileSizeBytes: 3450000,
    ),
    IslamicAudioTrack(
      id: 'adhan_naif_fida',
      title: 'أذان الشيخ نايف بن صالح فيده',
      subtitle: 'شيخ مؤذني الحرم المكي — أداء حجازي مهيب وتكبيرات جليلة',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/036.mp3',
      durationFormatted: '03:48',
      quality: 'استوديو نقي 320kbps HD',
      categoryAr: 'أذان الحرمين',
      muezzinName: 'الشيخ نايف فيده',
      fileSizeBytes: 3650000,
    ),
    IslamicAudioTrack(
      id: 'adhan_daghriri',
      title: 'أذان الشيخ حمد دغريري',
      subtitle: 'مؤذن المسجد الحرام الشريف — صدح عذب بالتوحيد والشهادة',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/037.mp3',
      durationFormatted: '03:42',
      quality: 'عالي النقاء 320kbps HD',
      categoryAr: 'أذان الحرمين',
      muezzinName: 'الشيخ حمد دغريري',
      fileSizeBytes: 3550000,
    ),
    IslamicAudioTrack(
      id: 'adhan_suraihi',
      title: 'أذان الشيخ عبد المجيد السريحي',
      subtitle: 'مؤذن المسجد النبوي الشريف — أداء مدني خاشع من جوار الروضة',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/038.mp3',
      durationFormatted: '03:55',
      quality: 'استوديو نقي 320kbps HD',
      categoryAr: 'أذان الحرمين',
      muezzinName: 'الشيخ عبد المجيد السريحي',
      fileSizeBytes: 3750000,
    ),
    IslamicAudioTrack(
      id: 'adhan_azhar',
      title: 'أذان الجامع الأزهر الشريف (القاهرة)',
      subtitle: 'صوت مئذنة الأزهر الشريف ومنارة العلم والإسلام لألف عام',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/039.mp3',
      durationFormatted: '03:30',
      quality: 'عالي النقاء 320kbps HD',
      categoryAr: 'أذان مصر',
      muezzinName: 'مؤذن الجامع الأزهر',
      fileSizeBytes: 3350000,
    ),
    IslamicAudioTrack(
      id: 'adhan_morocco_qarawiyyin',
      title: 'أذان جامع القرويين (فاس - المغرب)',
      subtitle: 'الأذان المغربي العتيق بالصيغة واللحن الأندلسي الأصيل',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/040.mp3',
      durationFormatted: '03:10',
      quality: 'استوديو نقي 320kbps HD',
      categoryAr: 'العالم الإسلامي',
      muezzinName: 'مؤذن جامع القرويين',
      fileSizeBytes: 3050000,
    ),
    IslamicAudioTrack(
      id: 'adhan_tunis_zaytouna',
      title: 'أذان جامع الزيتونة المعمور (تونس)',
      subtitle: 'الأداء التونسي الخاشع من منارة الزيتونة التاريخية',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/041.mp3',
      durationFormatted: '03:15',
      quality: 'عالي النقاء 320kbps HD',
      categoryAr: 'العالم الإسلامي',
      muezzinName: 'مؤذن جامع الزيتونة',
      fileSizeBytes: 3120000,
    ),
    IslamicAudioTrack(
      id: 'adhan_khalil_aqsa',
      title: 'أذان الحرم الإبراهيمي الشريف (الخليل)',
      subtitle: 'نداء التوحيد والصمود من جوار خليل الرحمن إبراهيم عليه السلام',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/042.mp3',
      durationFormatted: '03:00',
      quality: 'تسجيل تاريخي نقي 320kbps',
      categoryAr: 'القدس الشريف',
      muezzinName: 'مؤذن الحرم الإبراهيمي',
      fileSizeBytes: 2900000,
    ),
    IslamicAudioTrack(
      id: 'adhan_fatih_istanbul',
      title: 'أذان جامع الفاتح الكبير (إسطنبول)',
      subtitle: 'الأذان العثماني الرخيم بمقام الرست والنهوند العذب',
      type: IslamicAudioType.adhan,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/043.mp3',
      durationFormatted: '03:22',
      quality: 'عالي النقاء 320kbps HD',
      categoryAr: 'العالم الإسلامي',
      muezzinName: 'مؤذن جامع الفاتح',
      fileSizeBytes: 3250000,
    ),

    // 2. باقة أصوات إقامة الصلاة المتنوعة (Iqama Tracks)
    IslamicAudioTrack(
      id: 'iqamah_full',
      title: 'إقامة المسجد الحرام (مكة المكرمة)',
      subtitle: 'قد قامت الصلاة قد قامت الصلاة — بصوت شيخ مؤذني الحرم المكي',
      type: IslamicAudioType.iqamah,
      assetPath: 'assets/audio/iqamah.mp3',
      rawNotificationSound: 'iqamah',
      durationFormatted: '01:33',
      quality: 'استوديو نقي مدمج',
      categoryAr: 'الحرم المكي',
      muezzinName: 'مؤذن المسجد الحرام',
      fileSizeBytes: 123308,
    ),
    IslamicAudioTrack(
      id: 'iqamah_madinah',
      title: 'إقامة المسجد النبوي الشريف',
      subtitle: 'إقامة هادئة خاشعة بروحانية وسكينة مدينة رسول الله ﷺ',
      type: IslamicAudioType.iqamah,
      assetPath: 'assets/audio/iqamah.mp3',
      rawNotificationSound: 'iqamah',
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/016.mp3',
      fallbackUrls: ['https://archive.org/download/Athan_Mawsoa_mp3/013.mp3'],
      durationFormatted: '01:33',
      quality: 'عالي النقاء HD',
      categoryAr: 'المسجد النبوي',
      muezzinName: 'مؤذن الحرم النبوي',
      fileSizeBytes: 123308,
    ),
    IslamicAudioTrack(
      id: 'iqamah_afasy',
      title: 'إقامة الشيخ مشاري بن راشد العفاسي',
      subtitle: 'تنبيه إقامة الصلاة بأداء متقن متزن',
      type: IslamicAudioType.iqamah,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/007.mp3',
      durationFormatted: '00:48',
      quality: 'عالي النقاء HD 192kbps',
      categoryAr: 'مشاهير القراء',
      muezzinName: 'الشيخ مشاري العفاسي',
      fileSizeBytes: 770000,
    ),
    IslamicAudioTrack(
      id: 'iqamah_abdulbasit',
      title: 'إقامة الشيخ عبد الباسط عبد الصمد',
      subtitle: 'إقامة وقورة بصوت القارئ المفضل للوقوف بين يدي الله',
      type: IslamicAudioType.iqamah,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/012.mp3',
      durationFormatted: '01:40',
      quality: 'عالي النقاء HD 192kbps',
      categoryAr: 'مشاهير القراء',
      muezzinName: 'الشيخ عبد الباسط عبد الصمد',
      fileSizeBytes: 1600000,
    ),
    IslamicAudioTrack(
      id: 'iqamah_cairo',
      title: 'إقامة مساجد القاهرة والأزهر الشريف',
      subtitle: 'نداء الإقامة المصري الأصيل المعمول به في مساجد مصر',
      type: IslamicAudioType.iqamah,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Athan_Mawsoa_mp3/017.mp3',
      durationFormatted: '01:11',
      quality: 'عالي النقاء HD',
      categoryAr: 'مساجد مصر',
      muezzinName: 'مؤذنو القاهرة',
      fileSizeBytes: 1140000,
    ),
    IslamicAudioTrack(
      id: 'iqamah_short',
      title: 'إقامة سريعة وخفيفة للتنبيه',
      subtitle: 'نغمة إقامة مختصرة سريعة للتذكير الفوري بحلول الصلاة',
      type: IslamicAudioType.iqamah,
      assetPath: 'assets/audio/iqamah.mp3',
      rawNotificationSound: 'iqamah',
      durationFormatted: '00:15',
      quality: 'نغمة سريعة مدمجة',
      categoryAr: 'تنبيه سريع',
      fileSizeBytes: 123308,
    ),

    // 3. الأذكار والأدعية (تعمل عبر الإنترنت افتراضياً، وتعمل أوفلاين إذا حمّلها المستخدم)
    IslamicAudioTrack(
      id: 'adhkar_morning',
      title: 'أذكار الصباح كاملة (استوديو HD)',
      subtitle: 'حصن المسلم وبركة اليوم وانشراح الصدر بصوت خاشع نقي (تعمل أوفلاين)',
      type: IslamicAudioType.adhkar,
      assetPath: 'assets/audio/adhkar_morning_full.mp3',
      remoteUrl: 'https://archive.org/download/adkar_sabah_masae_safar/adkar_assbah.mp3',
      fallbackUrls: ['https://archive.org/download/TvQuran.com__Athkar/TvQuran.com_athkar_01.mp3'],
      durationFormatted: '03:38',
      quality: 'استوديو فائق النقاء HD 192kbps',
      categoryAr: 'أذكار الصباح والمساء',
      muezzinName: 'الشيخ مشاري العفاسي',
      fileSizeBytes: 1405868,
    ),
    IslamicAudioTrack(
      id: 'adhkar_evening',
      title: 'أذكار المساء كاملة (استوديو HD)',
      subtitle: 'حفظ الليل وسكينة الروح والاستعاذة من الشرور (تعمل أوفلاين)',
      type: IslamicAudioType.adhkar,
      assetPath: 'assets/audio/adhkar_evening_full.mp3',
      remoteUrl: 'https://archive.org/download/adkar_sabah_masae_safar/adkar_lmasaa.mp3',
      fallbackUrls: ['https://archive.org/download/TvQuran.com__Athkar/TvQuran.com_athkar_02.mp3'],
      durationFormatted: '03:48',
      quality: 'استوديو فائق النقاء HD 192kbps',
      categoryAr: 'أذكار الصباح والمساء',
      muezzinName: 'الشيخ مشاري العفاسي',
      fileSizeBytes: 1601516,
    ),
    IslamicAudioTrack(
      id: 'duaa_sharawi_post_prayer',
      title: 'دعاء ما بعد الأذان والصلاة — الشيخ الشعراوي',
      subtitle: '«اللهم رب هذه الدعوة التامة والصلاة القائمة...» بصوت إمام الدعاة فضيلة الشيخ محمد متولي الشعراوي رحمه الله',
      type: IslamicAudioType.adhkar,
      assetPath: 'assets/audio/duaa_sharawi_post_prayer.mp3',
      remoteUrl: 'https://archive.org/download/alshaarawi/alshaarawi-doaa-24.mp3',
      fallbackUrls: [
        'https://archive.org/download/Islamic_Tape-258_uP_bY_mUSLEm/sharawy_doaa_24.mp3',
      ],
      rawNotificationSound: 'duaa_sharawi_post_prayer',
      durationFormatted: '01:08',
      quality: 'استوديو منقى HD 44.1kHz',
      categoryAr: 'أدعية ما بعد الصلاة',
      muezzinName: 'الشيخ محمد متولي الشعراوي',
      fileSizeBytes: 478780,
    ),
    IslamicAudioTrack(
      id: 'adhkar_post_prayer',
      title: 'أذكار ما بعد الصلاة المكتوبة (HD)',
      subtitle: 'الاستغفار، التسبيح، التحميد، والتكبير تمام المائة وسؤال السلامة',
      type: IslamicAudioType.adhkar,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/TvQuran.com__Athkar/TvQuran.com_athkar_01.mp3',
      fallbackUrls: ['https://archive.org/download/adkar_sabah_masae_safar/adkar_assbah.mp3'],
      durationFormatted: '02:15',
      quality: 'استوديو نقي 192kbps',
      categoryAr: 'أدعية ما بعد الصلاة',
      muezzinName: 'نخبة القراء',
      fileSizeBytes: 2160000,
    ),
    IslamicAudioTrack(
      id: 'adhkar_sleep',
      title: 'أذكار النوم والاضطجاع والسكينة (HD)',
      subtitle: 'باسمك ربي وضعت جنبي وبك أرفعه — سكينة المضجع وحفظ النائم (تعمل أوفلاين)',
      type: IslamicAudioType.adhkar,
      assetPath: 'assets/audio/adhkar_sleep_full.mp3',
      remoteUrl: 'https://archive.org/download/TvQuran.com__Athkar/TvQuran.com_athkar_02.mp3',
      fallbackUrls: ['https://archive.org/download/adkar_sabah_masae_safar/adkar_lmasaa.mp3'],
      durationFormatted: '02:50',
      quality: 'استوديو نقي 192kbps',
      categoryAr: 'أذكار النوم والاستيقاظ',
      muezzinName: 'الشيخ مشاري العفاسي',
      fileSizeBytes: 953132,
    ),
    IslamicAudioTrack(
      id: 'adhkar_waking',
      title: 'أذكار الاستيقاظ من النوم وانشراح الصدر',
      subtitle: 'الحمد لله الذي أحيانا بعد ما أماتنا وإليه النشور — نشاط الروح',
      type: IslamicAudioType.adhkar,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/TvQuran.com__Athkar/TvQuran.com_athkar_03.mp3',
      fallbackUrls: ['https://archive.org/download/adkar_sabah_masae_safar/adkar_assbah.mp3'],
      durationFormatted: '10:33',
      quality: 'استوديو نقي 192kbps',
      categoryAr: 'أذكار النوم والاستيقاظ',
      muezzinName: 'نخبة القراء',
      fileSizeBytes: 6100000,
    ),
    IslamicAudioTrack(
      id: 'adhkar_home_mosque',
      title: 'أذكار المسجد والمنزل والخروج والدخول',
      subtitle: 'دعاء الخروج من البيت والدخول والذهاب للمسجد وأبواب الرحمة',
      type: IslamicAudioType.adhkar,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/TvQuran.com__Athkar/TvQuran.com_athkar_04.mp3',
      fallbackUrls: ['https://archive.org/download/adkar_sabah_masae_safar/adkar_assbah.mp3'],
      durationFormatted: '10:29',
      quality: 'استوديو نقي 192kbps',
      categoryAr: 'حصن المسلم المسموع',
      muezzinName: 'نخبة القراء',
      fileSizeBytes: 6050000,
    ),
    IslamicAudioTrack(
      id: 'prophetic_duas',
      title: 'جوامع الأدعية النبوية الشريفة (استوديو HD)',
      subtitle: 'أدعية رسول الله ﷺ الجامعة لخير الدنيا والآخرة والوقاية من الفتن',
      type: IslamicAudioType.adhkar,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/TvQuran.com__Athkar/TvQuran.com_athkar_05.mp3',
      fallbackUrls: ['https://archive.org/download/alshaarawi/alshaarawi-doaa-24.mp3'],
      durationFormatted: '10:17',
      quality: 'استوديو فائق النقاء HD 192kbps',
      categoryAr: 'الأدعية النبوية والقرآنية',
      muezzinName: 'نخبة القراء',
      fileSizeBytes: 5900000,
    ),
    IslamicAudioTrack(
      id: 'ruqyah_shariah',
      title: 'الرقية الشرعية الشاملة بالقرآن والسنة (HD)',
      subtitle: 'رقية المسلم من العين والحسد والهم بآيات الشفاء والأدعية النبوية الصحيحة',
      type: IslamicAudioType.adhkar,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/TvQuran.com__Athkar/TvQuran.com_athkar_06.mp3',
      fallbackUrls: ['https://server8.mp3quran.net/afs/001.mp3'],
      durationFormatted: '10:14',
      quality: 'استوديو فائق النقاء HD 192kbps',
      categoryAr: 'الرقية والتحصين',
      muezzinName: 'نخبة القراء',
      fileSizeBytes: 5850000,
    ),
    IslamicAudioTrack(
      id: 'dua_khatm_abdulbasit',
      title: 'دعاء ختم القرآن الكريم — الشيخ عبد الباسط عبد الصمد',
      subtitle: 'ابتهال ودعاء خاشع عند ختم كتاب الله بالصوت الذهبي الخالد',
      type: IslamicAudioType.adhkar,
      assetPath: null,
      remoteUrl: 'https://server7.mp3quran.net/basit/114.mp3',
      fallbackUrls: ['https://server7.mp3quran.net/basit_mjwd/001.mp3'],
      durationFormatted: '04:12',
      quality: 'استوديو فائق النقاء HD 192kbps',
      categoryAr: 'أدعية ختم القرآن والقنوت',
      muezzinName: 'الشيخ عبد الباسط عبد الصمد',
      fileSizeBytes: 4100000,
    ),
    IslamicAudioTrack(
      id: 'dua_khatm_minshawi',
      title: 'دعاء ختم القرآن والخشوع — الشيخ محمد صديق المنشاوي',
      subtitle: 'تضرع وبكاء خاشع في رحاب القرآن الكريم بصوت القارئ الباكي',
      type: IslamicAudioType.adhkar,
      assetPath: null,
      remoteUrl: 'https://server10.mp3quran.net/minsh/114.mp3',
      fallbackUrls: ['https://server10.mp3quran.net/minsh/001.mp3'],
      durationFormatted: '03:45',
      quality: 'استوديو فائق النقاء HD 192kbps',
      categoryAr: 'أدعية ختم القرآن والقنوت',
      muezzinName: 'الشيخ محمد صديق المنشاوي',
      fileSizeBytes: 3600000,
    ),
    IslamicAudioTrack(
      id: 'dua_qunoot_afasy',
      title: 'دعاء القنوت والوتر في قيام الليل — الشيخ مشاري العفاسي',
      subtitle: 'اللهم اهدنا فيمن هديت وعافنا فيمن عافيت وتولنا فيمن توليت',
      type: IslamicAudioType.adhkar,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/TvQuran.com__Athkar/TvQuran.com_athkar_05.mp3',
      fallbackUrls: ['https://server8.mp3quran.net/afs/001.mp3'],
      durationFormatted: '06:20',
      quality: 'استوديو فائق النقاء HD 192kbps',
      categoryAr: 'أدعية ختم القرآن والقنوت',
      muezzinName: 'الشيخ مشاري العفاسي',
      fileSizeBytes: 4800000,
    ),
    IslamicAudioTrack(
      id: 'dua_faraj_sharawi',
      title: 'دعاء تفريج الكرب والهم والضيق — الشيخ الشعراوي',
      subtitle: 'تضرع خاشع إلى الله لكشف الغم وتيسير العسير وجبر الخواطر',
      type: IslamicAudioType.adhkar,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/alshaarawi/alshaarawi-doaa-01.mp3',
      fallbackUrls: ['https://archive.org/download/alshaarawi/alshaarawi-doaa-24.mp3'],
      durationFormatted: '05:15',
      quality: 'تسجيل إذاعي منقى HD',
      categoryAr: 'الأدعية النبوية والقرآنية',
      muezzinName: 'الشيخ محمد متولي الشعراوي',
      fileSizeBytes: 478780,
    ),
    IslamicAudioTrack(
      id: 'dua_rizq_sharawi',
      title: 'دعاء الرزق الحلال والبركة والتيسير — الشيخ الشعراوي',
      subtitle: 'اللهم اكفنا بحلالك عن حرامك وأغننا بفضلك عمن سواك',
      type: IslamicAudioType.adhkar,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/alshaarawi/alshaarawi-doaa-10.mp3',
      fallbackUrls: ['https://archive.org/download/alshaarawi/alshaarawi-doaa-24.mp3'],
      durationFormatted: '04:50',
      quality: 'تسجيل إذاعي منقى HD',
      categoryAr: 'الأدعية النبوية والقرآنية',
      muezzinName: 'الشيخ محمد متولي الشعراوي',
      fileSizeBytes: 478780,
    ),
    IslamicAudioTrack(
      id: 'ibtihal_naqshbandi_mawlay',
      title: 'ابتهال «مولاي إني ببابك قد بسطت يدي» — الشيخ سيد النقشبندي',
      subtitle: 'أيقونة الابتهالات المصرية في السحر والفجر بجودة إذاعية منقاة HD',
      type: IslamicAudioType.adhkar,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Naqshbandi_Ibtihalat/Mawlay.mp3',
      fallbackUrls: ['https://archive.org/download/alshaarawi/alshaarawi-doaa-24.mp3'],
      durationFormatted: '07:40',
      quality: 'إذاعة القرآن الكريم HD',
      categoryAr: 'الابتهالات والتواشيح',
      muezzinName: 'الشيخ سيد النقشبندي',
      fileSizeBytes: 5400000,
    ),
    IslamicAudioTrack(
      id: 'ibtihal_tobar_subhan',
      title: 'ابتهال «جل المنادي وسبحان من عنت الوجوه» — الشيخ نصر الدين طوبار',
      subtitle: 'ابتهال الفجر الخاشع من تراث إذاعة القرآن الكريم بالقاهرة',
      type: IslamicAudioType.adhkar,
      assetPath: null,
      remoteUrl: 'https://archive.org/download/Nasr_Al_Din_Tobar/Jal_Al_Monadi.mp3',
      fallbackUrls: ['https://archive.org/download/alshaarawi/alshaarawi-doaa-24.mp3'],
      durationFormatted: '06:55',
      quality: 'إذاعة القرآن الكريم HD',
      categoryAr: 'الابتهالات والتواشيح',
      muezzinName: 'الشيخ نصر الدين طوبار',
      fileSizeBytes: 4950000,
    ),
  ];

  Future<void> init() async {
    if (_needsLegacyContainment) await containLegacyAdhkarPlayback();
    if (_isInitialized) return;

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
          _player.play();
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
    } catch (e) {
      debugPrint('IslamicAudioService init directory error: $e');
    }

    _isInitialized = true;
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
    _downloadedLocalPaths.clear();
    _downloadedFileSizes.clear();
    _retiredRecordingPaths.clear();
    _retiredRecordingSizes.clear();
    if (!await dir.exists()) return;

    final entities = dir.listSync();
    for (final entity in entities) {
      if (entity is File && (entity.path.endsWith('.tmp') || entity.path.endsWith('.part'))) {
        try {
          entity.deleteSync();
        } catch (_) {}
        continue;
      }
      if (entity is File && entity.path.endsWith('.mp3')) {
        final nonEmptySegs = entity.uri.pathSegments.where((s) => s.isNotEmpty);
          if (nonEmptySegs.isEmpty) continue;
          final filename = nonEmptySegs.last;
        final matching = allTracks.where(
            (track) => downloadFileNameForTrack(track.id) == filename);
        if (matching.isEmpty) {
          final legacyId = filename.substring(0, filename.length - 4);
          if (reviewedAdhanRecordingRevision.containsKey(legacyId)) {
            _retiredRecordingPaths[legacyId] = entity.path;
            _retiredRecordingSizes[legacyId] = entity.lengthSync();
          }
        }
        if (matching.isNotEmpty) {
          final id = matching.first.id;
          final size = entity.lengthSync();
          if (size > 1000) {
            _downloadedLocalPaths[id] = entity.path;
            _downloadedFileSizes[id] = size;
          }
        }
      }
    }
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
    final path = _downloadedLocalPaths[id];
    if (path == null) return false;
    final f = File(path);
    if (f.uri.pathSegments.last != downloadFileNameForTrack(id)) return false;
    return f.existsSync() && f.lengthSync() > 1000;
  }

  String? getLocalAudioPath(String id) {
    if (isDownloaded(id)) {
      return _downloadedLocalPaths[id];
    }
    return null;
  }

  bool isDownloading(String id) => _activeProgress.containsKey(id);

  double getDownloadProgress(String id) => _activeProgress[id] ?? 0.0;

  /// Downloads all remote Adhan tracks for 100% offline playback
  Future<void> downloadAllAdhanTracks({void Function(int completed, int total)? onProgress}) async {
    final adhanList = allTracks
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
    final track = allTracks.firstWhere((t) => t.id == id, orElse: () => allTracks.first);
    if (isHeldRecording(track) || track.remoteUrl == null || isDownloading(id)) return false;

    await init();
    if (isDownloading(id)) return false;
    final dirPath = _storageDirPath;
    if (dirPath == null) return false;

    final filePath = '$dirPath/${downloadFileNameForTrack(id)}';
    final attempt = ++_downloadAttemptCounter;
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
            final fileSize = tempFile.lengthSync();
            tempFile.renameSync(filePath);
            _downloadedLocalPaths[id] = filePath;
            _downloadedFileSizes[id] = fileSize;
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

  Future<bool> deleteDownloadedTrack(String id) async {
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
      _downloadedLocalPaths.remove(id);
      _downloadedFileSizes.remove(id);
      _retiredRecordingPaths.remove(id);
      _retiredRecordingSizes.remove(id);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Delete track error: $e');
      return false;
    }
  }

  Future<void> deleteAllDownloadedTracks() async {
    for (final path in [..._downloadedLocalPaths.values, ..._retiredRecordingPaths.values]) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
    }
    _downloadedLocalPaths.clear();
    _downloadedFileSizes.clear();
    _retiredRecordingPaths.clear();
    _retiredRecordingSizes.clear();
    notifyListeners();
  }

  List<IslamicAudioTrack> getDownloadedTracks() {
    return allTracks.where((t) => isDownloaded(t.id)).toList();
  }

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
    final track = allTracks.firstWhere(
      (t) => t.id == normalizedId || t.rawNotificationSound == trackId,
      orElse: () => allTracks.first,
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
    _isOnlinePreview = false;
    _onlinePreviewSession++;
    if (_needsLegacyContainment) await containLegacyAdhkarPlayback();
    if (_legacyStopFailed) return;
    if (isHeldRecording(track)) {
      _heldLegacyTrack = track;
      notifyListeners();
      return;
    }
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
      try {
        await _player.stop();
      } catch (_) {}
      await FastAudioService.instance.claimAudioFocus(player: _player, onStopOther: stop);
      await _player.setVolume(1.0);
      // 1. Check if user explicitly downloaded the HD file (offline HD playback)
      final localPath = getLocalAudioPath(track.id);
      if (localPath != null) {
        await _player.setFilePath(localPath);
        await _player.setSpeed(_playbackSpeed);
        unawaited(_player.play());
      }
      // 2. If a Studio HD remote stream exists, try resilient HD streaming & disk caching first,
      //    and fall back to the remastered 44.1kHz Stereo bundled asset if offline!
      else if (track.remoteUrl != null) {
        final cacheKey = 'audio_hd_${track.id}';
        final success = await FastAudioService.instance.playResilient(
          track.remoteUrl!,
          player: _player,
          onStopCallback: stop,
          primaryUrl: track.remoteUrl!,
          fallbackUrls: track.fallbackUrls,
          cacheKey: cacheKey,
        );
        if (success) {
          await _player.setSpeed(_playbackSpeed);
        } else if (track.assetPath != null) {
          // Seamless offline fallback to remastered 44.1kHz Stereo bundled asset
          if (!kIsWeb && File(track.assetPath!).existsSync()) {
            await _player.setFilePath(track.assetPath!);
          } else {
            await _player.setAsset(track.assetPath!);
          }
          await _player.setSpeed(_playbackSpeed);
          unawaited(_player.play());
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
        await _player.setSpeed(_playbackSpeed);
        unawaited(_player.play());
      } else {
        throw Exception('No playable audio source found for ${track.id}');
      }
    } catch (e) {
      debugPrint('Error playing ${track.id}: $e');
      _isBuffering = false;
      _isPlaying = false;
      _currentTrack = null;
      notifyListeners();
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
    if (_currentTrack != null) {
      try {
        await _player.play();
      } catch (e) {
        debugPrint('Audio resume error: $e');
      }
    }
  }

  Future<void> stop() async {
    _onlinePreviewSession++;
    _isOnlinePreview = false;
    if (disableNativePlayerForTesting) {
      _isPlaying = false;
      _currentTrack = null;
      _position = Duration.zero;
      notifyListeners();
      return;
    }
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('Audio stop error: $e');
    }
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
    return allTracks.where((t) => t.type == type).toList();
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferedPositionSub?.cancel();
    _player.dispose();
    _sfxPlayer.dispose();
    super.dispose();
  }
}
