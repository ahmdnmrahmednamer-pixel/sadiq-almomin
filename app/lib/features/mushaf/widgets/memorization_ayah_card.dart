import 'package:flutter/material.dart';
import '../../../core/models/ayah.dart';
import '../../../core/models/memorization_item.dart';
import '../../../core/services/memorization_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/theme/app_theme.dart';

/// Ayah card with interactive word-level masking and spaced-repetition Leitner rating buttons.
class MemorizationAyahCard extends StatelessWidget {
  final Ayah ayah;
  final int surahId;
  final bool isCurrentPlaying;
  final bool isDelaying;
  final int remainingDelaySeconds;
  final int currentAyahRepeat;
  final int ayahRepeatTarget;
  final MemorizationHideMode hideMode;
  final Set<String> revealedWords;
  final bool isDark;
  final void Function(int ayahNumber, int wordIndex) onToggleWordReveal;
  final void Function(Ayah ayah, MemorizationRating rating) onRateAyah;

  const MemorizationAyahCard({
    super.key,
    required this.ayah,
    required this.surahId,
    required this.isCurrentPlaying,
    required this.isDelaying,
    required this.remainingDelaySeconds,
    required this.currentAyahRepeat,
    required this.ayahRepeatTarget,
    required this.hideMode,
    required this.revealedWords,
    required this.isDark,
    required this.onToggleWordReveal,
    required this.onRateAyah,
  });

  @override
  Widget build(BuildContext context) {
    final memItem = MemorizationService.instance.getItem(surahId, ayah.ayahNumber);
    final words = MemorizationMaskHelper.splitAyahWords(ayah.cleanTextUthmani);

    return Card(
      elevation: isCurrentPlaying ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isCurrentPlaying ? AppColors.accentGold : Colors.transparent,
          width: isCurrentPlaying ? 2 : 0,
        ),
      ),
      color: isCurrentPlaying
          ? (isDark ? const Color(0xFF233020) : const Color(0xFFF0F7F2))
          : (isDark ? AppColors.darkSurface : Colors.white),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar: Ayah Number + Spaced-Repetition Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isCurrentPlaying ? AppColors.accentGold : AppColors.primaryGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'الآية ${ayah.ayahNumber}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isCurrentPlaying ? Colors.black : AppColors.primaryGreen,
                        ),
                      ),
                    ),
                    if (isCurrentPlaying) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isDelaying
                              ? 'وقفة للترديد ($remainingDelaySeconds ث)'
                              : 'تكرار $currentAyahRepeat من ${ayahRepeatTarget >= 999 ? "∞" : ayahRepeatTarget}',
                          style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                // Leitner Status Badge
                if (memItem != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: memItem.leitnerBox >= 3 ? Colors.green.withValues(alpha: 0.15) : Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'الصندوق ${memItem.leitnerBox}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: memItem.leitnerBox >= 3 ? Colors.green.shade800 : Colors.amber.shade900,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Ayah Text with Interactive Masking
            if (hideMode == MemorizationHideMode.none)
              Semantics(
                container: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    '${ayah.cleanTextUthmani} ﴿${SettingsService.instance.formatAyahNumber(ayah.ayahNumber)}﴾',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      height: 1.8,
                      fontWeight: isCurrentPlaying ? FontWeight.bold : FontWeight.w500,
                      fontFamilyFallback: const ['Traditional Arabic', 'Amiri', 'serif'],
                    ),
                  ),
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ...List.generate(words.length, (wordIdx) {
                    final isRevealed = revealedWords.contains('${ayah.ayahNumber}:$wordIdx');
                    final isEligible = MemorizationMaskHelper.isWordMasked(
                      wordIndex: wordIdx,
                      totalWords: words.length,
                      mode: hideMode,
                      isRevealed: false,
                    );
                    final isMasked = isEligible && !isRevealed;

                    if (isMasked) {
                      // Interactive blurred / hidden pill with clear indexed label and zero hidden text leakage
                      return Semantics(
                        label: 'الكلمة ${wordIdx + 1} مخفية، انقر للإظهار',
                        button: true,
                        onTap: () => onToggleWordReveal(ayah.ayahNumber, wordIdx),
                        excludeSemantics: true,
                        child: InkWell(
                          onTap: () => onToggleWordReveal(ayah.ayahNumber, wordIdx),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: isDark ? 0.25 : 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.touch_app, size: 12, color: AppColors.mutedText),
                                SizedBox(width: 4),
                                Text(
                                  '••••••',
                                  style: TextStyle(
                                    letterSpacing: 2,
                                    color: AppColors.mutedText,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    // Naturally visible plain text (words not subject to masking in this mode)
                    if (!isEligible) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                        child: Text(
                          words[wordIdx],
                          style: TextStyle(
                            fontSize: 20,
                            height: 1.8,
                            fontWeight: isCurrentPlaying ? FontWeight.bold : FontWeight.w500,
                            fontFamilyFallback: const ['Traditional Arabic', 'Amiri', 'serif'],
                          ),
                        ),
                      );
                    }

                    // Revealed word (eligible word revealed by user tap; can be tapped again to re-hide)
                    return Semantics(
                      label: 'الكلمة ${wordIdx + 1}: ${words[wordIdx]}، مظهرة، انقر للإخفاء',
                      button: true,
                      onTap: () => onToggleWordReveal(ayah.ayahNumber, wordIdx),
                      excludeSemantics: true,
                      child: InkWell(
                        onTap: () => onToggleWordReveal(ayah.ayahNumber, wordIdx),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.accentGold.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            words[wordIdx],
                            style: TextStyle(
                              fontSize: 20,
                              height: 1.8,
                              fontWeight: isCurrentPlaying ? FontWeight.bold : FontWeight.w500,
                              color: AppColors.accentGold,
                              fontFamilyFallback: const ['Traditional Arabic', 'Amiri', 'serif'],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    child: Text(
                      '﴿${SettingsService.instance.formatAyahNumber(ayah.ayahNumber)}﴾',
                      style: TextStyle(
                        fontSize: 20,
                        height: 1.8,
                        fontWeight: isCurrentPlaying ? FontWeight.bold : FontWeight.w500,
                        fontFamilyFallback: const ['Traditional Arabic', 'Amiri', 'serif'],
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),

            // Rating / Leitner Evaluation Buttons (FR-MEM-003)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceEvenly,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildRatingButton(
                    label: 'متقن',
                    icon: Icons.check_circle_outline,
                    color: Colors.green,
                    onTap: () => onRateAyah(ayah, MemorizationRating.easy),
                  ),
                  _buildRatingButton(
                    label: 'تثبيت',
                    icon: Icons.timelapse,
                    color: Colors.amber.shade800,
                    onTap: () => onRateAyah(ayah, MemorizationRating.hard),
                  ),
                  _buildRatingButton(
                    label: 'نسيت',
                    icon: Icons.replay,
                    color: Colors.redAccent,
                    onTap: () => onRateAyah(ayah, MemorizationRating.forgot),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
