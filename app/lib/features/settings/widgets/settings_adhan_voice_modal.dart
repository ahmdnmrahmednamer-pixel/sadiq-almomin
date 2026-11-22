import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../../../core/audio/fast_audio_service.dart';
import 'adhan_voice_option.dart';
import '../../../core/text/arabic_normalizer.dart';
import '../../../core/services/settings_service.dart';
import 'package:flutter/material.dart';
import '../../../core/notifications/prayer_notification_service.dart';
import '../../../core/services/islamic_audio_service.dart';

/// Old saved choices are retained, but must not imply their recording is used.
String? savedAdhanFallbackNotice(String key) {
  if (PrayerNotificationService.adhanAssignmentUnavailableReason(key) == null) {
    return null;
  }
  return 'التسجيل المحفوظ غير مدعوم لأذان التنبيه. في وضع الأذان يُستخدم صوت مكة الموجود مؤقتًا، وليس التسجيل المحفوظ. مواعيد التذكير واختيارك المحفوظ لم يتغيرا، مع احترام وضع الصامت والاهتزاز وباقي أوضاع التنبيه. اختر صوتًا مدعومًا من القائمة لتغييره.';
}

String getAdhanVoiceName(String key) {
  final tracks = IslamicAudioService.allTracks.where(
    (t) => t.id == key || t.rawNotificationSound == key,
  );
  final name = tracks.isEmpty ? 'اختيار صوت قديم غير معروف' : adhanVoiceLabel(tracks.first);
  if (savedAdhanFallbackNotice(key) == null) return name;
  return '$name. غير مدعوم للتنبيه؛ البديل في وضع الأذان: صوت مكة مؤقتًا. مواعيد التذكير وأوضاع التنبيه لم تتغير. اضغط لاختيار صوت مدعوم.';
}

String adhanVoiceLabel(IslamicAudioTrack track) {
  final name = track.muezzinName?.trim();
  if (name == null || name.isEmpty) return track.title;
  return track.id.contains('fajr') ? '$name (الفجر)' : name;
}

/// Optional source details stay separate from the plain voice name.
String? adhanSourceDetails(IslamicAudioTrack track) {
  if (track.sourceFileNames.isEmpty) return null;
  final reason =
      PrayerNotificationService.adhanAssignmentUnavailableReason(track.id);
  return [
    'الاسم كما ورد في المصدر، ولم تُتحقق نسبة الصوت إلى صاحبه.',
    ...track.sourceFileNames,
    if (reason != null) reason,
    if (track.sourceUrl != null) track.sourceUrl!,
  ].join('\n\n');
}

String getIqamahVoiceName(String key) {
  switch (key) {
    case 'iqamah_madinah':
      return 'إقامة المسجد النبوي الشريف (المدينة المنورة)';
    case 'iqamah_afasy':
      return 'إقامة الشيخ مشاري بن راشد العفاسي';
    case 'iqamah_abdulbasit':
      return 'إقامة الشيخ عبد الباسط عبد الصمد';
    case 'iqamah_cairo':
      return 'إقامة مساجد القاهرة والأزهر الشريف';
    case 'iqamah_short':
      return 'إقامة سريعة وخفيفة للتنبيه';
    case 'iqamah_makkah':
    case 'iqamah_full':
    default:
      return 'إقامة المسجد الحرام (مكة المكرمة)';
  }
}

void showSettingsAdhanVoiceModal(BuildContext context,
    {int initialTab = 0, String? initialPrayer}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PrayerMuezzinManagerSheet(
      initialTab: initialTab,
      initialPrayer: initialPrayer,
    ),
  );
}

/// Sheet showing the 5 daily prayers, each with its dedicated Muezzin dropdown and audio preview
class _PrayerMuezzinManagerSheet extends StatefulWidget {
  final int initialTab;
  final String? initialPrayer;
  const _PrayerMuezzinManagerSheet({this.initialTab = 0, this.initialPrayer});
  @override
  State<_PrayerMuezzinManagerSheet> createState() =>
      _PrayerMuezzinManagerSheetState();
}

class _PrayerMuezzinManagerSheetState
    extends State<_PrayerMuezzinManagerSheet> {
  @override
  void initState() {
    super.initState();
    if (widget.initialPrayer != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showPrayerMuezzinDropdownPicker(context, widget.initialPrayer!);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: SettingsService.instance.textDirection,
        child: SafeArea(
            child: Material(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.88,
            child: Column(children: [
              ListTile(
                  title: const Text('مؤذنو الصلوات الخمس'),
                  trailing: IconButton(
                      tooltip: 'إغلاق',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context))),
              const Expanded(
                  child: SingleChildScrollView(child: PrayerVoiceList())),
            ]),
          ),
        )),
      );
}

/// All entry points open the same per-prayer voice picker.
class PrayerVoiceList extends StatelessWidget {
  const PrayerVoiceList({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: PrayerNotificationService.instance,
        builder: (context, _) {
          final notifications = PrayerNotificationService.instance;
          return Column(children: [
            for (final name in ['الفجر', 'الظهر', 'العصر', 'المغرب', 'العشاء'])
              ListTile(
                key: ValueKey('prayer_voice_$name'),
                title: Text('صلاة $name'),
                subtitle:
                    Text(getAdhanVoiceName(notifications.getPrayerVoice(name))),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => showPrayerMuezzinDropdownPicker(context, name),
              ),
            ListTile(
                title: const Text('مؤذن لجميع الصلوات'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => showPrayerMuezzinDropdownPicker(context, 'الكل')),
            ListTile(
                title: const Text('صوت الإقامة'),
                subtitle:
                    Text(getIqamahVoiceName(notifications.selectedIqamahVoice)),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => showPrayerMuezzinDropdownPicker(
                    context, 'إقامة الصلاة',
                    isIqamah: true)),
          ]);
        },
      );
}

/// Interactive Dropdown/Picker Sheet for choosing a Sheikh for a specific prayer
/// Allows listening to any Sheikh's voice before selecting him
void showPrayerMuezzinDropdownPicker(BuildContext context, String prayerName,
    {bool isIqamah = false, AudioPlayer Function()? previewPlayerFactory,
    String? selectedVoice, ValueChanged<String>? onStage}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PrayerMuezzinPickerSheet(
      prayerName: prayerName,
      isIqamah: isIqamah,
      previewPlayerFactory: previewPlayerFactory,
      selectedVoice: selectedVoice, onStage: onStage,
    ),
  );
}

class _PrayerMuezzinPickerSheet extends StatefulWidget {
  final String prayerName;
  final String? selectedVoice;
  final ValueChanged<String>? onStage;
  final bool isIqamah;
  final AudioPlayer Function()? previewPlayerFactory;

  const _PrayerMuezzinPickerSheet({
    required this.prayerName,
    this.isIqamah = false,
    this.selectedVoice, this.onStage,
    this.previewPlayerFactory,
  });

  @override
  State<_PrayerMuezzinPickerSheet> createState() =>
      _PrayerMuezzinPickerSheetState();
}

class _PrayerMuezzinPickerSheetState extends State<_PrayerMuezzinPickerSheet>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late final AudioPlayer _previewPlayer;
  StreamSubscription<PlayerState>? _previewState;
  bool _routeCurrent = true;
  int _previewRequest = 0;
  String? _previewTrackId;
  String? _previewError;
  bool _previewPlaying = false;
  bool _previewLoading = false;
  bool _previewStopFailed = false;
  bool _closing = false;
  bool _disposed = false;
  Future<void> _pendingStop = Future<void>.value();
  Future<void> _pendingLoad = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _previewPlayer = widget.previewPlayerFactory?.call() ?? AudioPlayer();
    _previewState = _previewPlayer.playerStateStream.listen(
      (state) {
        if (!mounted || _closing) return;
        setState(() {
          _previewPlaying =
              state.playing &&
              state.processingState != ProcessingState.completed &&
              state.processingState != ProcessingState.idle;
        });
      },
      // just_audio's playerStateStream suppresses playback errors. Do not let
      // an untagged late stream error cancel a newer request. The captured
      // setUrl/play futures below own error handling for their request.
      onError: (Object error, StackTrace stack) {},
    );
    // Download status still comes from the catalog service, not our preview.
    IslamicAudioService.instance.init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (_routeCurrent && !isCurrent) {
      unawaited(_stopPreview().catchError((Object _) {}));
    }
    _routeCurrent = isCurrent;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_stopPreview().catchError((Object _) {}));
    }
  }

  Future<void> _stopPreview({bool preparePlayback = false}) {
    if (_disposed) return Future<void>.value();
    final request = ++_previewRequest;
    if (mounted && !_closing) {
      setState(() => _previewLoading = false);
    }
    // Never stop the global focus owner: it may have changed since Listen.
    _pendingStop = _pendingStop.catchError((Object _) {}).then((_) async {
      if (_disposed) return;
      try {
        await _previewPlayer.stop();
        if (mounted && !_closing && request == _previewRequest) {
          setState(() {
            _previewPlaying = false;
            if (!preparePlayback) _previewTrackId = null;
            _previewStopFailed = false;
          });
        }
      } catch (_) {
        if (mounted && !_closing && request == _previewRequest) {
          setState(() {
            _previewStopFailed = true;
            _previewPlaying = _previewPlayer.playing;
            _previewError = 'تعذر إيقاف المعاينة. أعد محاولة الإيقاف.';
          });
        }
        rethrow;
      }
    });
    return _pendingStop;
  }

  void _previewFailed(int request) {
    if (!mounted || _closing || request != _previewRequest) return;
    setState(
      () => _previewError =
          'تعذر تشغيل الصوت عبر الإنترنت. تحقق من اتصالك ثم حاول مرة أخرى.',
    );
    unawaited(_stopPreview().catchError((Object _) {}));
  }

  Future<void> _playPreview(IslamicAudioTrack track) async {
    if (_closing) return;
    if (IslamicAudioService.unavailableRecordingReason(track.id) != null) return;
    if (_previewTrackId == track.id && (_previewPlaying || _previewLoading || _previewStopFailed)) {
      try {
        await _stopPreview();
      } catch (_) {
        _previewFailed(_previewRequest);
      }
      return;
    }
    final stopped = _stopPreview(preparePlayback: true);
    final request = _previewRequest;
    setState(() {
      _previewTrackId = track.id;
      _previewLoading = true;
      _previewError = null;
    });
    try {
      await stopped;
      await _pendingLoad.catchError((Object _) {});
      if (!mounted || _closing || request != _previewRequest) return;
      final focus = FastAudioService.instance;
      final token = await focus.claimAudioFocus(
        player: _previewPlayer,
        onStopOther: _stopPreview,
      );
      bool current() =>
          mounted &&
          !_closing &&
          request == _previewRequest &&
          token == focus.activePlaybackToken;
      if (!current()) return;
      final urls = [
        if (track.remoteUrl != null) track.remoteUrl!,
        ...track.fallbackUrls,
      ].where((url) => url.trim().isNotEmpty).toList();
      for (final url in urls) {
        if (!current()) return;
        try {
          // Online preview only. No local-file fallback or background download.
          _pendingLoad = _previewPlayer
              .setUrl(url, headers: FastAudioService.fastStreamingHeaders)
              .then<void>((_) {});
          await _pendingLoad;
          if (!current()) return;
          setState(() => _previewLoading = false);
          unawaited(
            _previewPlayer.play().catchError((Object _) {
              _previewFailed(request);
            }),
          );
          return;
        } catch (_) {
          _pendingLoad = Future<void>.value();
          if (!current()) return;
        }
      }
      _previewFailed(request);
    } catch (_) {
      _previewFailed(request);
    } finally {
      if (mounted &&
          !_closing &&
          request == _previewRequest &&
          _previewLoading) {
        setState(() => _previewLoading = false);
      }
    }
  }

  Future<void> _assign(IslamicAudioTrack track) async {
    if (_closing || (!widget.isIqamah && PrayerNotificationService.adhanAssignmentUnavailableReason(track.id) != null) || IslamicAudioService.unavailableRecordingReason(track.id) != null) return;
    setState(() => _closing = true);
    try {
      await _stopPreview();
      if (!mounted) return;
      final notifications = PrayerNotificationService.instance;
      if (widget.onStage != null) {
        widget.onStage!(track.id);
      } else if (widget.isIqamah) {
        await notifications.setSelectedIqamahVoice(track.id);
      } else if (widget.prayerName == 'الكل') {
        await notifications.setAllPrayersVoice(track.id);
      } else {
        await notifications.setPrayerVoice(widget.prayerName, track.id);
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.onStage != null ? 'تم اختيار الصوت. اضغط تطبيق لحفظه.' : 'تم تعيين ${adhanVoiceLabel(track)}: ${widget.prayerName}',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _closing = false;
          _previewError = 'تعذر إيقاف المعاينة أو حفظ الاختيار. أعد المحاولة.';
        });
      }
    }
  }

  @override
  void dispose() {
    _closing = true;
    _disposed = true;
    ++_previewRequest;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_previewState?.cancel().catchError((Object _) {}));
    // Attempt both operations independently so a rejected or delayed stop does
    // not prevent disposal. Neither operation can stop a newer focus owner.
    unawaited(_previewPlayer.stop().catchError((Object _) {}));
    unawaited(_previewPlayer.dispose().catchError((Object _) {}));
    _searchController.dispose();
    super.dispose();
  }

  List<IslamicAudioTrack> _getFilteredTracks() {
    final all = IslamicAudioService.allTracks.where((t) {
      if (widget.isIqamah) {
        return t.type == IslamicAudioType.iqamah;
      } else {
        return t.type == IslamicAudioType.adhan &&
            !t.id.contains('duaa') &&
            !t.id.contains('sharawi');
      }
    }).toList();

    if (_searchQuery.trim().isEmpty) return all;

    final q = _searchQuery.trim().toLowerCase();
    final normQ = ArabicNormalizer.normalize(_searchQuery, loose: true);
    return all.where((t) {
      final matchTitle = t.title.toLowerCase().contains(q) ||
          ArabicNormalizer.normalize(t.title, loose: true).contains(normQ);
      final matchSub = t.subtitle.toLowerCase().contains(q) ||
          ArabicNormalizer.normalize(t.subtitle, loose: true).contains(normQ);
      final matchMuezzin =
          (t.muezzinName?.toLowerCase().contains(q) ?? false) ||
              (t.muezzinName != null &&
                  ArabicNormalizer.normalize(t.muezzinName!, loose: true)
                      .contains(normQ));
      final matchCat = (t.categoryAr?.toLowerCase().contains(q) ?? false) ||
          (t.categoryAr != null &&
              ArabicNormalizer.normalize(t.categoryAr!, loose: true)
                  .contains(normQ));
      return matchTitle || matchSub || matchMuezzin || matchCat;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final audio = IslamicAudioService.instance;
    final notifications = PrayerNotificationService.instance;
    return Focus(
      autofocus: true,
      onFocusChange: (hasFocus) {
        if (!hasFocus) unawaited(_stopPreview().catchError((Object _) {}));
      },
      child: Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: SafeArea(
        child: Container(
          height: MediaQuery.sizeOf(context).height * 0.88,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(children: [
                Expanded(
                    child: Text(
                        widget.isIqamah
                            ? 'صوت الإقامة'
                            : widget.prayerName == 'الكل'
                                ? 'مؤذن لجميع الصلوات'
                                : 'مؤذن ${widget.prayerName}',
                        style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                    tooltip: 'إغلاق',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: const InputDecoration(
                      labelText: 'بحث باسم المؤذن',
                      prefixIcon: Icon(Icons.search))),
            ),
            if (_previewError != null)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Semantics(liveRegion: true, child: Text(_previewError!))),
            Expanded(
                child: AnimatedBuilder(
              animation: Listenable.merge([audio, notifications]),
              builder: (context, _) {
                final tracks = _getFilteredTracks();
                final selected = widget.selectedVoice ?? (widget.isIqamah
                    ? notifications.selectedIqamahVoice
                    : widget.prayerName == 'الكل'
                        ? notifications.selectedAdhanVoice
                        : notifications.getPrayerVoice(widget.prayerName));
                final fallbackNotice = widget.isIqamah ? null : savedAdhanFallbackNotice(selected);
                if (tracks.isEmpty && fallbackNotice == null) {
                  return const Center(child: Text('لا توجد أصوات مطابقة'));
                }
                final noticeCount = fallbackNotice == null ? 0 : 1;
                return ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: tracks.length + noticeCount,
                  itemBuilder: (context, index) {
                    if (noticeCount == 1 && index == 0) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(fallbackNotice!, key: const ValueKey('saved_adhan_fallback_notice')),
                        ),
                      );
                    }
                    final track = tracks[index - noticeCount];
                    return AdhanVoiceOption(
                      key: ValueKey('voice_${track.id}'),
                      name: adhanVoiceLabel(track),
                      semanticName: track.sourceFileNames.isEmpty
                          ? null
                          : '${adhanVoiceLabel(track)}، اسم حسب المصدر غير موثق',
                      sourceDetails: adhanSourceDetails(track),
                      assignmentUnavailableMessage: track.sourceFileNames.isEmpty
                          ? null : 'للاستماع والتحميل فقط',
                      unavailableReason: IslamicAudioService.unavailableRecordingReason(track.id),
                      assignmentUnavailableReason: widget.isIqamah ? null : PrayerNotificationService.adhanAssignmentUnavailableReason(track.id),
                      selected: selected == track.id ||
                          selected == track.rawNotificationSound,
                      playing:
                          _previewTrackId == track.id &&
                              (_previewPlaying || _previewLoading || _previewStopFailed),
                      downloaded:
                          track.isBundled || audio.isDownloaded(track.id),
                      downloading: audio.isDownloading(track.id),
                      onListen: () => _playPreview(track),
                      onAssign: () => _assign(track),
                      onDownload: () async {
                        final ok = await audio.downloadTrack(track.id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(ok
                                ? 'تم التحميل'
                                : 'تعذر التحميل. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.')));
                      },
                    );
                  },
                );
              },
            )),
          ]),
        ),
      ),
    ));
  }
}
