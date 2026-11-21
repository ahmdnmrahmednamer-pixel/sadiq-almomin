import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../../core/audio/fast_audio_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/localization/app_localizations.dart';
import 'package:flutter/material.dart';
import '../../core/services/fajr_qiyam_alarm_service.dart';
import '../../core/services/islamic_audio_service.dart';
import '../../core/services/prayer_service.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/prayer_location_banner.dart';
import '../../core/ui/app_dropdown_field.dart';

/// شاشة ضبط «منبّه الاستعداد لصلاة الفجر ومنبّه قيام الليل الذكي»
class FajrQiyamAlarmScreen extends StatefulWidget {
  const FajrQiyamAlarmScreen({super.key, this.previewPlayerFactory});

  @visibleForTesting
  final AudioPlayer Function()? previewPlayerFactory;

  @override
  State<FajrQiyamAlarmScreen> createState() => _FajrQiyamAlarmScreenState();
}

class _FajrQiyamAlarmScreenState extends State<FajrQiyamAlarmScreen> {
  final FajrQiyamAlarmService _alarmService = FajrQiyamAlarmService.instance;
  final IslamicAudioService _audioService = IslamicAudioService.instance;
  @override
  void initState() {
    super.initState();
    _alarmService.init();
  }

  Future<void> _pickTone({required bool isQiyam}) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => _AlarmTonePicker(
        isQiyam: isQiyam,
        savedId:
            isQiyam ? _alarmService.qiyamToneId : _alarmService.preFajrToneId,
        playerFactory: widget.previewPlayerFactory,
      ),
    );
    if (chosen == null || !mounted) return;
    try {
      if (isQiyam) {
        if (!await _alarmService.setQiyamTone(chosen)) return;
      } else {
        if (!await _alarmService.setPreFajrTone(chosen)) return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_alarmService.schedulingError == null
            ? 'تم حفظ نغمة المنبّه'
            : 'حُدث اختيار النغمة، لكن تعذر تحديث التنبيه. راجع التحذير وأعد المحاولة.'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر إتمام حفظ النغمة. راجع إعداد المنبّه.'),
      ));
    }
  }

  Widget _toneChoice({required bool isQiyam, required String selectedId}) {
    final tone = _alarmService.getToneById(selectedId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tone.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: ValueKey(isQiyam ? 'qiyam-tone-picker' : 'fajr-tone-picker'),
          onPressed: () => _pickTone(isQiyam: isQiyam),
          icon: const ExcludeSemantics(child: Icon(Icons.music_note_rounded)),
          label: Text(isQiyam ? 'اختيار نغمة قيام الليل' : 'اختيار نغمة الفجر'),
        ),
      ],
    );
  }

  Future<void> _pickFixedQiyamTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _alarmService.qiyamFixedHour,
        minute: _alarmService.qiyamFixedMinute,
      ),
      helpText: 'اختر موعد الاستيقاظ لقيام الليل',
    );
    if (picked != null) {
      await _alarmService.setQiyamFixedTime(picked.hour, picked.minute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('dawn_awakening')),
          actions: [
            IconButton(
              tooltip: 'إيقاف الصوت الحالي',
              icon: const Icon(Icons.volume_off_rounded),
              onPressed: () async {
                await _audioService.stop();
                if (!mounted) return;
                await _audioService.stopSfx();
                if (!mounted) return;
              },
            ),
          ],
        ),
        body: AnimatedBuilder(
          animation: Listenable.merge([
            _alarmService,
            PrayerService.instance,
            _audioService,
          ]),
          builder: (context, _) {
            final prayerData = PrayerService.instance.currentData;
            final nextFajr = _alarmService.getNextFajrTime(prayerData);
            final nextPreFajrWake =
                _alarmService.getNextPreFajrWakeTime(prayerData);
            final nextQiyamWake =
                _alarmService.getNextQiyamWakeTime(prayerData);
            final lastThirdStart =
                _alarmService.getLastThirdOfNightStart(prayerData);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_alarmService.preferenceError != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_alarmService.preferenceError!,
                          style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_alarmService.schedulingError != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(_alarmService.schedulingError!,
                              style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              key: const ValueKey('retry-wakeup-scheduling'),
                              onPressed: () async { await _alarmService.retryScheduling(); },
                              icon: const ExcludeSemantics(child: Icon(Icons.refresh)),
                              label: const Text('إعادة محاولة تحديث المنبّهات'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Top Live Astronomical Times Summary Banner
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0B3B2D), Color(0xFF172738)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.accentGold.withValues(alpha: 0.5),
                      width: 1.4,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.alarm_on_rounded,
                            color: AppColors.accentGold,
                            size: 28,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'مواقيت الاستيقاظ المحسوبة تلقائياً لموقعك',
                              style: TextStyle(
                                fontFamily: 'Amiri',
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (prayerData == null) ...[
                        Text(
                          GpsLocationActionControls.describeUnavailableReason(
                            PrayerService.instance,
                          ),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const GpsLocationActionControls(onDarkSurface: true),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: _buildTimeStatBox(
                              label: 'موعد أذان الفجر القادم',
                              timeStr: nextFajr != null
                                  ? _alarmService.formatTimeAr(nextFajr)
                                  : 'حدّث المواقيت',
                              icon: Icons.wb_twilight_rounded,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildTimeStatBox(
                              label: 'منبّه الاستعداد للفجر',
                              timeStr: !_alarmService.preFajrEnabled
                                  ? 'متوقف'
                                  : (nextPreFajrWake != null
                                      ? _alarmService
                                          .formatTimeAr(nextPreFajrWake)
                                      : 'حدّث المواقيت'),
                              icon: Icons.notifications_active_rounded,
                              highlight: _alarmService.preFajrEnabled &&
                                  nextPreFajrWake != null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildTimeStatBox(
                              label: 'منبّه قيام الليل',
                              timeStr: !_alarmService.qiyamEnabled
                                  ? 'متوقف'
                                  : (nextQiyamWake != null
                                      ? _alarmService
                                          .formatTimeAr(nextQiyamWake)
                                      : 'حدّث المواقيت'),
                              icon: Icons.nights_stay_rounded,
                              highlight: _alarmService.qiyamEnabled &&
                                  nextQiyamWake != null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // SECTION 1: Pre-Fajr Wake-Up Alarm Card
                _buildPreFajrSectionCard(isDark, nextPreFajrWake),
                const SizedBox(height: 18),

                // SECTION 2: Qiyam Al-Layl Wake-Up Alarm Card
                _buildQiyamSectionCard(isDark, nextQiyamWake, lastThirdStart),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTimeStatBox({
    required String label,
    required String timeStr,
    required IconData icon,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.accentGold.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? AppColors.accentGold : Colors.white24,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.accentGold, size: 18),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10.5, color: Colors.white70),
          ),
          const SizedBox(height: 3),
          Text(
            timeStr,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreFajrSectionCard(bool isDark, DateTime? nextPreFajrWake) {
    final mins = _alarmService.preFajrMinutesBefore;
    final selectedToneId = _alarmService.preFajrToneId;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: isDark ? AppTheme.darkCard : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.wb_twilight_rounded,
                    color: AppColors.primaryGreen,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '١. منبّه الاستيقاظ والاستعداد قبل صلاة الفجر',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        nextPreFajrWake != null
                            ? 'يوقظك قبل الفجر بـ $mins دقيقة (${_alarmService.formatTimeAr(nextPreFajrWake)}) لتتوضأ وتدرك الصلاة في وقتها'
                            : 'موعد المنبّه غير متاح. حدّث موقع الصلاة ومواقيتها؛ لن يُجدول هذا المنبّه حتى تتوفر مواقيت قادمة.',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _alarmService.preFajrEnabled,
                  activeThumbColor: AppColors.primaryGreen,
                  onChanged: (v) => _alarmService.setPreFajrEnabled(v),
                ),
              ],
            ),
            const Divider(height: 24),
            const Text(
              'حدد الوقت قبل أذان الفجر (بالدقائق):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            const SizedBox(height: 8),
            AppDropdownField<int>(
              label: 'اختر مدة الاستيقاظ قبل أذان الفجر',
              value:
                  [10, 15, 20, 25, 30, 45, 60, 90].contains(mins) ? mins : 30,
              dense: true,
              prefixIcon: Icons.alarm_on_rounded,
              options: [10, 15, 20, 25, 30, 45, 60, 90]
                  .map((m) => AppDropdownOption<int>(
                        value: m,
                        label: 'قبل صلاة الفجر بـ $m دقيقة',
                      ))
                  .toList(),
              onChanged: (m) => _alarmService.setPreFajrMinutesBefore(m),
            ),
            Slider(
              value: mins.toDouble().clamp(5.0, 120.0),
              min: 5,
              max: 120,
              divisions: 23,
              activeColor: AppColors.primaryGreen,
              label: '$mins دقيقة قبل الفجر',
              onChanged: (val) =>
                  _alarmService.setPreFajrMinutesBefore(val.round()),
            ),
            const SizedBox(height: 8),
            _toneChoice(isQiyam: false, selectedId: selectedToneId),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.notifications_active_rounded),
                label: const Text(
                  'تجربة رنين منبّه الاستعداد للفجر الآن',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () =>
                    _alarmService.triggerImmediateTestAlarm(isQiyam: false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQiyamSectionCard(
    bool isDark,
    DateTime? nextQiyamWake,
    DateTime? lastThirdStart,
  ) {
    final mode = _alarmService.qiyamMode;
    final selectedToneId = _alarmService.qiyamToneId;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: isDark ? AppTheme.darkCard : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accentGold.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.nights_stay_rounded,
                    color: AppColors.accentGold,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '٢. منبّه قيام الليل والتهجد (الثلث الأخير)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        nextQiyamWake != null
                            ? (lastThirdStart != null
                                ? 'موعد التنبيه القادم: ${_alarmService.formatTimeAr(nextQiyamWake)} (بداية الثلث الأخير: ${_alarmService.formatTimeAr(lastThirdStart)})'
                                : 'موعد التنبيه الثابت القادم: ${_alarmService.formatTimeAr(nextQiyamWake)}')
                            : 'موعد المنبّه غير متاح. حدّث موقع الصلاة ومواقيتها، أو اختر وقتاً ثابتاً. لا يُجدول الموعد المحسوب دون مواقيت قادمة.',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _alarmService.qiyamEnabled,
                  activeThumbColor: AppColors.accentGold,
                  onChanged: (v) => _alarmService.setQiyamEnabled(v),
                ),
              ],
            ),
            const Divider(height: 24),
            const Text(
              'نظام تحديد وقت الاستيقاظ لقيام الليل:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            const SizedBox(height: 8),
            AppDropdownField<String>(
              label: 'نظام تحديد وقت الاستيقاظ لقيام الليل',
              value: mode,
              dense: true,
              prefixIcon: Icons.nights_stay_rounded,
              options: const [
                AppDropdownOption(
                  value: 'last_third',
                  label: 'بداية الثلث الأخير من الليل تلقائياً',
                ),
                AppDropdownOption(
                  value: 'before_fajr',
                  label: 'قبل أذان الفجر بمدة محددة ⏳',
                ),
                AppDropdownOption(
                  value: 'fixed_time',
                  label: 'وقت ثابت أختاره بنفسي ⏰',
                ),
              ],
              onChanged: (val) => _alarmService.setQiyamMode(val),
            ),
            const SizedBox(height: 12),
            if (mode == 'before_fajr') ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [45, 60, 75, 90, 120].map((m) {
                  final sel = _alarmService.qiyamMinutesBeforeFajr == m;
                  return ChoiceChip(
                    label: Text('قبل الفجر بـ $m دقيقة'),
                    selected: sel,
                    selectedColor: AppColors.accentGold,
                    onSelected: (_) =>
                        _alarmService.setQiyamMinutesBeforeFajr(m),
                  );
                }).toList(),
              ),
            ] else if (mode == 'fixed_time') ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule_rounded),
                label: Text(
                  'الوقت المحدد: ${_alarmService.qiyamFixedHour.toString().padLeft(2, '0')}:${_alarmService.qiyamFixedMinute.toString().padLeft(2, '0')} ص — اضغط للتغيير',
                ),
                onPressed: _pickFixedQiyamTime,
              ),
            ],
            const SizedBox(height: 12),
            _toneChoice(isQiyam: true, selectedId: selectedToneId),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryGreen,
                  side: const BorderSide(color: AppColors.primaryGreen),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.nights_stay_rounded),
                label: const Text(
                  'تجربة رنين منبّه قيام الليل الآن',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () =>
                    _alarmService.triggerImmediateTestAlarm(isQiyam: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draft tone selection. This route owns only its preview player, never the
/// scheduler or saved preferences. It never stops the global focus owner on exit.
class _AlarmTonePicker extends StatefulWidget {
  const _AlarmTonePicker({
    required this.isQiyam,
    required this.savedId,
    this.playerFactory,
  });
  final bool isQiyam;
  final String savedId;
  final AudioPlayer Function()? playerFactory;

  @override
  State<_AlarmTonePicker> createState() => _AlarmTonePickerState();
}

class _AlarmTonePickerState extends State<_AlarmTonePicker>
    with WidgetsBindingObserver {
  late final AudioPlayer _player;
  late String _draftId;
  String? _previewId;
  StreamSubscription<PlayerState>? _stateSubscription;
  bool _routeCurrent = true;
  int _request = 0;
  bool _loading = false;
  bool _playing = false;
  bool _closing = false;
  bool _disposed = false;
  bool _stopFailed = false;
  Future<void> _pendingStop = Future<void>.value();
  Future<void> _pendingLoad = Future<void>.value();
  String? _error;

  bool get _hasPreviewToStop =>
      (_previewId == _draftId && (_loading || _playing)) || _stopFailed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _draftId = widget.savedId;
    _player = widget.playerFactory?.call() ?? AudioPlayer();
    _stateSubscription = _player.playerStateStream.listen((state) {
      if (!mounted || _closing) return;
      setState(() {
        _playing = state.playing &&
            state.processingState != ProcessingState.completed &&
            state.processingState != ProcessingState.idle;
      });
    },
        // State-stream errors have no request identity. just_audio already filters
        // these; the captured load/play futures handle each request's own failures.
        onError: (Object error, StackTrace stack) {});
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

  Future<void> _stopPreview() {
    if (_disposed) return Future<void>.value();
    final request = ++_request;
    if (mounted && !_closing) setState(() => _loading = false);
    // Stop only our player, never a newer global audio owner.
    _pendingStop = _pendingStop.catchError((Object _) {}).then((_) async {
      if (_disposed) return;
      try {
        await _player.stop();
        if (mounted && !_closing && request == _request) {
          setState(() {
            _playing = false;
            _stopFailed = false;
          });
        }
      } catch (_) {
        if (mounted && !_closing && request == _request) {
          setState(() {
            _playing = _player.playing;
            _stopFailed = true;
            _error = 'تعذر إيقاف المعاينة. أعد محاولة الإيقاف.';
          });
        }
        rethrow;
      }
    });
    return _pendingStop;
  }

  void _previewFailed(int request) {
    if (!mounted || _closing || request != _request) return;
    setState(() {
      _error = 'تعذر تشغيل النغمة. يمكنك المحاولة مجدداً أو اختيار نغمة أخرى.';
      _loading = false;
    });
    unawaited(_stopPreview().catchError((Object _) {}));
  }

  Future<void> _preview() async {
    if (_closing) return;
    if (_hasPreviewToStop) {
      try {
        await _stopPreview();
      } catch (_) {
        // _stopPreview keeps the Stop retry and the specific error visible.
      }
      return;
    }
    final stopped = _stopPreview();
    final request = _request;
    final selectedId = _draftId;
    _previewId = selectedId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await stopped;
      await _pendingLoad.catchError((Object _) {});
      if (!mounted || _closing || request != _request) return;
      final token = await FastAudioService.instance.claimAudioFocus(
        player: _player,
        onStopOther: _stopPreview,
      );
      if (!mounted ||
          _closing ||
          request != _request ||
          token != FastAudioService.instance.activePlaybackToken) {
        return;
      }
      final String asset;
      if (selectedId == 'approaching_fajr') {
        // This catalog entry uses the existing spoken reminder rather than its
        // fallback trackId (adhan_fajr). Match the service's real preview source.
        asset = 'assets/audio/approaching_fajr.mp3';
      } else {
        asset = IslamicAudioService.allTracks
            .firstWhere((track) =>
                track.id ==
                FajrQiyamAlarmService.instance.getToneById(selectedId).trackId)
            .assetPath!;
      }
      _pendingLoad = _player.setAsset(asset).then<void>((_) {});
      await _pendingLoad;
      if (!mounted ||
          _closing ||
          request != _request ||
          token != FastAudioService.instance.activePlaybackToken) {
        return;
      }
      setState(() => _loading = false);
      unawaited(_player.play().catchError((Object _) {
        _previewFailed(request);
      }));
    } catch (_) {
      if (!_stopFailed) _previewFailed(request);
    } finally {
      if (mounted && !_closing && request == _request && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _finish(String? result) async {
    if (_closing) return;
    setState(() => _closing = true);
    try {
      await _stopPreview();
    } catch (_) {
      if (result != null) {
        if (mounted) {
          setState(() {
            _closing = false;
            _stopFailed = true;
            _playing = _player.playing;
            _error = 'تعذر إيقاف المعاينة. أعد محاولة الإيقاف ثم احفظ.';
          });
        }
        return;
      }
      // Cancel can still dismiss: disposal independently attempts stop/dispose.
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _closing = true;
    _disposed = true;
    ++_request;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stateSubscription?.cancel().catchError((Object _) {}));
    unawaited(_player.stop().catchError((Object _) {}));
    unawaited(_player.dispose().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text(widget.isQiyam ? 'نغمة قيام الليل' : 'نغمة الفجر'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                    'اختر النغمة واستمع إليها، ثم اضغط حفظ. الاستماع لا يغير إعداداتك.'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const ValueKey('alarm-tone-dropdown'),
                  initialValue: _draftId,
                  isExpanded: true,
                  itemHeight: null,
                  decoration: const InputDecoration(
                      labelText: 'النغمة', border: OutlineInputBorder()),
                  selectedItemBuilder: (context) => FajrQiyamAlarmService
                      .availableTones
                      .map((tone) => Text(tone.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis))
                      .toList(),
                  items: FajrQiyamAlarmService.availableTones
                      .map((tone) => DropdownMenuItem(
                          value: tone.id,
                          child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(tone.title))))
                      .toList(),
                  onChanged: _closing
                      ? null
                      : (id) {
                          if (id == null) return;
                          unawaited(_stopPreview().catchError((Object _) {}));
                          setState(() {
                            _draftId = id;
                            _error = null;
                          });
                        },
                ),
                const SizedBox(height: 8),
                ExcludeSemantics(
                    child: Text(FajrQiyamAlarmService.instance
                        .getToneById(_draftId)
                        .title)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('alarm-tone-preview'),
                  onPressed: _closing ? null : _preview,
                  icon: Icon(_hasPreviewToStop ? Icons.stop : Icons.volume_up),
                  label: Text(
                      _hasPreviewToStop ? 'إيقاف الاستماع' : 'الاستماع للنغمة'),
                ),
                if (_loading)
                  Semantics(
                      liveRegion: true, child: const Text('جار تحميل النغمة')),
                if (_error != null)
                  Semantics(liveRegion: true, child: Text(_error!)),
              ],
            ),
          ),
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
              onPressed: _closing ? null : () => _finish(null),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: _closing ? null : () => _finish(_draftId),
              child: const Text('حفظ')),
        ],
      ),
    );
  }
}
