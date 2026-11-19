import 'package:flutter/material.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/theme/app_theme.dart';

/// Bottom bar for Quran memorization audio loop controls.
class MemorizationPlaybackBar extends StatelessWidget {
  final bool isDark;
  final bool isPlaying;
  final int currentAyahNumber;
  final int fromAyah;
  final int toAyah;
  final int currentRangeRepeat;
  final int rangeRepeatTarget;
  final VoidCallback onPlayPause;
  final VoidCallback? onStop;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onSelectReciter;

  const MemorizationPlaybackBar({
    super.key,
    required this.isDark,
    required this.isPlaying,
    required this.currentAyahNumber,
    required this.fromAyah,
    required this.toAyah,
    required this.currentRangeRepeat,
    required this.rangeRepeatTarget,
    required this.onPlayPause,
    required this.onStop,
    required this.onPrev,
    required this.onNext,
    required this.onSelectReciter,
  });

  @override
  Widget build(BuildContext context) {
    final reciter = SettingsService.instance.currentReciter;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status and Reciter Header (responsive wrap, full text, no ellipsis/clamp/shrink)
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runAlignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      const WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: ExcludeSemantics(
                          child: Padding(
                            padding: EdgeInsets.only(left: 4.0),
                            child: Icon(Icons.record_voice_over, size: 14, color: AppColors.mutedText),
                          ),
                        ),
                      ),
                      TextSpan(
                        text: 'القارئ: ${reciter.nameAr}',
                        style: const TextStyle(fontSize: 11, color: AppColors.mutedText),
                      ),
                    ],
                  ),
                ),
                Text(
                  isPlaying
                      ? 'الآية: $currentAyahNumber · مقطع $currentRangeRepeat/${rangeRepeatTarget >= 999 ? "∞" : rangeRepeatTarget}'
                      : 'المقطع: $fromAyah إلى $toAyah',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Playback Buttons Row (wrapped controls when needed, every target >= 48px, no FittedBox)
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                // Stop Button
                IconButton(
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.stop_circle_outlined, size: 28),
                  tooltip: 'إيقاف كامل',
                  onPressed: onStop,
                ),

                // Previous Ayah
                IconButton(
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.skip_previous_rounded, size: 30),
                  tooltip: 'الآية السابقة',
                  onPressed: onPrev,
                ),

                // Main Play / Pause Button
                Container(
                  decoration: const BoxDecoration(
                    color: AppColors.primaryGreen,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    iconSize: 34,
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    color: Colors.white,
                    tooltip: isPlaying ? 'إيقاف مؤقت' : 'بدء التكرار والتحفيظ',
                    onPressed: onPlayPause,
                  ),
                ),

                // Next Ayah
                IconButton(
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.skip_next_rounded, size: 30),
                  tooltip: 'الآية التالية',
                  onPressed: onNext,
                ),

                // Quick Reciter change
                IconButton(
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.tune, size: 24),
                  tooltip: 'اختيار قارئ آخر',
                  onPressed: onSelectReciter,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
