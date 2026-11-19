import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// بطاقة البوابات الرئيسية الإيمانية — موحدة التصميم والنفاذية عبر كافة الأقسام
class PortalCategoryCard extends StatelessWidget {
  final String numberText;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? badgeText;

  const PortalCategoryCard({
    super.key,
    required this.numberText,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trimmedBadge = badgeText?.trim();
    final hasBadge = trimmedBadge != null && trimmedBadge.isNotEmpty;
    final semanticLabel = [title, if (hasBadge) trimmedBadge, if (subtitle.trim().isNotEmpty) subtitle].join('، ');

    final iconBox = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Icon(icon, color: color, size: 26),
      ),
    );

    final numberPill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        numberText,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );

    final badgePill = hasBadge
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.accentGold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.accentGold.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              trimmedBadge,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppColors.accentGold,
              ),
            ),
          )
        : null;

    final titleText = Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.2,
      ),
    );

    final subtitleText = Text(
      subtitle,
      style: TextStyle(
        fontSize: 12.5,
        color: isDark ? Colors.white70 : Colors.grey.shade600,
        height: 1.35,
      ),
    );

    final arrowCircle = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E3327) : const Color(0xFFF1F5F2),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14,
        color: Colors.grey,
      ),
    );

    return Semantics(
      label: semanticLabel,
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF14241C) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: color.withValues(alpha: isDark ? 0.3 : 0.22),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textScale =
                      MediaQuery.textScalerOf(context).scale(16) / 16.0;
                  final useStackedLayout =
                      textScale >= 1.35 || constraints.maxWidth < 290;

                  if (useStackedLayout) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  iconBox,
                                  numberPill,
                                  if (badgePill != null) badgePill,
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            arrowCircle,
                          ],
                        ),
                        const SizedBox(height: 10),
                        titleText,
                        if (subtitle.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          subtitleText,
                        ],
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      iconBox,
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                numberPill,
                                titleText,
                                if (badgePill != null) badgePill,
                              ],
                            ),
                            if (subtitle.trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              subtitleText,
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      arrowCircle,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
