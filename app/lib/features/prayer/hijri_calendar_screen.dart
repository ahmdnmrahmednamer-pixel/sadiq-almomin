import 'package:flutter/material.dart';
import '../../core/services/prayer_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';

import '../ramadan/ramadan_screen.dart';
import 'widgets/hijri_accessible_date_picker_dialog.dart';

class IslamicOccasion {
  final String title;
  final int hijriMonth;
  final int hijriDay;
  final String description;
  final IconData icon;

  const IslamicOccasion({
    required this.title,
    required this.hijriMonth,
    required this.hijriDay,
    required this.description,
    required this.icon,
  });
}

class HijriCalendarScreen extends StatefulWidget {
  const HijriCalendarScreen({super.key});

  @override
  State<HijriCalendarScreen> createState() => _HijriCalendarScreenState();
}

class _HijriCalendarScreenState extends State<HijriCalendarScreen> {
  int _hijriAdjustment = 0; // ±2 days persisted in SettingsService
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _hijriAdjustment = SettingsService.instance.hijriAdjustmentDays;
    SettingsService.instance.addListener(_onSettingsUpdated);
  }

  void _onSettingsUpdated() {
    if (mounted && _hijriAdjustment != SettingsService.instance.hijriAdjustmentDays) {
      setState(() {
        _hijriAdjustment = SettingsService.instance.hijriAdjustmentDays;
      });
    }
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onSettingsUpdated);
    super.dispose();
  }

  static const List<IslamicOccasion> occasions = [
    IslamicOccasion(
      title: 'رأس السنة الهجرية',
      hijriMonth: 1,
      hijriDay: 1,
      description: 'بداية العام الهجري الجديد واستذكار الهجرة النبوية الشريفة',
      icon: Icons.brightness_auto,
    ),
    IslamicOccasion(
      title: 'يوم عاشوراء',
      hijriMonth: 1,
      hijriDay: 10,
      description: 'نجاة نبي الله موسى عليه السلام، ويستحب صيامه وتاسوعاء قبله',
      icon: Icons.wb_twighlight,
    ),
    IslamicOccasion(
      title: 'المولد النبوي الشريف',
      hijriMonth: 3,
      hijriDay: 12,
      description: 'مولد خير الأنام محمد ﷺ رحمة للعالمين',
      icon: Icons.star_rounded,
    ),
    IslamicOccasion(
      title: 'الإسراء والمعراج',
      hijriMonth: 7,
      hijriDay: 27,
      description: 'معجزة الإسراء بالرسول ﷺ وفرض الصلوات الخمس',
      icon: Icons.mosque,
    ),
    IslamicOccasion(
      title: 'ليلة النصف من شعبان',
      hijriMonth: 8,
      hijriDay: 15,
      description: 'تحويل القبلة إلى المسجد الحرام وليلة المغفرة والرحمة',
      icon: Icons.nightlight_round,
    ),
    IslamicOccasion(
      title: 'أول أيام شهر رمضان المبارك',
      hijriMonth: 9,
      hijriDay: 1,
      description: 'شهر الصيام والقرآن وليلة القدر التي هي خير من ألف شهر',
      icon: Icons.nights_stay,
    ),
    IslamicOccasion(
      title: 'عيد الفطر المبارك',
      hijriMonth: 10,
      hijriDay: 1,
      description: 'فرحة إتمام الصيام وجائزة العابدين وزكاة الفطر',
      icon: Icons.celebration,
    ),
    IslamicOccasion(
      title: 'يوم عرفة',
      hijriMonth: 12,
      hijriDay: 9,
      description: 'خير يوم طلعت عليه الشمس، وصيامه يكفر سنة ماضية وقادمة',
      icon: Icons.terrain,
    ),
    IslamicOccasion(
      title: 'عيد الأضحى المبارك',
      hijriMonth: 12,
      hijriDay: 10,
      description: 'يوم النحر وأيام التشريق وذكر الله وذبح الأضاحي',
      icon: Icons.festival,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final textScale = media.textScaler.scale(1.0);
    final isLargeText = textScale >= 1.35;
    // Pass adjustmentDays explicitly to avoid double-adding _hijriAdjustment (Bug #18 fix)
    final hijri = HijriDateHelper.toHijri(_selectedDate, adjustmentDays: _hijriAdjustment);
    final currentHijriMonth = hijri['month']!;
    final currentHijriDay = hijri['day']!;
    final currentHijriYear = hijri['year']!;
    final monthName = HijriDateHelper.hijriMonths[currentHijriMonth - 1];

    // Compute adaptive AppBar height matching Material AppBar's own title text scaling so the full title wraps without ellipsis or excess whitespace
    final appBarTitleStyle = Theme.of(context).appBarTheme.titleTextStyle ??
        Theme.of(context).textTheme.titleLarge ??
        const TextStyle(fontSize: 20, fontWeight: FontWeight.bold);
    final availableAppBarTitleWidth = (media.size.width - 128).clamp(120.0, double.infinity);
    final titlePainter = TextPainter(
      text: TextSpan(text: 'التقويم الهجري والمناسبات', style: appBarTitleStyle),
      textDirection: SettingsService.instance.textDirection,
      textScaler: media.textScaler.clamp(maxScaleFactor: 1.34),
    )..layout(maxWidth: availableAppBarTitleWidth);
    final adaptiveToolbarHeight = (titlePainter.height + 16)
        .clamp(kToolbarHeight, double.infinity);

    // Build rolling 12-month upcoming occasions list so late Dhu al-Hijjah wraps into next Hijri year (Bug #17 fix)
    final thisYearOccasions = occasions
        .where((occ) =>
            occ.hijriMonth > currentHijriMonth ||
            (occ.hijriMonth == currentHijriMonth && occ.hijriDay >= currentHijriDay))
        .map((occ) => MapEntry(occ, currentHijriYear))
        .toList();

    final nextYearOccasions = occasions
        .where((occ) =>
            occ.hijriMonth < currentHijriMonth ||
            (occ.hijriMonth == currentHijriMonth && occ.hijriDay < currentHijriDay))
        .map((occ) => MapEntry(occ, currentHijriYear + 1))
        .toList();

    final upcomingEntries = [...thisYearOccasions, ...nextYearOccasions];

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: adaptiveToolbarHeight,
          title: const Text(
            'التقويم الهجري والمناسبات',
            softWrap: true,
            overflow: TextOverflow.visible,
          ),
          actions: [
            IconButton(
              key: const ValueKey('hijri_ramadan_button'),
              icon: const Icon(Icons.nightlight_round, color: AppColors.accentGold),
              tooltip: 'إمساكية ومحراب رمضان المبارك',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RamadanScreen()),
                );
              },
            ),
            IconButton(
              key: const ValueKey('hijri_adjustment_button'),
              icon: const Icon(Icons.tune),
              tooltip: 'تعديل رؤية الهلال (± يومين)',
              onPressed: _showAdjustmentDialog,
            ),
          ],
        ),
        body: ListView(
          key: const ValueKey('hijri_calendar_list_view'),
          padding: const EdgeInsets.all(16.0),
          children: [
            // Main Hijri Banner Card
            Semantics(
              container: true,
              child: Container(
                key: const ValueKey('hijri_banner_card'),
                padding: EdgeInsets.all(isLargeText ? 18 : 24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryGreen, AppColors.secondaryGreen],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGreen.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      HijriDateHelper.getDayOfWeek(_selectedDate),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.accentGold,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$currentHijriDay $monthName $currentHijriYear هـ',
                      key: const ValueKey('hijri_banner_date_text'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'الموافق ${HijriDateHelper.getGregorianDateString(_selectedDate)}',
                      key: const ValueKey('hijri_banner_gregorian_text'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    if (_hijriAdjustment != 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'تعديل الرؤية الشرعية محفوظ: ${_hijriAdjustment > 0 ? "+$_hijriAdjustment" : _hijriAdjustment} يوم',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.softGold, fontSize: 12),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    // White days & Sunnah fasting indicators
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final stackBadges = isLargeText || constraints.maxWidth < 340;
                          if (stackBadges) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildWhiteDaysBadge(currentHijriDay),
                                Container(
                                  height: 1,
                                  margin: const EdgeInsets.symmetric(vertical: 8),
                                  color: Colors.white24,
                                ),
                                _buildFastingDayBadge(_selectedDate.weekday),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: _buildWhiteDaysBadge(currentHijriDay)),
                              Container(
                                width: 1,
                                height: 24,
                                margin: const EdgeInsets.symmetric(horizontal: 10),
                                color: Colors.white24,
                              ),
                              Expanded(child: _buildFastingDayBadge(_selectedDate.weekday)),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Date Navigation Controls
            Card(
              key: const ValueKey('hijri_nav_controls_card'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final prevButton = TextButton.icon(
                      key: const ValueKey('hijri_prev_day_button'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                        });
                      },
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('اليوم السابق', softWrap: true),
                    );

                    final pickButton = OutlinedButton.icon(
                      key: const ValueKey('hijri_pick_date_button'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onPressed: _pickGregorianDate,
                      icon: const Icon(Icons.calendar_month, size: 18),
                      label: const Text('اختر تاريخاً', softWrap: true),
                    );

                    final nextButton = TextButton.icon(
                      key: const ValueKey('hijri_next_day_button'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedDate = _selectedDate.add(const Duration(days: 1));
                        });
                      },
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('اليوم التالي', softWrap: true),
                    );

                    if (isLargeText) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          prevButton,
                          const SizedBox(height: 8),
                          pickButton,
                          const SizedBox(height: 8),
                          nextButton,
                        ],
                      );
                    }

                    return SizedBox(
                      width: constraints.maxWidth,
                      child: Wrap(
                        alignment: WrapAlignment.spaceEvenly,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          prevButton,
                          pickButton,
                          nextButton,
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Upcoming Islamic Occasions Header
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Semantics(
                    header: true,
                    child: const Text(
                      'المناسبات الإسلامية القادمة',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ),
                  Text(
                    '$currentHijriYear - ${currentHijriYear + 1} هـ',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.accentGold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Occasions List
            ...upcomingEntries.map((entry) {
              final occ = entry.key;
              final occYear = entry.value;
              final isCurrent = occYear == currentHijriYear &&
                  occ.hijriMonth == currentHijriMonth &&
                  occ.hijriDay == currentHijriDay;

              final iconCircle = Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? AppColors.accentGold
                      : AppColors.primaryGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  occ.icon,
                  color: isCurrent ? Colors.black : AppColors.primaryGreen,
                  size: 22,
                ),
              );

              final datePill = Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.softGold.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${occ.hijriDay} ${HijriDateHelper.hijriMonths[occ.hijriMonth - 1]} $occYear هـ',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreen,
                  ),
                ),
              );

              final titleText = Text(
                occ.title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isCurrent ? AppColors.primaryGreen : null,
                ),
              );

              final descriptionText = Text(
                occ.description,
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? Colors.white70 : AppColors.mutedText,
                  height: 1.4,
                ),
              );

              return Semantics(
                container: true,
                child: Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: isCurrent ? AppColors.accentGold : Colors.transparent,
                      width: isCurrent ? 1.5 : 0,
                    ),
                  ),
                  color: isCurrent
                      ? (isDark ? const Color(0xFF263228) : const Color(0xFFF0F8F2))
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: isLargeText
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 10,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  iconCircle,
                                  datePill,
                                ],
                              ),
                              const SizedBox(height: 10),
                              titleText,
                              const SizedBox(height: 4),
                              descriptionText,
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              iconCircle,
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: double.infinity,
                                      child: Wrap(
                                        alignment: WrapAlignment.spaceBetween,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          titleText,
                                          datePill,
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    descriptionText,
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildWhiteDaysBadge(int currentDay) {
    final isWhiteDay = currentDay == 13 || currentDay == 14 || currentDay == 15;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Icon(
            Icons.circle,
            size: 10,
            color: isWhiteDay ? Colors.greenAccent : Colors.white38,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            isWhiteDay ? 'اليوم من الأيام البيض المستحبة' : 'الأيام البيض: ١٣، ١٤، ١٥',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildFastingDayBadge(int weekday) {
    final isMonThu = weekday == DateTime.monday || weekday == DateTime.thursday;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Icon(
            Icons.restaurant_menu,
            size: 14,
            color: isMonThu ? AppColors.softGold : Colors.white38,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            isMonThu ? 'سنة صيام الإثنين والخميس' : 'صيام الإثنين والخميس',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Future<void> _pickGregorianDate() async {
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final picked = textScale >= 1.35
        ? await showHijriAccessibleDatePicker(
            context: context,
            initialDate: _selectedDate,
            firstDate: DateTime(1980),
            lastDate: DateTime(2050),
          )
        : await showDatePicker(
            context: context,
            initialDate: _selectedDate,
            firstDate: DateTime(1980),
            lastDate: DateTime(2050),
            locale: const Locale('ar'),
          );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _showAdjustmentDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final media = MediaQuery.of(dialogCtx);
          final isCompactOrLargeText =
              media.size.width <= 420 || media.textScaler.scale(1.0) >= 1.35;

          return Directionality(
            textDirection: SettingsService.instance.textDirection,
            child: AlertDialog(
              key: const ValueKey('hijri_adjustment_dialog'),
              insetPadding: isCompactOrLargeText
                  ? const EdgeInsets.symmetric(horizontal: 16, vertical: 20)
                  : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              title: const Text('تعديل تقويم الرؤية الشرعية'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'وفقاً لإعلانات دار الإفتاء وهيئات الرؤية الشرعية، قد يختلف التاريخ الهجري بمقدار يوم أو يومين عن الحساب الفلكي:',
                      style: TextStyle(fontSize: 13, height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          IconButton(
                            key: const ValueKey('hijri_adjust_decrement_button'),
                            tooltip: 'إنقاص أو تقليل',
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                            onPressed: _hijriAdjustment > -2
                                ? () {
                                    setState(() => _hijriAdjustment--);
                                    SettingsService.instance
                                        .setHijriAdjustmentDays(_hijriAdjustment);
                                    setDialogState(() {});
                                  }
                                : null,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.accentGold.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_hijriAdjustment > 0 ? "+$_hijriAdjustment" : "$_hijriAdjustment"} يوم',
                              key: const ValueKey('hijri_adjust_value_text'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('hijri_adjust_increment_button'),
                            tooltip: 'إضافة أو زيادة',
                            icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                            onPressed: _hijriAdjustment < 2
                                ? () {
                                    setState(() => _hijriAdjustment++);
                                    SettingsService.instance
                                        .setHijriAdjustmentDays(_hijriAdjustment);
                                    setDialogState(() {});
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                FilledButton(
                  key: const ValueKey('hijri_adjust_save_button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('حفظ التعديل'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
