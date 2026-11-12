import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/services/prayer_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_dropdown_field.dart';
import '../settings_calculation_method_modal.dart';
import 'settings_section_header.dart';

/// Refactored Section 3: Prayer Calculation, Fiqh Madhhab & Hijri Adjustment
class SettingsPrayerAndFiqhSection extends StatelessWidget {
  const SettingsPrayerAndFiqhSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SettingsService.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(
          title: context.tr('section_prayer_fiqh'),
          icon: Icons.mosque_rounded,
        ),

        // Calculation Method Guide Launcher Row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  context.tr('calc_method'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: AppColors.secondaryGreen,
                  ),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.calculate_rounded, size: 16),
                label: Text(
                  s.isArabic ? 'دليل طرق الحساب' : 'Methods Guide',
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: () => showSettingsCalculationMethodModal(context),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: AppDropdownField<String>(
            label: context.tr('calc_method'),
            value: s.calculationMethod,
            prefixIcon: Icons.calculate_rounded,
            options: SettingsService.calculationMethods
                .map((m) => AppDropdownOption<String>(
                      value: m['id']!,
                      label: m['name']!,
                    ))
                .toList(),
            onChanged: (val) => s.setCalculationMethod(val),
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: AppDropdownField<String>(
                  label: context.tr('fiqh_madhhab'),
                  value: s.fiqhMadhhab,
                  dense: true,
                  prefixIcon: Icons.balance_rounded,
                  options: const [
                    AppDropdownOption(
                        value: 'shafii_egypt',
                        label: 'الشافعي / دار الإفتاء المصرية'),
                    AppDropdownOption(value: 'hanafi', label: 'المذهب الحنفي'),
                    AppDropdownOption(value: 'maliki', label: 'المذهب المالكي'),
                    AppDropdownOption(value: 'hanbali', label: 'المذهب الحنبلي'),
                    AppDropdownOption(
                        value: 'comparative', label: 'الفقه المقارن العام'),
                  ],
                  onChanged: (val) => s.setFiqhMadhhab(val),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: AppDropdownField<int>(
                  label: context.tr('hijri_adjust'),
                  value: s.hijriAdjustmentDays,
                  dense: true,
                  prefixIcon: Icons.calendar_month_rounded,
                  options: const [
                    AppDropdownOption(value: -2, label: '-٢ يوم'),
                    AppDropdownOption(value: -1, label: '-١ يوم'),
                    AppDropdownOption(value: 0, label: 'فلكي (٠)'),
                    AppDropdownOption(value: 1, label: '+١ يوم'),
                    AppDropdownOption(value: 2, label: '+٢ يوم'),
                  ],
                  onChanged: (val) => s.setHijriAdjustmentDays(val),
                ),
              ),
            ],
          ),
        ),

        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.my_location_rounded,
              color: AppColors.primaryGreen,
              size: 20,
            ),
          ),
          title: const Text('الموقع الفعلي وتحديد المدينة تلقائياً',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          subtitle: Text(
              'الموقع الفعلي: ${PrayerService.instance.currentData?.locationName ?? 'جاري التحديد عبر GPS...'}'),
          trailing: OutlinedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('تحديث'),
            onPressed: () async {
              final ok = await PrayerService.instance.requestGpsLocation();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'تم تحديث الموقع الفعلي بنجاح'
                        : (PrayerService.instance.errorMessage ?? 'تعذر تحديث الموقع')),
                    backgroundColor: ok ? AppColors.primaryGreen : Colors.redAccent,
                  ),
                );
              }
            },
          ),
        ),
        const Divider(),
      ],
    );
  }
}
