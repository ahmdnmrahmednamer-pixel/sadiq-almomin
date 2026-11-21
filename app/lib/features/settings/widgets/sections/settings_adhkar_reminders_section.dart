import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../../../../core/audio/fast_audio_service.dart';
import 'package:flutter/material.dart';
import '../../../../core/notifications/prayer_notification_service.dart';
import '../../../../core/theme/app_theme.dart';

/// Section: User-customizable Morning, Evening, and Sleep Adhkar Notification Timings
class SettingsAdhkarRemindersSection extends StatelessWidget {
  const SettingsAdhkarRemindersSection({super.key, this.previewPlayerFactory});
  @visibleForTesting
  final AudioPlayer Function()? previewPlayerFactory;

  Future<void> _pickMorningTime(BuildContext context) async {
    final pn = PrayerNotificationService.instance;
    final picked = await showTimePicker(
      context: context,
      initialTime: pn.morningAdhkarTime,
      helpText: 'اختر موعد إشعار أذكار الصباح',
      cancelText: 'إلغاء',
      confirmText: 'حفظ الموعد',
    );
    if (picked != null) {
      await pn.setMorningAdhkarTime(picked.hour, picked.minute);
    }
  }

  Future<void> _pickEveningTime(BuildContext context) async {
    final pn = PrayerNotificationService.instance;
    final picked = await showTimePicker(
      context: context,
      initialTime: pn.eveningAdhkarTime,
      helpText: 'اختر موعد إشعار أذكار المساء',
      cancelText: 'إلغاء',
      confirmText: 'حفظ الموعد',
    );
    if (picked != null) {
      await pn.setEveningAdhkarTime(picked.hour, picked.minute);
    }
  }

  Future<void> _pickSleepTime(BuildContext context) async {
    final pn = PrayerNotificationService.instance;
    final picked = await showTimePicker(
      context: context,
      initialTime: pn.sleepAdhkarTime,
      helpText: 'اختر موعد إشعار أذكار النوم',
      cancelText: 'إلغاء',
      confirmText: 'حفظ الموعد',
    );
    if (picked != null) {
      await pn.setSleepAdhkarTime(picked.hour, picked.minute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pn = PrayerNotificationService.instance;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ReminderSectionHeader(
          title: 'مواقيت وتنبيهات أذكار المسلم',
          icon: Icons.alarm_rounded,
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            'مواعيد تنبيهات الأذكار',
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // 1. بطاقة أذكار الصباح
        _buildAdhkarCard(
          context: context,
          isDark: isDark,
          title: 'أذكار الصباح المباركة',
          subtitle: '',
          icon: Icons.wb_sunny_rounded,
          accentColor: const Color(0xFFD4AF37),
          isEnabled: pn.morningAdhkarEnabled,
          onToggle: (val) => pn.toggleMorningAdhkar(val),
          currentTimeStr: PrayerNotificationService.formatTimeArabic(
            pn.morningAdhkarHour,
            pn.morningAdhkarMinute,
          ),
          onPickTime: () => _pickMorningTime(context),
          presetTimes: const [
            (6, 0, '٠٦:٠٠ ص'),
            (6, 30, '٠٦:٣٠ ص'),
            (7, 0, '٠٧:٠٠ ص'),
            (7, 30, '٠٧:٣٠ ص'),
            (8, 0, '٠٨:٠٠ ص'),
          ],
          onSelectPreset: (h, m) => pn.setMorningAdhkarTime(h, m),
          currentHour: pn.morningAdhkarHour,
          currentMinute: pn.morningAdhkarMinute,
        ),

        const SizedBox(height: 12),

        // 2. بطاقة أذكار المساء
        _buildAdhkarCard(
          context: context,
          isDark: isDark,
          title: 'أذكار المساء المباركة',
          subtitle: '',
          icon: Icons.nights_stay_rounded,
          accentColor: const Color(0xFF1B4332),
          isEnabled: pn.eveningAdhkarEnabled,
          onToggle: (val) => pn.toggleEveningAdhkar(val),
          currentTimeStr: PrayerNotificationService.formatTimeArabic(
            pn.eveningAdhkarHour,
            pn.eveningAdhkarMinute,
          ),
          onPickTime: () => _pickEveningTime(context),
          presetTimes: const [
            (16, 30, '٠٤:٣٠ م'),
            (17, 0, '٠٥:٠٠ م'),
            (17, 30, '٠٥:٣٠ م'),
            (18, 0, '٠٦:٠٠ م'),
            (18, 30, '٠٦:٣٠ م'),
          ],
          onSelectPreset: (h, m) => pn.setEveningAdhkarTime(h, m),
          currentHour: pn.eveningAdhkarHour,
          currentMinute: pn.eveningAdhkarMinute,
        ),

        const SizedBox(height: 12),

        // 3. بطاقة أذكار النوم
        _buildAdhkarCard(
          context: context,
          isDark: isDark,
          title: 'أذكار وسنن النوم',
          subtitle: '',
          icon: Icons.hotel_rounded,
          accentColor: const Color(0xFF4A6B82),
          isEnabled: pn.sleepAdhkarEnabled,
          onToggle: (val) => pn.toggleSleepAdhkar(val),
          currentTimeStr: PrayerNotificationService.formatTimeArabic(
            pn.sleepAdhkarHour,
            pn.sleepAdhkarMinute,
          ),
          onPickTime: () => _pickSleepTime(context),
          presetTimes: const [
            (21, 30, '٠٩:٣٠ م'),
            (22, 0, '١٠:٠٠ م'),
            (22, 30, '١٠:٣٠ م'),
            (23, 0, '١١:٠٠ م'),
            (23, 30, '١١:٣٠ م'),
          ],
          onSelectPreset: (h, m) => pn.setSleepAdhkarTime(h, m),
          currentHour: pn.sleepAdhkarHour,
          currentMinute: pn.sleepAdhkarMinute,
        ),

        const SizedBox(height: 12),
        _ShortAudioReminders(previewPlayerFactory: previewPlayerFactory),
        const Divider(),
      ],
    );
  }

  Widget _buildAdhkarCard({
    required BuildContext context,
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required bool isEnabled,
    required ValueChanged<bool> onToggle,
    required String currentTimeStr,
    required VoidCallback onPickTime,
    required List<(int, int, String)> presetTimes,
    required void Function(int, int) onSelectPreset,
    required int currentHour,
    required int currentMinute,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: isDark ? const Color(0xFF1E2824) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isEnabled
                ? AppColors.accentGold.withValues(alpha: 0.5)
                : Colors.grey.withValues(alpha: 0.2),
            width: isEnabled ? 1.5 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.04),
        child: Column(
          children: [
            SwitchListTile(
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.accentGold, size: 22),
              ),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
              ),
              subtitle: subtitle.isEmpty ? null : Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              value: isEnabled,
              activeThumbColor: AppColors.accentGold,
              activeTrackColor: AppColors.primaryGreen,
              onChanged: onToggle,
            ),
          if (isEnabled) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Icon(Icons.access_time_filled_rounded, size:18, color: isDark ? const Color(0xFF77D4B2) : AppColors.primaryGreen),
                    const Text('الموعد:', style:TextStyle(fontSize:13,fontWeight:FontWeight.w700)),
                    Text(currentTimeStr, style:TextStyle(fontWeight:FontWeight.w900,fontSize:13.5,color:isDark ? const Color(0xFF77D4B2) : AppColors.primaryGreen)),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.edit_calendar_rounded, size: 15),
                        label: const Text('تغيير الوقت',
                            style: TextStyle(fontSize: 12)),
                        onPressed: onPickTime,
                      ),
                  ]),
                  const SizedBox(height: 10),
                  const Text(
                    'مواعيد شائعة مقترحة:',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: presetTimes.map((preset) {
                        final isSelected =
                            currentHour == preset.$1 && currentMinute == preset.$2;
                        return Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: ChoiceChip(
                            label: Text(preset.$3),
                            selected: isSelected,
                            selectedColor: AppColors.accentGold.withValues(alpha: 0.25),
                            labelStyle: TextStyle(
                              fontSize: 11.5,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? AppColors.primaryGreen
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                            side: BorderSide(
                              color: isSelected
                                  ? AppColors.accentGold
                                  : Colors.grey.withValues(alpha: 0.3),
                            ),
                            onSelected: (_) =>
                                onSelectPreset(preset.$1, preset.$2),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
}

class _ReminderSectionHeader extends StatelessWidget {
  const _ReminderSectionHeader({required this.title,required this.icon});
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final color=Theme.of(context).brightness==Brightness.dark?const Color(0xFF77D4B2):AppColors.primaryGreen;
    return Padding(padding:const EdgeInsets.fromLTRB(16,18,16,8),child:Semantics(header:true,child:Row(children:[Icon(icon,color:color,size:20),const SizedBox(width:10),Expanded(child:Text(title,style:TextStyle(fontSize:16,fontWeight:FontWeight.w900,color:color)))])));
  }
}

String _frequencyLabel(ShortReminderFrequency value) => switch(value) {
  ShortReminderFrequency.off => 'إيقاف',
  ShortReminderFrequency.halfHourly => 'كل ٣٠ دقيقة',
  ShortReminderFrequency.hourly => 'كل ساعة',
  ShortReminderFrequency.twoHourly => 'كل ساعتين',
  ShortReminderFrequency.daily => 'كل ٢٤ ساعة',
  ShortReminderFrequency.custom => 'مدة مخصصة',
};

class _ShortAudioReminders extends StatelessWidget {
  const _ShortAudioReminders({this.previewPlayerFactory});
  final AudioPlayer Function()? previewPlayerFactory;
  @override
  Widget build(BuildContext context) {
    final service = PrayerNotificationService.instance;
    return AnimatedBuilder(
        animation: service,
        builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _ReminderSectionHeader(
                    title: 'التذكير الصوتي القصير',
                    icon: Icons.notifications_active_outlined),
                const Padding(padding:EdgeInsets.all(16),child:Text('إشعارات بصوت قصير. قد تتأخر أو تصمت حسب إعدادات الجهاز.')),
                const ExpansionTile(title:Text('الصوت والتوقيت'),children:[Padding(padding:EdgeInsets.all(16),child:Text('ليست أذكاراً كاملة. التوقيت يديره الجهاز. الصوت يتبع إذن الإشعارات وإعدادات القناة والصامت وعدم الإزعاج. تغيير التكرار لا يغيّر صوت قناة سبق إنشاؤها.'))]),
                if (!service.masterEnabled)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'التنبيهات العامة مغلقة. لن تُجدول هذه التذكيرات حتى تفتحها.')),
                for (final key
                    in PrayerNotificationService.shortReminderIds.keys)
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                                key == 'salawat'
                                    ? 'الصلاة على النبي'
                                    : 'الاستغفار والحوقلة',
                                style: Theme.of(context).textTheme.titleMedium),
                            if (service.shortFrequency(key) == ShortReminderFrequency.custom)
                              Text('التكرار المخصص: كل ${service.shortInterval(key).minutes} دقيقة. يمكن تعديله من الإعدادات الرئيسية.'),
                            Wrap(spacing: 8, children: [
                              for (final value in ShortReminderFrequency.values.where((value) => value != ShortReminderFrequency.custom))
                                ChoiceChip(
                                    label: Text(_frequencyLabel(value), semanticsLabel: '${key == 'salawat' ? 'الصلاة على النبي' : 'الاستغفار والحوقلة'}، ${_frequencyLabel(value)}'),
                                    selected:
                                        service.shortFrequency(key) == value,
                                    onSelected: service.shortReminderBusy
                                        ? null
                                        : (_) async {
                                            try {
                                              await service
                                                  .setShortReminderFrequency(
                                                      key, value);
                                            } catch (_) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(const SnackBar(
                                                        content: Text(
                                                            'تعذر حفظ التكرار. أعد المحاولة.')));
                                              }
                                            }
                                          }),
                            ]),
                            if (service.shortReminderBusy)
                              const Text('جاري تحديث التذكير...'),
                            if (service.shortReminderError(key) != null) ...[
                              Text(service.shortReminderError(key)!,
                                  semanticsLabel:
                                      service.shortReminderError(key)),
                              TextButton(
                                  onPressed: service.shortReminderBusy
                                      ? null
                                      : service.scheduleShortReminders,
                                  child: const Text('إعادة محاولة التحديث')),
                            ],
                            OutlinedButton.icon(
                                onPressed: () => showDialog<void>(
                                    context: context,
                                    builder: (_) => _ShortReminderPreview(
                                        reminderKey: key, player: previewPlayerFactory?.call())),
                                icon: const Icon(Icons.headphones),
                                label: const Text('استماع إلى الصوت')),
                          ])),
              ],
            ));
  }
}

class _ShortReminderPreview extends StatefulWidget {
  const _ShortReminderPreview({required this.reminderKey, this.player});
  final AudioPlayer? player;
  final String reminderKey;
  @override
  State<_ShortReminderPreview> createState() => _ShortReminderPreviewState();
}

class _ShortReminderPreviewState extends State<_ShortReminderPreview> with WidgetsBindingObserver {
  bool _routeCurrent = true;
  bool _disposed = false;
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (_routeCurrent && !isCurrent) unawaited(_stop());
    _routeCurrent = isCurrent;
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) { if(state != AppLifecycleState.resumed) unawaited(_stop()); }
  late final AudioPlayer _player = widget.player ?? AudioPlayer();
  int _generation = 0;
  bool _busy = false;
  bool _stopFailed = false;
  String? _error;
  Future<void>? _pendingStop;
  Future<void> _stop() {
    if (_disposed) return Future<void>.value();
    final pending = _pendingStop;
    if (pending != null) return pending;
    final generation = ++_generation;
    if (mounted) setState(() => _busy = true);
    return _pendingStop = _performStop(generation).whenComplete(() {
      _pendingStop = null;
    });
  }

  Future<void> _performStop(int generation) async {
    try {
      await _player.stop();
      if (mounted && generation == _generation) {
        setState(() {
          _stopFailed = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _stopFailed = true;
          _error = 'تعذر إيقاف المعاينة. أعد محاولة الإيقاف.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _play() async {
    if (_busy || _pendingStop != null || _stopFailed) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final focus = FastAudioService.instance;
      final token =
          await focus.claimAudioFocus(player: _player, onStopOther: _stop);
      if (!mounted ||
          generation != _generation ||
          focus.activePlaybackToken != token) {
        return;
      }
      await _player.setAsset('assets/audio/reminder_${widget.reminderKey}.mp3');
      if (!mounted ||
          generation != _generation ||
          focus.activePlaybackToken != token) {
        return;
      }
      await _player.play();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = 'تعذر تشغيل المعاينة.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_player.stop().catchError((Object _) {}));
    unawaited(_player.dispose().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(autofocus:true,onFocusChange:(hasFocus) { if(!hasFocus) unawaited(_stop()); }, child:AlertDialog(
        title: Text(widget.reminderKey == 'salawat'
            ? 'الصلاة على النبي'
            : 'الاستغفار والحوقلة'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('معاينة فقط، لا تغيّر التذكير.'),
          if (_error != null) Text(_error!),
          TextButton.icon(
              onPressed: _busy || _stopFailed ? null : _play,
              icon: const Icon(Icons.play_arrow),
              label: const Text('تشغيل المعاينة')),
          TextButton.icon(
              onPressed: _pendingStop == null ? _stop : null,
              icon: const Icon(Icons.stop),
              label: const Text('إيقاف المعاينة')),
        ])),
        actions: [
          TextButton(
              onPressed: _pendingStop != null ? null : () async {
                await _stop();
                if (context.mounted && _error == null) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('إغلاق'))
        ],
      ));
}

void showShortReminderPreview(BuildContext context, String key) {
  showDialog<void>(context: context, builder: (_) => _ShortReminderPreview(reminderKey: key));
}
