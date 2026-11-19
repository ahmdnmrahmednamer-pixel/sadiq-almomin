import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/notifications/prayer_notification_service.dart';
import '../../../../core/services/adhan_sensor_gesture_service.dart';
import '../../../../core/services/islamic_audio_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_dropdown_field.dart';
import '../../../prayer/adhan_control_screen.dart';
import '../settings_adhan_voice_modal.dart';
import 'settings_section_header.dart';

/// Refactored Section 4: Adhan, Muezzins, Alerts & Smart Sensors
class SettingsAdhanAndSensorsSection extends StatelessWidget {
  const SettingsAdhanAndSensorsSection({super.key});

  void _showPreReminderPicker(BuildContext context) {
    final pn = PrayerNotificationService.instance;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Directionality(
        textDirection: SettingsService.instance.textDirection,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timer_rounded,
                      color: AppColors.primaryGreen, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'تعديل دقائق التنبيه المسبق',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryGreen),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...[5, 10, 15, 20, 30].map((min) {
                final isSelected = pn.preReminderMinutes == min;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Material(
                    color: isSelected
                        ? AppColors.primaryGreen.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.accentGold
                              : Colors.grey.shade200,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.accentGold.withValues(alpha: 0.2)
                                : AppColors.primaryGreen
                                    .withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.timer_rounded,
                            color: isSelected
                                ? AppColors.accentGold
                                : AppColors.primaryGreen,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          '$min دقائق قبل الأذان',
                          style: TextStyle(
                            fontWeight:
                                isSelected ? FontWeight.w900 : FontWeight.w700,
                            fontSize: 14.5,
                            color: isSelected ? AppColors.primaryGreen : null,
                          ),
                        ),
                        trailing: isSelected
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.accentGold
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text('المحدد ✓',
                                    style: TextStyle(
                                        color: AppColors.primaryGreen,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11.5)),
                              )
                            : null,
                        onTap: () {
                          pn.setPreReminder(min);
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showQiyamOffsetPicker(BuildContext context) {
    final pn = PrayerNotificationService.instance;
    final options = [
      {'minutes': 60, 'label': 'قبل أذان الفجر بساعة (٦٠ دقيقة)'},
      {'minutes': 90, 'label': 'قبل أذان الفجر بساعة ونصف (٩٠ دقيقة)'},
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Directionality(
        textDirection: SettingsService.instance.textDirection,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.nightlight_round,
                      color: AppColors.accentGold, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'تعديل توقيت تنبيه قيام الليل',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryGreen),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...options.map((opt) {
                final mins = opt['minutes'] as int;
                final label = opt['label'] as String;
                final isSelected = pn.qiyamOffsetMinutes == mins;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Material(
                    color: isSelected
                        ? AppColors.primaryGreen.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.accentGold
                              : Colors.grey.shade200,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.accentGold.withValues(alpha: 0.2)
                                : AppColors.primaryGreen
                                    .withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.access_time_filled_rounded,
                            color: isSelected
                                ? AppColors.accentGold
                                : AppColors.primaryGreen,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          label,
                          style: TextStyle(
                            fontWeight:
                                isSelected ? FontWeight.w900 : FontWeight.w700,
                            fontSize: 14.5,
                            color: isSelected ? AppColors.primaryGreen : null,
                          ),
                        ),
                        trailing: isSelected
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.accentGold
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text('المحدد ✓',
                                    style: TextStyle(
                                        color: AppColors.primaryGreen,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11.5)),
                              )
                            : null,
                        onTap: () {
                          pn.setQiyamOffset(mins);
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsService.instance;
    final pn = PrayerNotificationService.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(
          title: context.tr('section_adhan_sensors'),
          icon: Icons.notifications_active_rounded,
        ),

        SwitchListTile(
          secondary:
              const Icon(Icons.alarm_on_rounded, color: AppColors.primaryGreen),
          title: const Text('التنبيه المسبق قبل الأذان'),
          value: pn.preReminderEnabled,
          activeThumbColor: AppColors.accentGold,
          activeTrackColor: AppColors.primaryGreen,
          onChanged: (val) => pn.togglePreReminder(val),
        ),
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.timer_rounded,
                color: AppColors.primaryGreen, size: 20),
          ),
          title: const Text('تعديل دقائق التنبيه المسبق'),
          subtitle: Text('${pn.preReminderMinutes} دقائق قبل الأذان'),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
          onTap: () => _showPreReminderPicker(context),
        ),
        SwitchListTile(
          secondary:
              const Icon(Icons.nightlight_round, color: AppColors.accentGold),
          title: const Text('تنبيه قيام الليل والتهجد 🌙'),
          value: pn.qiyamReminderEnabled,
          activeThumbColor: AppColors.accentGold,
          activeTrackColor: AppColors.primaryGreen,
          onChanged: (val) => pn.toggleQiyamReminder(val),
        ),
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.accentGold.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.access_time_filled_rounded,
                color: AppColors.accentGold, size: 20),
          ),
          title: const Text('تعديل توقيت تنبيه قيام الليل'),
          subtitle: Text('${pn.qiyamOffsetMinutes} دقيقة قبل الفجر'),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
          onTap: () => _showQiyamOffsetPicker(context),
        ),
        SwitchListTile(
          secondary:
              const Icon(Icons.mosque_rounded, color: AppColors.primaryGreen),
          title: const Text('تذكير سنن يوم الجمعة المباركة 🕌'),
          value: pn.fridayReminderEnabled,
          activeThumbColor: AppColors.accentGold,
          activeTrackColor: AppColors.primaryGreen,
          onChanged: (val) => pn.toggleFridayReminder(val),
        ),

        const SettingsSectionHeader(
          title: 'إيماءات التحكم بالأذان ومستشعرات الحركة',
          icon: Icons.sensors_rounded,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.picture_in_picture_alt_rounded,
              color: AppColors.primaryGreen),
          title: const Text('الظهور فوق التطبيقات وشاشة القفل'),
          value: AdhanSensorGestureService.instance.overlayWindowEnabled,
          activeThumbColor: AppColors.accentGold,
          activeTrackColor: AppColors.primaryGreen,
          onChanged: (val) =>
              AdhanSensorGestureService.instance.toggleOverlayWindow(val),
        ),

        SwitchListTile(
          secondary: const Icon(Icons.notifications_active_rounded,
              color: AppColors.primaryGreen),
          title: Text(context.tr('notifications'),
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          value: pn.masterEnabled,
          activeThumbColor: AppColors.accentGold,
          activeTrackColor: AppColors.primaryGreen,
          onChanged: (val) {
            s.toggleAdhanAlerts(val);
            pn.toggleMaster(val);
          },
        ),

        // Sound Mode Dropdown
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: AppDropdownField<AdhanSoundMode>(
            label: 'نمط صوت تنبيه الأذان',
            value: pn.soundMode,
            prefixIcon: Icons.surround_sound_rounded,
            options: const [
              AppDropdownOption(
                  value: AdhanSoundMode.fullAdhan,
                  label: 'أذان كامل (نداء الحق كاملاً بجودة HD)'),
              AppDropdownOption(
                  value: AdhanSoundMode.takbeerat,
                  label: 'تكبيرات الأذان فقط (الله أكبر)'),
              AppDropdownOption(
                  value: AdhanSoundMode.softBeep, label: 'نغمة إشعار هادئة'),
              AppDropdownOption(
                  value: AdhanSoundMode.vibrateOnly,
                  label: 'اهتزاز فقط (بدون صوت)'),
              AppDropdownOption(
                  value: AdhanSoundMode.silent, label: 'إشعار صامت'),
            ],
            onChanged: (mode) => pn.setSoundMode(mode),
          ),
        ),

        // Per-Prayer Muezzin Dropdowns (5 Prayers)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'مؤذن كل صلاة',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: AppColors.secondaryGreen),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.volume_up_rounded, size: 16),
                label: const Text('معاينة الأصوات',
                    style: TextStyle(fontSize: 12)),
                onPressed: () => showSettingsAdhanVoiceModal(context),
              ),
            ],
          ),
        ),
        const PrayerVoiceList(),

        // Pre-Reminder & Iqamah Offset Dropdowns
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: AppDropdownField<int>(
                  label: context.tr('pre_adhan_alert'),
                  value: [5, 10, 15, 20, 30].contains(pn.preReminderMinutes)
                      ? pn.preReminderMinutes
                      : 15,
                  dense: true,
                  prefixIcon: Icons.timer_rounded,
                  options: const [
                    AppDropdownOption(value: 5, label: 'قبل الأذان بـ ٥ د'),
                    AppDropdownOption(value: 10, label: 'قبل الأذان بـ ١٠ د'),
                    AppDropdownOption(value: 15, label: 'قبل الأذان بـ ١٥ د'),
                    AppDropdownOption(value: 20, label: 'قبل الأذان بـ ٢٠ د'),
                    AppDropdownOption(value: 30, label: 'قبل الأذان بـ ٣٠ د'),
                  ],
                  onChanged: (val) => pn.setPreReminderMinutes(val),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppDropdownField<int>(
                  label: context.tr('iqamah_offset'),
                  value:
                      [5, 10, 15, 20, 25, 30].contains(pn.iqamahOffsetMinutes)
                          ? pn.iqamahOffsetMinutes
                          : 15,
                  dense: true,
                  prefixIcon: Icons.notifications_paused_rounded,
                  options: const [
                    AppDropdownOption(value: 5, label: 'بعد الأذان بـ ٥ د'),
                    AppDropdownOption(value: 10, label: 'بعد الأذان بـ ١٠ د'),
                    AppDropdownOption(value: 15, label: 'بعد الأذان بـ ١٥ د'),
                    AppDropdownOption(value: 20, label: 'بعد الأذان بـ ٢٠ د'),
                    AppDropdownOption(value: 25, label: 'بعد الأذان بـ ٢٥ د'),
                    AppDropdownOption(value: 30, label: 'بعد الأذان بـ ٣٠ د'),
                  ],
                  onChanged: (val) => pn.setIqamahOffsetMinutes(val),
                ),
              ),
            ],
          ),
        ),

        SwitchListTile(
          secondary: const Icon(Icons.wb_twilight_rounded,
              color: AppColors.accentGold),
          title: const Text('أذان الفجر المميز (الصلاة خير من النوم)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          value: pn.fajrDistinctVoiceEnabled,
          activeThumbColor: AppColors.accentGold,
          activeTrackColor: AppColors.primaryGreen,
          onChanged: (val) => pn.toggleFajrDistinctVoice(val),
        ),

        SwitchListTile(
          secondary: const Icon(Icons.record_voice_over_rounded,
              color: AppColors.accentGold),
          title: const Text('تشغيل دعاء الشيخ الشعراوي بعد الأذان 🎧',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          value: s.playSharawiDuaaAfterAdhan,
          activeThumbColor: AppColors.accentGold,
          activeTrackColor: AppColors.primaryGreen,
          onChanged: (val) => s.togglePlaySharawiDuaaAfterAdhan(val),
        ),

        SwitchListTile(
          secondary: const Icon(Icons.do_not_disturb_on_total_silence_rounded,
              color: AppColors.primaryGreen),
          title: const Text('وضع الخشوع الصامت التلقائي وقت الصلاة',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          subtitle: const Text(
              'تذكير بكتم الرنين لمدة ٢٠ دقيقة عقب الإقامة للخشوع في الصلاة',
              style: TextStyle(fontSize: 12)),
          value: s.autoSilentDuringPrayer,
          activeThumbColor: AppColors.accentGold,
          activeTrackColor: AppColors.primaryGreen,
          onChanged: (val) => s.toggleAutoSilentDuringPrayer(val),
        ),

        SwitchListTile(
          secondary: const Icon(Icons.auto_awesome_rounded,
              color: AppColors.primaryGreen),
          title: const Text('تذكير السنن الرواتب المؤكدة (١٢ ركعة يومياً)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          value: s.sunanRawatibReminderEnabled,
          activeThumbColor: AppColors.accentGold,
          activeTrackColor: AppColors.primaryGreen,
          onChanged: (val) => s.toggleSunanRawatibReminder(val),
        ),

        SwitchListTile(
          secondary: const Icon(Icons.vibration_rounded,
              color: AppColors.primaryGreen),
          title: const Text('إيقاف الأذان عند هز الهاتف 📳',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          value: AdhanSensorGestureService.instance.shakeToStopEnabled,
          activeThumbColor: AppColors.accentGold,
          activeTrackColor: AppColors.primaryGreen,
          onChanged: (val) =>
              AdhanSensorGestureService.instance.toggleShakeToStop(val),
        ),

        SwitchListTile(
          secondary: const Icon(Icons.screen_rotation_rounded,
              color: AppColors.accentGold),
          title: const Text('كتم الأذان عند قلب الهاتف على وجهه 📱',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          value: AdhanSensorGestureService.instance.flipToMuteEnabled,
          activeThumbColor: AppColors.accentGold,
          activeTrackColor: AppColors.primaryGreen,
          onChanged: (val) =>
              AdhanSensorGestureService.instance.toggleFlipToMute(val),
        ),

        SwitchListTile(
          secondary: const Icon(Icons.volume_up_rounded,
              color: AppColors.primaryGreen),
          title: const Text('التسبيح بزر رفع الصوت في المسبحة (+١) 🔊',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          value: s.tasbihVolumeButtonEnabled,
          activeThumbColor: AppColors.accentGold,
          activeTrackColor: AppColors.primaryGreen,
          onChanged: (val) => s.toggleTasbihVolumeButton(val),
        ),

        SwitchListTile(
          secondary: const Icon(Icons.linear_scale_rounded,
              color: AppColors.accentGold),
          title: const Text('إظهار سليدر حبات المسبحة التفاعلي 📿',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          value: s.tasbihSliderEnabled,
          activeThumbColor: AppColors.accentGold,
          activeTrackColor: AppColors.primaryGreen,
          onChanged: (val) => s.toggleTasbihSlider(val),
        ),

        ListTile(
          leading: const Icon(Icons.ring_volume_rounded,
              color: AppColors.primaryGreen),
          title: const Text('تجربة نداء الأذان وشاشة التحكم',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          trailing: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('تجربة الشاشة'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdhanControlScreen(
                        prayerName: 'الظهر', autoPlay: false)),
              );
            },
          ),
        ),
        const Divider(),
      ],
    );
  }
}
