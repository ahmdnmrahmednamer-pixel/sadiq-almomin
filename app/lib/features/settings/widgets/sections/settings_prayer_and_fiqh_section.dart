import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/services/prayer_service.dart';
import '../../../prayer/widgets/prayer_location_banner.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_dropdown_field.dart';
import '../settings_calculation_method_modal.dart';
import 'settings_section_header.dart';

/// Refactored Section 3: Prayer Calculation, Fiqh Madhhab & Hijri Adjustment
class SettingsPrayerAndFiqhSection extends StatelessWidget {
  const SettingsPrayerAndFiqhSection({super.key});

  static const List<AppDropdownOption<String>> _fiqhOptions = [
    AppDropdownOption(
      value: 'shafii_egypt',
      label: 'الشافعي / دار الإفتاء المصرية',
    ),
    AppDropdownOption(value: 'hanafi', label: 'المذهب الحنفي'),
    AppDropdownOption(value: 'maliki', label: 'المذهب المالكي'),
    AppDropdownOption(value: 'hanbali', label: 'المذهب الحنبلي'),
    AppDropdownOption(value: 'comparative', label: 'الفقه المقارن العام'),
  ];

  static const List<AppDropdownOption<int>> _hijriOptions = [
    AppDropdownOption(value: -2, label: '-٢ يوم'),
    AppDropdownOption(value: -1, label: '-١ يوم'),
    AppDropdownOption(value: 0, label: 'فلكي (٠)'),
    AppDropdownOption(value: 1, label: '+١ يوم'),
    AppDropdownOption(value: 2, label: '+٢ يوم'),
  ];

  Widget _buildLargeTextSelectorTile<T>({
    required BuildContext context,
    required Key tileKey,
    required String label,
    required IconData icon,
    required T value,
    required List<AppDropdownOption<T>> options,
    required ValueChanged<T> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = options.firstWhere(
      (o) => o.value == value,
      orElse: () => options.first,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Semantics(
        button: true,
        container: true,
        label: '$label، الاختيار الحالي: ${selected.label}',
        child: InkWell(
          key: tileKey,
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (sheetCtx) {
                return Directionality(
                  textDirection: SettingsService.instance.textDirection,
                  child: SafeArea(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.72,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                          ),
                          ...options.map((opt) {
                            final isSelected = opt.value == selected.value;
                            return ListTile(
                              title: Text(
                                opt.label,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              trailing: isSelected
                                  ? const Icon(
                                      Icons.check_rounded,
                                      color: AppColors.primaryGreen,
                                    )
                                  : null,
                              onTap: () {
                                onChanged(opt.value);
                                Navigator.pop(sheetCtx);
                              },
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF16201C)
                  : AppColors.primaryGreen.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primaryGreen.withValues(alpha: 0.28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        icon,
                        size: 18,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white70
                              : AppColors.secondaryGreen,
                        ),
                      ),
                    ),
                    const ExcludeSemantics(
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  selected.label,
                  style: TextStyle(
                    fontFamily: 'Amiri',
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: isDark ? Colors.white : const Color(0xFF18221E),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        SettingsService.instance,
        PrayerService.instance,
      ]),
      builder: (context, _) {
        final s = SettingsService.instance;
        final isLargeText = MediaQuery.textScalerOf(context).scale(1.0) >= 1.35;
        final calcOptions = SettingsService.calculationMethods
            .map((m) => AppDropdownOption<String>(
                  value: m['id']!,
                  label: m['name']!,
                ))
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        SettingsSectionHeader(
          title: context.tr('section_prayer_fiqh'),
          icon: Icons.mosque_rounded,
        ),

        // Calculation Method Guide Launcher (wraps cleanly at large text scales)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  context.tr('calc_method'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: AppColors.secondaryGreen,
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
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
        ),

        if (isLargeText) ...[
          _buildLargeTextSelectorTile<String>(
            context: context,
            tileKey: const ValueKey('settings_large_text_calc_method'),
            label: context.tr('calc_method'),
            icon: Icons.calculate_rounded,
            value: s.calculationMethod,
            options: calcOptions,
            onChanged: (val) => s.setCalculationMethod(val),
          ),
          _buildLargeTextSelectorTile<String>(
            context: context,
            tileKey: const ValueKey('settings_large_text_fiqh_madhhab'),
            label: context.tr('fiqh_madhhab'),
            icon: Icons.balance_rounded,
            value: s.fiqhMadhhab,
            options: _fiqhOptions,
            onChanged: (val) => s.setFiqhMadhhab(val),
          ),
          _buildLargeTextSelectorTile<int>(
            context: context,
            tileKey: const ValueKey('settings_large_text_hijri_adjust'),
            label: context.tr('hijri_adjust'),
            icon: Icons.calendar_month_rounded,
            value: s.hijriAdjustmentDays,
            options: _hijriOptions,
            onChanged: (val) => s.setHijriAdjustmentDays(val),
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: AppDropdownField<String>(
              label: context.tr('calc_method'),
              value: s.calculationMethod,
              prefixIcon: Icons.calculate_rounded,
              options: calcOptions,
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
                    options: _fiqhOptions,
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
                    options: _hijriOptions,
                    onChanged: (val) => s.setHijriAdjustmentDays(val),
                  ),
                ),
              ],
            ),
          ),
        ],

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.my_location_rounded,
                      color: AppColors.primaryGreen,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'الموقع الفعلي عبر GPS',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            GpsFreshnessChip(
                              freshness:
                                  PrayerService.instance.locationFreshness,
                            ),
                            Text(
                              PrayerService.formatDisplayLocationName(
                                PrayerService.instance.currentData,
                                PrayerService.instance.locationFreshness,
                                unknownFallback: 'الموقع غير محدد بعد',
                              ),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                        if (PrayerService.instance.cachedFixAgeLabel != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              PrayerService.instance.cachedFixAgeLabel!,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.mutedText,
                              ),
                            ),
                          ),
                        if (PrayerService.instance.currentData == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              GpsLocationActionControls
                                  .describeUnavailableReason(
                                PrayerService.instance,
                              ),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.mutedText,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const GpsLocationActionControls(),
            ],
          ),
        ),
        const Divider(),
      ],
        );
      },
    );
  }
}
