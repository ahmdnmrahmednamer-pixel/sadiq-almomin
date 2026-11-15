import '../services/settings_service.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppDropdownOption<T> {
  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;

  const AppDropdownOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
  });
}

/// Unified, accessible Dropdown selector component used across تطبيق صديق المؤمن
/// whenever a control has multiple options. Built with full native Semantics
/// for screen readers without requiring any accessibility toggle.
class AppDropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<AppDropdownOption<T>> options;
  final ValueChanged<T> onChanged;
  final IconData? prefixIcon;
  final String? helperText;
  final bool dense;

  const AppDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.prefixIcon,
    this.helperText,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uniqueOptions = <AppDropdownOption<T>>[];
    final seenValues = <T>{};
    for (final opt in options) {
      if (seenValues.add(opt.value)) {
        uniqueOptions.add(opt);
      }
    }

    final T? effectiveValue = uniqueOptions.isEmpty
        ? null
        : (uniqueOptions.any((o) => o.value == value)
            ? value
            : uniqueOptions.first.value);
    final selectedOption =
        uniqueOptions.where((o) => o.value == effectiveValue).firstOrNull;

    return Semantics(
      container: true,
      label: '$label، الاختيار الحالي: ${selectedOption?.label ?? ""}',
      hint: 'قائمة منسدلة، انقر لاختيار عنصر آخر',
      child: Directionality(
        textDirection: SettingsService.instance.textDirection,
        child: DropdownButtonFormField<T>(
          initialValue: effectiveValue,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.primaryGreen,
          ),
          dropdownColor: isDark ? const Color(0xFF1A2420) : Colors.white,
          style: TextStyle(
            fontFamily: 'Amiri',
            fontSize: dense ? 13.5 : 14.5,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF18221E),
          ),
          decoration: InputDecoration(
            labelText: label,
            helperText: helperText,
            isDense: dense,
            filled: true,
            fillColor: isDark
                ? const Color(0xFF16201C)
                : AppColors.primaryGreen.withValues(alpha: 0.04),
            prefixIcon: prefixIcon != null
                ? ExcludeSemantics(
                    child: Icon(
                      prefixIcon,
                      color: AppColors.primaryGreen,
                      size: dense ? 18 : 20,
                    ),
                  )
                : null,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: dense ? 10 : 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: AppColors.primaryGreen.withValues(alpha: 0.25),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: AppColors.primaryGreen.withValues(alpha: 0.25),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.accentGold,
                width: 1.6,
              ),
            ),
          ),
          items: uniqueOptions.map((opt) {
            return DropdownMenuItem<T>(
              value: opt.value,
              child: Row(
                children: [
                  if (opt.icon != null) ...[
                    ExcludeSemantics(
                      child: Icon(
                        opt.icon,
                        size: 18,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      opt.subtitle != null && opt.subtitle!.isNotEmpty
                          ? '${opt.label} (${opt.subtitle})'
                          : opt.label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (newVal) {
            if (newVal != null) {
              onChanged(newVal);
            }
          },
        ),
      ),
    );
  }
}

/// Compact pill-shaped dropdown for AppBars and toolbars
class AppToolbarDropdown<T> extends StatelessWidget {
  final String semanticLabel;
  final T value;
  final List<AppDropdownOption<T>> options;
  final ValueChanged<T> onChanged;
  final IconData? icon;

  const AppToolbarDropdown({
    super.key,
    required this.semanticLabel,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uniqueOptions = <AppDropdownOption<T>>[];
    final seenValues = <T>{};
    for (final opt in options) {
      if (seenValues.add(opt.value)) {
        uniqueOptions.add(opt);
      }
    }

    final T? effectiveValue = uniqueOptions.isEmpty
        ? null
        : (uniqueOptions.any((o) => o.value == value)
            ? value
            : uniqueOptions.first.value);
    final selectedOption =
        uniqueOptions.where((o) => o.value == effectiveValue).firstOrNull;

    return Semantics(
      container: true,
      label: '$semanticLabel: ${selectedOption?.label ?? ""}',
      hint: 'قائمة منسدلة لتغيير $semanticLabel',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.primaryGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.accentGold.withValues(alpha: 0.45),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: effectiveValue,
            isDense: true,
            icon: const Icon(
              Icons.arrow_drop_down_rounded,
              color: AppColors.accentGold,
              size: 20,
            ),
            dropdownColor: isDark ? const Color(0xFF1A2420) : Colors.white,
            style: TextStyle(
              fontFamily: 'Amiri',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppColors.primaryGreen,
            ),
            items: uniqueOptions.map((opt) {
              return DropdownMenuItem<T>(
                value: opt.value,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (opt.icon != null) ...[
                      ExcludeSemantics(
                        child: Icon(opt.icon, size: 15, color: AppColors.primaryGreen),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        opt.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) onChanged(val);
            },
          ),
        ),
      ),
    );
  }
}


/// Dropdown selector with a dedicated audio preview button right beside it.
/// Enables selecting a Sheikh (Reciter) or Muezzin (Adhan voice) from the dropdown
/// and instantly listening to a high-fidelity audio sample.
class AppAudioDropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<AppDropdownOption<T>> options;
  final ValueChanged<T> onChanged;
  final VoidCallback onPreviewPressed;
  final bool isPlaying;
  final IconData? prefixIcon;
  final String? helperText;
  final bool dense;
  final String previewButtonLabel;
  final String? previewTooltip;

  const AppAudioDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.onPreviewPressed,
    this.isPlaying = false,
    this.prefixIcon,
    this.helperText,
    this.dense = false,
    this.previewButtonLabel = 'استماع',
    this.previewTooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 1. The Dropdown
        Expanded(
          child: AppDropdownField<T>(
            label: label,
            value: value,
            options: options,
            onChanged: onChanged,
            prefixIcon: prefixIcon,
            helperText: helperText,
            dense: dense,
          ),
        ),
        const SizedBox(width: 8),

        // 2. Audio Preview Button right beside the Dropdown
        Semantics(
          button: true,
          label: previewTooltip ?? (isPlaying ? 'إيقاف الاستماع' : 'استماع عينة من $label'),
          child: Container(
            margin: EdgeInsets.only(bottom: helperText != null ? 20 : 0),
            child: Material(
              color: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: isPlaying
                      ? const LinearGradient(
                          colors: [Color(0xFFDC2626), Color(0xFFB91C1C)],
                        )
                      : const LinearGradient(
                          colors: [AppColors.primaryGreen, AppColors.secondaryGreen],
                        ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: (isPlaying ? Colors.red : AppColors.primaryGreen).withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onPreviewPressed,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: dense ? 10 : 12,
                      vertical: dense ? 10 : 13,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPlaying ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                          color: Colors.white,
                          size: dense ? 18 : 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isPlaying ? 'إيقاف' : previewButtonLabel,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: dense ? 11.5 : 12.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
