import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/services/prayer_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/theme/app_theme.dart';

enum _AccessiblePickerMode { day, year, input }

/// Shows a responsive, large-text accessible Gregorian date picker preserving
/// full effective user text scaling (no TextScaler clamp or font shrinking),
/// full unellipsized selected date display, >= 48x48 touch targets, unique
/// semantic labels/states, month/year navigation, and text input mode.
Future<DateTime?> showHijriAccessibleDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  return showDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: HijriAccessibleDatePickerDialog(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
      ),
    ),
  );
}

class HijriAccessibleDatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const HijriAccessibleDatePickerDialog({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<HijriAccessibleDatePickerDialog> createState() =>
      _HijriAccessibleDatePickerDialogState();
}

class _HijriAccessibleDatePickerDialogState
    extends State<HijriAccessibleDatePickerDialog> {
  late final DateTime _firstDate;
  late final DateTime _lastDate;
  late DateTime _selectedDate;
  late int _displayedYear;
  late int _displayedMonth;
  _AccessiblePickerMode _mode = _AccessiblePickerMode.day;
  late final TextEditingController _inputController;
  String? _inputError;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _clampDate(DateTime d) {
    final normalized = _dateOnly(d);
    if (normalized.isBefore(_firstDate)) return _firstDate;
    if (normalized.isAfter(_lastDate)) return _lastDate;
    return normalized;
  }

  String _formatInputDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  @override
  void initState() {
    super.initState();
    _firstDate = _dateOnly(widget.firstDate);
    _lastDate = _dateOnly(widget.lastDate);
    _selectedDate = _clampDate(widget.initialDate);
    _displayedYear = _selectedDate.year;
    _displayedMonth = _selectedDate.month;
    _inputController = TextEditingController(text: _formatInputDate(_selectedDate));
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  bool get _canGoPrevMonth =>
      _displayedYear > _firstDate.year ||
      (_displayedYear == _firstDate.year && _displayedMonth > _firstDate.month);

  bool get _canGoNextMonth =>
      _displayedYear < _lastDate.year ||
      (_displayedYear == _lastDate.year && _displayedMonth < _lastDate.month);

  void _goPrevMonth() {
    if (!_canGoPrevMonth) return;
    setState(() {
      if (_displayedMonth == 1) {
        _displayedMonth = 12;
        _displayedYear -= 1;
      } else {
        _displayedMonth -= 1;
      }
    });
  }

  void _goNextMonth() {
    if (!_canGoNextMonth) return;
    setState(() {
      if (_displayedMonth == 12) {
        _displayedMonth = 1;
        _displayedYear += 1;
      } else {
        _displayedMonth += 1;
      }
    });
  }

  void _selectYear(int year) {
    final maxDays = DateUtils.getDaysInMonth(year, _displayedMonth);
    final candidate = _clampDate(
      DateTime(year, _displayedMonth, math.min(_selectedDate.day, maxDays)),
    );
    setState(() {
      _displayedYear = candidate.year;
      _displayedMonth = candidate.month;
      _selectedDate = candidate;
      _inputController.text = _formatInputDate(_selectedDate);
      _inputError = null;
      _mode = _AccessiblePickerMode.day;
    });
  }

  void _selectDay(int day) {
    final candidate = DateTime(_displayedYear, _displayedMonth, day);
    if (candidate.isBefore(_firstDate) || candidate.isAfter(_lastDate)) return;
    setState(() {
      _selectedDate = candidate;
      _inputController.text = _formatInputDate(_selectedDate);
      _inputError = null;
    });
  }

  String _normalizeDigits(String raw) {
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const easternArabic = '۰۱۲۳۴۵۶۷۸۹';
    final buf = StringBuffer();
    for (final rune in raw.runes) {
      final ch = String.fromCharCode(rune);
      final idx1 = arabicIndic.indexOf(ch);
      if (idx1 != -1) {
        buf.write(idx1);
        continue;
      }
      final idx2 = easternArabic.indexOf(ch);
      if (idx2 != -1) {
        buf.write(idx2);
        continue;
      }
      buf.write(ch);
    }
    return buf.toString();
  }

  DateTime? _parseInputDate(String raw) {
    final normalized = _normalizeDigits(raw.trim()).replaceAll('-', '/');
    final parts = normalized.split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    if (month < 1 || month > 12) return null;
    final maxDays = DateUtils.getDaysInMonth(year, month);
    if (day < 1 || day > maxDays) return null;
    final parsed = DateTime(year, month, day);
    if (parsed.isBefore(_firstDate) || parsed.isAfter(_lastDate)) return null;
    return parsed;
  }

  void _toggleInputMode() {
    if (_mode == _AccessiblePickerMode.input) {
      final parsed = _parseInputDate(_inputController.text);
      setState(() {
        if (parsed != null) {
          _selectedDate = parsed;
          _displayedYear = parsed.year;
          _displayedMonth = parsed.month;
        }
        _inputError = null;
        _mode = _AccessiblePickerMode.day;
      });
    } else {
      setState(() {
        _inputController.text = _formatInputDate(_selectedDate);
        _inputError = null;
        _mode = _AccessiblePickerMode.input;
      });
    }
  }

  void _confirm() {
    if (_mode == _AccessiblePickerMode.input) {
      final parsed = _parseInputDate(_inputController.text);
      if (parsed == null) {
        setState(() {
          _inputError =
              'يرجى إدخال تاريخ صحيح بصيغة يوم/شهر/سنة بين ${_formatInputDate(_firstDate)} و${_formatInputDate(_lastDate)}';
        });
        return;
      }
      Navigator.of(context).pop(parsed);
      return;
    }
    Navigator.of(context).pop(_selectedDate);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final textDirection = SettingsService.instance.textDirection;
    final selectedWeekday = HijriDateHelper.getDayOfWeek(_selectedDate);
    final selectedGregorian = HijriDateHelper.getGregorianDateString(_selectedDate);
    final fullSelectedHeader = '$selectedWeekday، $selectedGregorian';
    final displayedMonthName = HijriDateHelper.gregorianMonths[_displayedMonth - 1];
    final monthYearLabel = '$displayedMonthName $_displayedYear';
    final visibleHeight = math.max(
      140.0,
      media.size.height - media.viewInsets.bottom - media.viewPadding.vertical - 40.0,
    );
    final maxContentHeight = math.min(visibleHeight * 0.72, media.size.height * 0.72);

    return AlertDialog(
      key: const ValueKey('hijri_accessible_date_picker_dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: maxContentHeight,
          ),
          child: SingleChildScrollView(
            key: const ValueKey('hijri_picker_scroll_view'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header: picker title, mode toggle, and FULL unellipsized selected date
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: const Text(
                          'اختيار التاريخ',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryGreen,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('hijri_picker_mode_toggle_button'),
                      tooltip: _mode == _AccessiblePickerMode.input
                          ? 'التبديل إلى التقويم'
                          : 'التبديل إلى الإدخال',
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: Icon(
                        _mode == _AccessiblePickerMode.input
                            ? Icons.calendar_today_rounded
                            : Icons.edit_outlined,
                        color: AppColors.primaryGreen,
                      ),
                      onPressed: _toggleInputMode,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  fullSelectedHeader,
                  key: const ValueKey('hijri_picker_selected_date_header'),
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.primaryGreen,
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),

                if (_mode == _AccessiblePickerMode.input)
                  _buildInputMode(isDark)
                else ...[
                  // Month & Year Controls
                  _buildMonthYearControls(
                    monthYearLabel: monthYearLabel,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  if (_mode == _AccessiblePickerMode.year)
                    _buildYearGrid(media: media, textDirection: textDirection, isDark: isDark)
                  else
                    _buildDayGrid(
                      media: media,
                      textDirection: textDirection,
                      isDark: isDark,
                      monthName: displayedMonthName,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              key: const ValueKey('hijri_picker_cancel_button'),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'الإلغاء',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            FilledButton(
              key: const ValueKey('hijri_picker_confirm_button'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              onPressed: _confirm,
              child: const Text(
                'حسنًا',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMonthYearControls({
    required String monthYearLabel,
    required bool isDark,
  }) {
    final isYearMode = _mode == _AccessiblePickerMode.year;
    final yearToggleLabel = isYearMode
        ? 'العودة للأيام، $monthYearLabel'
        : 'اختيار العام، $monthYearLabel';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: yearToggleLabel,
          excludeSemantics: true,
          onTap: () {
            setState(() {
              _mode = isYearMode
                  ? _AccessiblePickerMode.day
                  : _AccessiblePickerMode.year;
            });
          },
          child: OutlinedButton.icon(
            key: const ValueKey('hijri_picker_year_toggle_button'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              foregroundColor: isDark ? AppColors.softGold : AppColors.primaryGreen,
            ),
            onPressed: () {
              setState(() {
                _mode = isYearMode
                    ? _AccessiblePickerMode.day
                    : _AccessiblePickerMode.year;
              });
            },
            icon: Icon(
              isYearMode ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
            ),
            label: Text(
              monthYearLabel,
              key: const ValueKey('hijri_picker_month_year_text'),
              softWrap: true,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        if (!isYearMode) ...[
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                key: const ValueKey('hijri_picker_prev_month_button'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onPressed: _canGoPrevMonth ? _goPrevMonth : null,
                icon: const Icon(Icons.chevron_right),
                label: const Text('الشهر السابق', softWrap: true),
              ),
              TextButton.icon(
                key: const ValueKey('hijri_picker_next_month_button'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onPressed: _canGoNextMonth ? _goNextMonth : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('الشهر التالي', softWrap: true),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDayGrid({
    required MediaQueryData media,
    required TextDirection textDirection,
    required bool isDark,
    required String monthName,
  }) {
    final daysInMonth = DateUtils.getDaysInMonth(_displayedYear, _displayedMonth);
    final today = _dateOnly(DateTime.now());
    final bodyLargeBase = Theme.of(context).textTheme.bodyLarge ??
        const TextStyle(fontSize: 18);
    final dayBaseFontSize = bodyLargeBase.fontSize ?? 18.0;
    final dayMeasureStyle = DefaultTextStyle.of(context).style.merge(
      bodyLargeBase.copyWith(fontSize: dayBaseFontSize, fontWeight: FontWeight.bold),
    );

    final samplePainter = TextPainter(
      text: TextSpan(text: '30', style: dayMeasureStyle),
      textDirection: textDirection,
      textScaler: media.textScaler,
    )..layout();

    final minCellWidth = math.max(56.0, samplePainter.width + 24.0);
    final minCellHeight = math.max(52.0, samplePainter.height + 10.0);
    const spacing = 8.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = ((maxWidth + spacing) / (minCellWidth + spacing))
            .floor()
            .clamp(3, 7);
        final cellWidth = (maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          key: const ValueKey('hijri_picker_day_grid'),
          spacing: spacing,
          runSpacing: spacing,
          children: List.generate(daysInMonth, (index) {
            final day = index + 1;
            final date = DateTime(_displayedYear, _displayedMonth, day);
            final isDisabled = date.isBefore(_firstDate) || date.isAfter(_lastDate);
            final isSelected = date.year == _selectedDate.year &&
                date.month == _selectedDate.month &&
                date.day == _selectedDate.day;
            final isToday = date.year == today.year &&
                date.month == today.month &&
                date.day == today.day;
            final weekdayName = HijriDateHelper.getDayOfWeek(date);
            final semanticLabel =
                '$day، $weekdayName، $day $monthName $_displayedYear م'
                '${isToday ? '، تاريخ اليوم' : ''}';

            return Semantics(
              button: true,
              enabled: !isDisabled,
              selected: isSelected,
              label: semanticLabel,
              excludeSemantics: true,
              onTap: isDisabled ? null : () => _selectDay(day),
              child: Material(
                color: isSelected
                    ? AppColors.primaryGreen
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : AppColors.primaryGreen.withValues(alpha: 0.06)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected
                        ? AppColors.primaryGreen
                        : (isToday
                            ? AppColors.accentGold
                            : Colors.transparent),
                    width: isToday || isSelected ? 1.8 : 1.0,
                  ),
                ),
                child: InkWell(
                  key: ValueKey('hijri_picker_day_$day'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: isDisabled ? null : () => _selectDay(day),
                  child: SizedBox(
                    width: cellWidth,
                    height: minCellHeight,
                    child: Center(
                      child: Text(
                        '$day',
                        key: ValueKey('hijri_picker_day_text_$day'),
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: bodyLargeBase.copyWith(
                          fontSize: dayBaseFontSize,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w600,
                          color: isDisabled
                              ? Colors.grey
                              : (isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white : Colors.black87)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildYearGrid({
    required MediaQueryData media,
    required TextDirection textDirection,
    required bool isDark,
  }) {
    final totalYears = _lastDate.year - _firstDate.year + 1;
    final bodyLargeBase = Theme.of(context).textTheme.bodyLarge ??
        const TextStyle(fontSize: 18);
    final yearBaseFontSize = bodyLargeBase.fontSize ?? 18.0;
    final yearMeasureStyle = DefaultTextStyle.of(context).style.merge(
      bodyLargeBase.copyWith(fontSize: yearBaseFontSize, fontWeight: FontWeight.bold),
    );
    final samplePainter = TextPainter(
      text: TextSpan(text: '2050', style: yearMeasureStyle),
      textDirection: textDirection,
      textScaler: media.textScaler,
    )..layout();

    final minCellWidth = math.max(96.0, samplePainter.width + 24.0);
    final minCellHeight = math.max(52.0, samplePainter.height + 10.0);
    const spacing = 8.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = ((maxWidth + spacing) / (minCellWidth + spacing))
            .floor()
            .clamp(2, 4);
        final cellWidth = (maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          key: const ValueKey('hijri_picker_year_grid'),
          spacing: spacing,
          runSpacing: spacing,
          children: List.generate(totalYears, (index) {
            final year = _firstDate.year + index;
            final isSelectedYear = year == _displayedYear;
            return Semantics(
              button: true,
              selected: isSelectedYear,
              label: '$year',
              excludeSemantics: true,
              onTap: () => _selectYear(year),
              child: Material(
                color: isSelectedYear
                    ? AppColors.primaryGreen
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : AppColors.primaryGreen.withValues(alpha: 0.06)),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  key: ValueKey('hijri_picker_year_$year'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _selectYear(year),
                  child: SizedBox(
                    width: cellWidth,
                    height: minCellHeight,
                    child: Center(
                      child: Text(
                        '$year',
                        key: ValueKey('hijri_picker_year_text_$year'),
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: bodyLargeBase.copyWith(
                          fontSize: yearBaseFontSize,
                          fontWeight:
                              isSelectedYear ? FontWeight.bold : FontWeight.w600,
                          color: isSelectedYear
                              ? Colors.white
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildInputMode(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'أدخل التاريخ بصيغة يوم/شهر/سنة',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 18),
        TextField(
          key: const ValueKey('hijri_picker_date_input'),
          controller: _inputController,
          keyboardType: TextInputType.datetime,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: 'التاريخ',
            hintText: '18/11/2026',
            helperText:
                'النطاق المتاح: ${_formatInputDate(_firstDate)} - ${_formatInputDate(_lastDate)}',
            helperMaxLines: 3,
            errorText: _inputError,
            errorMaxLines: 3,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onSubmitted: (_) => _confirm(),
        ),
      ],
    );
  }
}
