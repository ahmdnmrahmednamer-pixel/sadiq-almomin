import '../../../core/ui/app_dropdown_field.dart';
import 'package:flutter/material.dart';
import '../../../core/notifications/prayer_notification_service.dart';
import '../../../core/services/islamic_audio_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../settings/widgets/settings_adhan_voice_modal.dart';

/// بطاقة اختيار وتخصيص مؤذن لكل صلاة من الصلوات الخمس
/// تتيح للمستخدم الاستماع المسبق لصوت كل شيخ قبل اعتماده،
/// مع قوائم منسدلة واضحة وخيارات متكاملة بدون أي تعقيد.
class PrayerMuezzinSelectorCard extends StatefulWidget {
  final bool isDark;

  const PrayerMuezzinSelectorCard({super.key, required this.isDark});

  @override
  State<PrayerMuezzinSelectorCard> createState() => _PrayerMuezzinSelectorCardState();
}

class _PrayerMuezzinSelectorCardState extends State<PrayerMuezzinSelectorCard> {
  String? _currentlyPlayingKey;

  final List<Map<String, dynamic>> _prayers = [
    {
      'name': 'الفجر',
      'icon': Icons.nights_stay_rounded,
      'color': const Color(0xFF1E293B),
      'subtitle': 'نداء الصلاة خير من النوم',
    },
    {
      'name': 'الظهر',
      'icon': Icons.wb_sunny_rounded,
      'color': const Color(0xFFD97706),
      'subtitle': 'دخول وقت فريضة الظهر',
    },
    {
      'name': 'العصر',
      'icon': Icons.wb_twilight_rounded,
      'color': const Color(0xFFEA580C),
      'subtitle': 'الصلاة الوسطى',
    },
    {
      'name': 'المغرب',
      'icon': Icons.mode_night_rounded,
      'color': const Color(0xFFDC2626),
      'subtitle': 'حلول المساء والإفطار',
    },
    {
      'name': 'العشاء',
      'icon': Icons.dark_mode_rounded,
      'color': const Color(0xFF4338CA),
      'subtitle': 'ختام صلوات اليوم المفروضة',
    },
  ];

  @override
  void dispose() {
    IslamicAudioService.instance.stop();
    super.dispose();
  }

  Future<void> _playPreview(String voiceKey) async {
    final audio = IslamicAudioService.instance;
    final track = IslamicAudioService.allTracks.firstWhere(
      (t) => t.id == voiceKey || t.rawNotificationSound == voiceKey,
      orElse: () => IslamicAudioService.allTracks.first,
    );

    if (_currentlyPlayingKey == track.id && audio.isPlaying) {
      await audio.stop();
      if (mounted) setState(() => _currentlyPlayingKey = null);
    } else {
      if (mounted) setState(() => _currentlyPlayingKey = track.id);
      await audio.playTrack(track);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifService = PrayerNotificationService.instance;
    final audioService = IslamicAudioService.instance;

    return AnimatedBuilder(
      animation: Listenable.merge([notifService, audioService]),
      builder: (context, _) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF15221B) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.primaryGreen.withValues(alpha: 0.25),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: widget.isDark ? 0.25 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Banner
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primaryGreen, AppColors.secondaryGreen],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryGreen.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.record_voice_over_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'اختيار مؤذن لكل صلاة 🕌',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primaryGreen,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'اختر الشيخ المناسب واستمع لصوته أولاً قبل الاختيار',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: widget.isDark ? Colors.white70 : AppColors.mutedText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Quick Action: Unified Muezzin Pill
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    showPrayerMuezzinDropdownPicker(context, 'الكل');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.accentGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_awesome_rounded, color: AppColors.accentGold, size: 16),
                            SizedBox(width: 8),
                            Text(
                              'هل تريد تعميم شيخ واحد لجميع الصلوات؟',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Text(
                              'تطبيق للكل ▾',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // The 5 Prayer Cards with Dropdown & Preview
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  children: _prayers.map((prayer) {
                    final name = prayer['name'] as String;
                    final currentVoiceKey = notifService.getPrayerVoice(name);
                    final currentVoiceName = getAdhanVoiceName(currentVoiceKey);
                    final isPlaying = _currentlyPlayingKey == currentVoiceKey && audioService.isPlaying;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: widget.isDark ? const Color(0xFF1B2A22) : const Color(0xFFF8FAF9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isPlaying
                              ? AppColors.accentGold
                              : (widget.isDark ? Colors.white12 : Colors.grey.shade300),
                          width: isPlaying ? 1.6 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Prayer Row: Icon, Name, and Selected Voice Name
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: (prayer['color'] as Color).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  prayer['icon'] as IconData,
                                  color: prayer['color'] as Color,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'صلاة $name',
                                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '(${prayer['subtitle']})',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: widget.isDark ? Colors.white54 : AppColors.mutedText,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      currentVoiceName,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: widget.isDark ? AppColors.softGold : AppColors.primaryGreen,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          // Dropdown selector with direct audio sample preview
                          AppAudioDropdownField<String>(
                            label: 'اختر مؤذن صلاة $name',
                            value: IslamicAudioService.allTracks
                                    .where((t) => t.type == IslamicAudioType.adhan && !t.id.contains('duaa') && !t.id.contains('sharawi'))
                                    .any((t) => t.id == currentVoiceKey)
                                ? currentVoiceKey
                                : IslamicAudioService.allTracks
                                    .where((t) => t.type == IslamicAudioType.adhan && !t.id.contains('duaa') && !t.id.contains('sharawi'))
                                    .first
                                    .id,
                            dense: true,
                            prefixIcon: Icons.mosque_rounded,
                            isPlaying: isPlaying,
                            previewButtonLabel: 'استماع',
                            previewTooltip: 'استماع عينة أذان صلاة $name',
                            options: IslamicAudioService.allTracks
                                .where((t) => t.type == IslamicAudioType.adhan && !t.id.contains('duaa') && !t.id.contains('sharawi'))
                                .map((t) => AppDropdownOption<String>(
                                      value: t.id,
                                      label: t.title,
                                    ))
                                .toList(),
                            onChanged: (newVoiceId) async {
                              await notifService.setPrayerCustomVoice(name, newVoiceId);
                              if (audioService.isPlaying) {
                                _playPreview(newVoiceId);
                              }
                            },
                            onPreviewPressed: () => _playPreview(currentVoiceKey),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }
}
