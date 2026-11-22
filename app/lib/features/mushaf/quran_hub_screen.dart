import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/widgets/app_navigation_drawer.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/portal_category_card.dart';

/// بوابة «القرآن الكريم وعلومه» (QuranHubScreen)
/// مقسمة إلى ١٠ محاور قرآنية مستقلة:
/// 1. القرآن المكتوب
/// 2. القرآن المسموع
/// 3. العلامات المرجعية
/// 4. المحفّظ
/// 5. التجويد
/// 6. خواطري
/// 7. البحث القرآني
/// 8. التفاسير
/// 9. الإعراب
/// 10. أسباب النزول
class QuranHubScreen extends StatelessWidget {
  final int initialTabIndex;

  const QuranHubScreen({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        drawer: const AppNavigationDrawer(),
        appBar: AppBar(
          title: Semantics(
            header: true,
            label: 'القرآن الكريم وعلومه',
            excludeSemantics: true,
            child: const Text('القرآن الكريم'),
          ),
          leading: Builder(
            builder: (ctx) => Semantics(
              label: 'open navigation menu',
              button: true,
              hint: 'افتح قائمة التنقل',
              child: IconButton(
                icon: const Icon(Icons.menu_rounded),
                tooltip: 'open navigation menu',
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: 'البحث في القرآن',
              onPressed: () => context.push('/search'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          children: [
            // 1. Serene Spiritual Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF0F3628), const Color(0xFF071E16)]
                      : [const Color(0xFF0F5B45), const Color(0xFF1B6B4E)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.accentGold.withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.menu_book_rounded, color: AppColors.accentGold, size: 36),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'كِتَابٌ أَنزَلْنَاهُ إِلَيْكَ مُبَارَكٌ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Amiri',
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'قراءة، تلاوات، حفظ، تجويد، وتدبر',
                          style: TextStyle(
                            color: Color(0xFFFFEFA6),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // 1. القرآن المكتوب
            PortalCategoryCard(
              numberText: '١',
              title: 'القرآن المكتوب',
              subtitle: 'قراءة السور والأجزاء والصفحات',
              icon: Icons.menu_book_rounded,
              color: AppColors.primaryGreen,
              onTap: () => context.push('/mushaf-reader'),
            ),

            // 2. القرآن المسموع
            PortalCategoryCard(
              numberText: '٢',
              title: 'القرآن المسموع',
              subtitle: 'الاستماع إلى السور كاملة بالقارئ المختار',
              icon: Icons.record_voice_over_rounded,
              color: const Color(0xFF1E8260),
              onTap: () => context.push('/audio'),
            ),

            // 3. العلامات المرجعية
            PortalCategoryCard(
              numberText: '٣',
              title: 'العلامات المرجعية',
              subtitle: 'الآيات المحفوظة',
              icon: Icons.bookmark_rounded,
              color: AppColors.accentGold,
              onTap: () => context.push('/mushaf-reader?tab=bookmarks'),
            ),

            // 4. المحفّظ
            PortalCategoryCard(
              numberText: '٤',
              title: 'المحفّظ',
              subtitle: 'تكرار الآيات ومتابعة الحفظ',
              icon: Icons.psychology_rounded,
              color: const Color(0xFF2E7D32),
              onTap: () => context.push('/memorization'),
            ),

            // 5. التجويد
            PortalCategoryCard(
              numberText: '٥',
              title: 'التجويد',
              subtitle: 'أحكام التلاوة ودليل ألوان المصحف',
              icon: Icons.palette_rounded,
              color: const Color(0xFF16A085),
              onTap: () => context.push('/tajweed'),
            ),

            // 6. خواطري
            PortalCategoryCard(
              numberText: '٦',
              title: 'خواطري',
              subtitle: 'تدوين وحفظ التدبرات على الآيات',
              icon: Icons.edit_note_rounded,
              color: const Color(0xFFB8860B),
              onTap: () => context.push('/notes'),
            ),

            // 7. البحث القرآني
            PortalCategoryCard(
              numberText: '٧',
              title: 'البحث القرآني',
              subtitle: 'البحث في الآيات والسور محلياً',
              icon: Icons.search_rounded,
              color: const Color(0xFF1B5E20),
              onTap: () => context.push('/search'),
            ),

            // 8. التفاسير
            PortalCategoryCard(
              numberText: '٨',
              title: 'التفاسير',
              subtitle: 'عرض ومقارنة كتب التفسير للآيات',
              icon: Icons.auto_stories_rounded,
              color: const Color(0xFFB8893A),
              onTap: () => context.push('/comparative-tafsir'),
            ),

            // 9. الإعراب
            PortalCategoryCard(
              numberText: '٩',
              title: 'الإعراب',
              subtitle: 'إعراب الآيات وبيان وجوه النحو',
              icon: Icons.text_format_rounded,
              color: const Color(0xFF0F5B45),
              onTap: () => context.push('/quran-irab'),
            ),

            // 10. أسباب النزول
            PortalCategoryCard(
              numberText: '١٠',
              title: 'أسباب النزول',
              subtitle: 'عرض سياق تنزيل الآيات المتاحة',
              icon: Icons.history_edu_rounded,
              color: const Color(0xFF25739B),
              onTap: () => context.push('/quran-asbab-nuzul'),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
