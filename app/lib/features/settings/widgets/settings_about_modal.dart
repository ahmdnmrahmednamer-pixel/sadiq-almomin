import '../../../core/services/settings_service.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

void showSettingsAboutModal(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final media = MediaQuery.of(ctx);
      final textScale = media.textScaler.scale(1.0);
      final isLargeText = textScale >= 1.35;
      final isNarrow = media.size.width <= 420;
      final useCompactChrome = isLargeText || isNarrow;

      final headerWidget = Semantics(
        header: true,
        container: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mosque_rounded,
                color: AppColors.primaryGreen,
                size: 26,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'عن تطبيق صديق المؤمن',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'منظومة إسلامية شاملة',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.lightText,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

      final maxScrollHeight = media.size.height * (isLargeText ? 0.74 : 0.72);

      return Directionality(
        textDirection: SettingsService.instance.textDirection,
        child: AlertDialog(
          key: const ValueKey('settings_about_dialog'),
          insetPadding: useCompactChrome
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 20)
              : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: isLargeText
              ? const EdgeInsets.fromLTRB(16, 16, 16, 6)
              : const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          title: isLargeText ? null : headerWidget,
          content: SizedBox(
            width: double.maxFinite,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxScrollHeight),
              child: SingleChildScrollView(
                key: const ValueKey('settings_about_scroll_view'),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isLargeText) ...[
                      headerWidget,
                      const SizedBox(height: 14),
                    ],

                    // Section Header
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            color: AppColors.accentGold,
                            size: 18,
                          ),
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'مميزات التطبيق ومعالمه الكبرى:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.primaryGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // 1. Quran
                    _buildFeaturePillar(
                      isDark: isDark,
                      isLargeText: isLargeText,
                      icon: Icons.menu_book_rounded,
                      iconColor: const Color(0xFF1E7E34),
                      title: 'محراب القرآن الكريم وتدبر علومه',
                      description: 'القرآن والتفسير والإعراب',
                    ),

                    // 2. Prayer & Adhan Studio
                    _buildFeaturePillar(
                      isDark: isDark,
                      isLargeText: isLargeText,
                      icon: Icons.access_time_filled_rounded,
                      iconColor: const Color(0xFFD97706),
                      title: 'مواقيت الصلاة ومُشغِّل الأذان والإقامة',
                      description: 'مواقيت الصلاة والأذان والإقامة',
                    ),

                    // 3. Audio Library & Reciters
                    _buildFeaturePillar(
                      isDark: isDark,
                      isLargeText: isLargeText,
                      icon: Icons.record_voice_over_rounded,
                      iconColor: const Color(0xFF2563EB),
                      title: 'المكتبة الصوتية وديوان كبار القراء',
                      description: 'تلاوات القرآن الكريم',
                    ),

                    // 4. Adhkar, Hadith & Smart Tasbih
                    _buildFeaturePillar(
                      isDark: isDark,
                      isLargeText: isLargeText,
                      icon: Icons.fingerprint_rounded,
                      iconColor: const Color(0xFF7C3AED),
                      title: 'حصن المسلم والسنة النبوية والسبحة',
                      description: 'أذكار اليوم والسبحة',
                    ),

                    // 5. Worship Services, Qibla & Zakat
                    _buildFeaturePillar(
                      isDark: isDark,
                      isLargeText: isLargeText,
                      icon: Icons.explore_rounded,
                      iconColor: const Color(0xFF059669),
                      title: 'محاريب العبادات والقبلة والزكاة والأنبياء',
                      description: 'القبلة والزكاة وقصص الأنبياء',
                    ),

                    // 6. Purity of Purpose & No-Ads Pledge
                    _buildFeaturePillar(
                      isDark: isDark,
                      isLargeText: isLargeText,
                      icon: Icons.verified_user_rounded,
                      iconColor: const Color(0xFF0F766E),
                      title: 'صفاء المقصد ونقاء العهد الوقفـي',
                      description: 'تطبيق مجاني بلا إعلانات',
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('settings_about_close_button'),
              onPressed: () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
                minimumSize: const Size(48, 48),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              child: const Text(
                'إغلاق',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
      );
    },
  );
}

Widget _buildFeaturePillar({
  required bool isDark,
  required bool isLargeText,
  required IconData icon,
  required Color iconColor,
  required String title,
  required String description,
}) {
  final iconBox = Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: iconColor.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, color: iconColor, size: 20),
  );

  final titleWidget = Text(
    title,
    style: TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 13,
      color: isDark ? AppColors.softGold : AppColors.primaryGreen,
    ),
  );

  final descriptionWidget = Text(
    description,
    style: TextStyle(
      fontSize: 11.8,
      height: 1.55,
      color: isDark ? Colors.white70 : const Color(0xFF4A5568),
    ),
  );

  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF1E2824) : const Color(0xFFFBFBFB),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.02),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: isLargeText
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  iconBox,
                  const SizedBox(width: 10),
                  Expanded(child: titleWidget),
                ],
              ),
              const SizedBox(height: 8),
              descriptionWidget,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              iconBox,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleWidget,
                    const SizedBox(height: 4),
                    descriptionWidget,
                  ],
                ),
              ),
            ],
          ),
  );
}
