import 'package:flutter/material.dart';
import '../../../core/models/memorization_item.dart';
import '../../../core/models/surah.dart';
import '../../../core/theme/app_theme.dart';

/// Configuration panel for surah range, audio loop repeats, delay, and hide-to-test modes.
class MemorizationControlsPanel extends StatelessWidget {
  final bool isDark;
  final List<Surah> surahs;
  final int selectedSurahId;
  final Surah? currentSurah;
  final int fromAyah;
  final int toAyah;
  final int ayahRepeatTarget;
  final int rangeRepeatTarget;
  final int delaySeconds;
  final MemorizationHideMode hideMode;
  final ValueChanged<int> onSurahChanged;
  final ValueChanged<int> onFromAyahChanged;
  final ValueChanged<int> onToAyahChanged;
  final ValueChanged<int> onAyahRepeatChanged;
  final ValueChanged<int> onRangeRepeatChanged;
  final ValueChanged<int> onDelayChanged;
  final ValueChanged<MemorizationHideMode> onHideModeChanged;
  final VoidCallback onRevealAllWords;
  final VoidCallback onHideAllWords;

  const MemorizationControlsPanel({
    super.key,
    required this.isDark,
    required this.surahs,
    required this.selectedSurahId,
    required this.currentSurah,
    required this.fromAyah,
    required this.toAyah,
    required this.ayahRepeatTarget,
    required this.rangeRepeatTarget,
    required this.delaySeconds,
    required this.hideMode,
    required this.onSurahChanged,
    required this.onFromAyahChanged,
    required this.onToAyahChanged,
    required this.onAyahRepeatChanged,
    required this.onRangeRepeatChanged,
    required this.onDelayChanged,
    required this.onHideModeChanged,
    required this.onRevealAllWords,
    required this.onHideAllWords,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScaler = MediaQuery.textScalerOf(context);
          final isLargeScale = textScaler.scale(12) > 15;
          final isNarrow = constraints.maxWidth < 380;
          final stackRow1 = isLargeScale || isNarrow;
          final stackNumberSelectors = isLargeScale && constraints.maxWidth < 340;

          // Compute responsive repeat badge width:
          // 3 per row on wide viewports, 2 per row when constrained or large text scale, full width on ultra narrow
          final double? badgeWidth;
          if (!isLargeScale && constraints.maxWidth >= 380) {
            badgeWidth = ((constraints.maxWidth - 16) / 3).floorToDouble();
          } else if (constraints.maxWidth >= 280) {
            badgeWidth = ((constraints.maxWidth - 8) / 2).floorToDouble();
          } else {
            badgeWidth = constraints.maxWidth;
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Row 1: Surah Selection & Ayah Bounds Pickers
              if (stackRow1) ...[
                _buildSurahDropdown(),
                const SizedBox(height: 6),
                if (stackNumberSelectors) ...[
                  _buildNumberSelector(
                    key: const Key('memorization_from_ayah_dropdown'),
                    label: 'من آية',
                    value: fromAyah,
                    max: currentSurah?.ayahCount ?? 7,
                    onChanged: onFromAyahChanged,
                  ),
                  const SizedBox(height: 6),
                  _buildNumberSelector(
                    key: const Key('memorization_to_ayah_dropdown'),
                    label: 'إلى آية',
                    value: toAyah,
                    max: currentSurah?.ayahCount ?? 7,
                    onChanged: onToAyahChanged,
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: _buildNumberSelector(
                          key: const Key('memorization_from_ayah_dropdown'),
                          label: 'من آية',
                          value: fromAyah,
                          max: currentSurah?.ayahCount ?? 7,
                          onChanged: onFromAyahChanged,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildNumberSelector(
                          key: const Key('memorization_to_ayah_dropdown'),
                          label: 'إلى آية',
                          value: toAyah,
                          max: currentSurah?.ayahCount ?? 7,
                          onChanged: onToAyahChanged,
                        ),
                      ),
                    ],
                  ),
                ],
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: _buildSurahDropdown(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _buildNumberSelector(
                        key: const Key('memorization_from_ayah_dropdown'),
                        label: 'من آية',
                        value: fromAyah,
                        max: currentSurah?.ayahCount ?? 7,
                        onChanged: onFromAyahChanged,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: _buildNumberSelector(
                        key: const Key('memorization_to_ayah_dropdown'),
                        label: 'إلى آية',
                        value: toAyah,
                        max: currentSurah?.ayahCount ?? 7,
                        onChanged: onToAyahChanged,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),

              // Row 2: Loop Target Controls (Ayah Repeats, Range Repeats, Delay) - Responsive Reflow
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildCompactBadge(
                    key: const Key('badge_ayah_repeat'),
                    title: 'تكرار الآية',
                    value: ayahRepeatTarget >= 999 ? 'مستمر' : '${ayahRepeatTarget}x',
                    options: const [1, 3, 5, 7, 10, 999],
                    onSelected: onAyahRepeatChanged,
                    width: badgeWidth,
                  ),
                  _buildCompactBadge(
                    key: const Key('badge_range_repeat'),
                    title: 'تكرار المقطع',
                    value: rangeRepeatTarget >= 999 ? 'مستمر' : '${rangeRepeatTarget}x',
                    options: const [1, 2, 3, 5, 999],
                    onSelected: onRangeRepeatChanged,
                    width: badgeWidth,
                  ),
                  _buildCompactBadge(
                    key: const Key('badge_delay'),
                    title: 'وقفة الترديد',
                    value: delaySeconds == 0 ? 'بدون' : '$delaySeconds ث',
                    options: const [0, 1, 2, 3, 5],
                    onSelected: onDelayChanged,
                    width: badgeWidth,
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Row 3: Hide-To-Test Modes (FR-MEM-002) - Responsive Reflow
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildHideModeChip(
                    'كامل الآية ظاهر',
                    MemorizationHideMode.none,
                    Icons.visibility,
                    const Key('chip_hide_mode_none'),
                  ),
                  _buildHideModeChip(
                    'إخفاء النصف الثاني',
                    MemorizationHideMode.secondHalf,
                    Icons.hourglass_bottom,
                    const Key('chip_hide_mode_secondHalf'),
                  ),
                  _buildHideModeChip(
                    'إخفاء كلمات متناوبة',
                    MemorizationHideMode.everyNthWord,
                    Icons.shuffle,
                    const Key('chip_hide_mode_everyNthWord'),
                  ),
                  _buildHideModeChip(
                    'إخفاء كامل (غيباً)',
                    MemorizationHideMode.allWords,
                    Icons.visibility_off,
                    const Key('chip_hide_mode_allWords'),
                  ),
                  if (hideMode != MemorizationHideMode.none) ...[
                    TextButton.icon(
                      key: const Key('memorization_reveal_all_button'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('كشف الكل', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: onRevealAllWords,
                    ),
                    TextButton.icon(
                      key: const Key('memorization_hide_all_button'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('إخفاء الكل', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: onHideAllWords,
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSurahDropdown() {
    return Container(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          key: const Key('memorization_surah_dropdown'),
          isExpanded: true,
          value: surahs.any((s) => s.id == selectedSurahId)
              ? selectedSurahId
              : (surahs.isNotEmpty ? surahs.first.id : null),
          items: surahs.map((s) {
            return DropdownMenuItem<int>(
              value: s.id,
              child: Text(
                '${s.id}. سورة ${s.nameAr}',
                softWrap: true,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null && val != selectedSurahId) {
              onSurahChanged(val);
            }
          },
        ),
      ),
    );
  }

  Widget _buildNumberSelector({
    Key? key,
    required String label,
    required int value,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              softWrap: true,
              style: const TextStyle(fontSize: 11, color: AppColors.mutedText),
            ),
          ),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                key: key,
                value: value.clamp(1, max < 1 ? 1 : max),
                items: List.generate(max < 1 ? 1 : max, (i) => i + 1).map((n) {
                  return DropdownMenuItem<int>(
                    value: n,
                    child: Text('$n', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) onChanged(val);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactBadge({
    Key? key,
    required String title,
    required String value,
    required List<int> options,
    required ValueChanged<int> onSelected,
    double? width,
  }) {
    final badgeWidget = PopupMenuButton<int>(
      key: key,
      tooltip: title,
      onSelected: onSelected,
      itemBuilder: (context) {
        return options.map((opt) {
          final text = opt >= 999 ? 'مستمر (∞)' : (title.contains('وقفة') ? '$opt ثوانٍ' : '$opt مرات');
          return PopupMenuItem<int>(
            value: opt,
            child: Text(text),
          );
        }).toList();
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        decoration: BoxDecoration(
          color: AppColors.primaryGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              softWrap: true,
              style: const TextStyle(fontSize: 10.5, color: AppColors.mutedText),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              textAlign: TextAlign.center,
              softWrap: true,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
            ),
          ],
        ),
      ),
    );

    if (width != null) {
      return SizedBox(width: width, child: badgeWidget);
    }
    return badgeWidget;
  }

  Widget _buildHideModeChip(String title, MemorizationHideMode mode, IconData icon, Key key) {
    final isSelected = hideMode == mode;
    return ChoiceChip(
      key: key,
      selected: isSelected,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      onSelected: (selected) {
        if (selected) {
          onHideModeChanged(mode);
        }
      },
      avatar: Icon(icon, size: 16, color: isSelected ? Colors.white : AppColors.primaryGreen),
      label: Text(
        title,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selectedColor: AppColors.primaryGreen,
      labelStyle: TextStyle(color: isSelected ? Colors.white : null),
    );
  }
}
