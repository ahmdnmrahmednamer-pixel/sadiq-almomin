import 'package:flutter/material.dart';
import '../../../../core/notifications/prayer_notification_service.dart';
import '../../../../core/theme/app_theme.dart';
import 'settings_section_header.dart';

/// Section: User-customizable Morning, Evening, and Sleep Adhkar Notification Timings
class SettingsAdhkarRemindersSection extends StatelessWidget {
  const SettingsAdhkarRemindersSection({super.key});

  Future<void> _pickMorningTime(BuildContext context) async {
    final pn = PrayerNotificationService.instance;
    final picked = await showTimePicker(
      context: context,
      initialTime: pn.morningAdhkarTime,
      helpText: 'اختر موعد إشعار أذكار الصباح ☀️',
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
      helpText: 'اختر موعد إشعار أذكار المساء 🌙',
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
      helpText: 'اختر موعد إشعار أذكار النوم 🛏️',
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
        const SettingsSectionHeader(
          title: 'مواقيت وتنبيهات أذكار المسلم',
          icon: Icons.alarm_rounded,
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            'حدّد الأوقات المناسبة لك لتلقي إشعارات أذكار الصباح والمساء والنوم يومياً، لتكون في حفظ الله ومعيته طوال اليوم.',
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
          title: 'أذكار الصباح المباركة ☀️',
          subtitle: 'حصن يومك وانشراح صدرك والبركة في رزقك',
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
          title: 'أذكار المساء المباركة 🌙',
          subtitle: 'حفظ الليل وسكينة الروح والأمان من كل سوء',
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
          title: 'أذكار وسنن النوم 🛏️',
          subtitle: 'تحصين المضجع والمأثور عن النبي ﷺ عند النوم',
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
                ? AppColors.accentGold.withOpacity(0.5)
                : Colors.grey.withOpacity(0.2),
            width: isEnabled ? 1.5 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        elevation: 1,
        shadowColor: Colors.black.withOpacity(0.04),
        child: Column(
          children: [
            SwitchListTile(
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.accentGold, size: 22),
              ),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
              ),
              subtitle: Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              value: isEnabled,
              activeColor: AppColors.accentGold,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.access_time_filled_rounded,
                                size: 18, color: AppColors.primaryGreen),
                            const SizedBox(width: 6),
                            const Text(
                              'الموعد:',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGreen.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppColors.primaryGreen.withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  currentTimeStr,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13.5,
                                    color: AppColors.primaryGreen,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
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
                    ],
                  ),
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
                            selectedColor: AppColors.accentGold.withOpacity(0.25),
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
                                  : Colors.grey.withOpacity(0.3),
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
