import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/widgets/app_navigation_drawer.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/portal_category_card.dart';

/// بوابة «القرآن الكريم وعلومه» (QuranHubScreen)
/// مقسمة إلى ٦ محاور قرآنية رئيسية واضحة ومستقلة:
/// 1. القرآن الكريم مكتوب
/// 2. القرآن الكريم مسموع
/// 3. البحث في القرآن
/// 4. التفاسير
/// 5. الإعراب
/// 6. أسباب نزول الآيات
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
          title: const Text('القرآن الكريم وعلومه'),
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
                  color: AppColors.accentGold.withOpacity(0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.35 : 0.1),
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
                          'تلاوة، استماع، تدبر، إعراب، وأسباب نزول',
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

            // 1. القرآن الكريم مكتوب
            PortalCategoryCard(
              numberText: '١',
              title: 'القرآن الكريم مكتوب',
              subtitle: 'المصحف الشريف كاملاً بالرسم العثماني المعتمد مع قلب الصفحات وتفسير الآيات',
              icon: Icons.menu_book_rounded,
              color: AppColors.primaryGreen,
              badgeText: '٦٠٤ صفحات',
              onTap: () => context.push('/mushaf-reader'),
            ),

            // 2. القرآن الكريم مسموع
            PortalCategoryCard(
              numberText: '٢',
              title: 'القرآن الكريم مسموع',
              subtitle: 'تلاوات خاشعة مرتلة ومجودة لأكثر من ٦٠ قارئاً من كبار القراء مع مشغل صوتي متكامل',
              icon: Icons.record_voice_over_rounded,
              color: const Color(0xFF1E8260),
              badgeText: '٦١ قارئاً',
              onTap: () => context.push('/scholars-audio'),
            ),

            // 3. البحث في القرآن
            PortalCategoryCard(
              numberText: '٣',
              title: 'البحث في القرآن',
              subtitle: 'محرك بحث فوري متقدم يبحث في الآيات والسور والكلمات بدقة وبدون إنترنت',
              icon: Icons.search_rounded,
              color: const Color(0xFF2E7D32),
              onTap: () => context.push('/search'),
            ),

            // 4. التفاسير
            PortalCategoryCard(
              numberText: '٤',
              title: 'التفاسير',
              subtitle: 'مقارنة ٩ تفاسير معتمدة (ابن كثير، السعدي، الطبري، القرطبي، الميسر، والبغوي)',
              icon: Icons.auto_stories_rounded,
              color: const Color(0xFFB8893A),
              badgeText: '٩ تفاسير',
              onTap: () => context.push('/comparative-tafsir'),
            ),

            // 5. الإعراب
            PortalCategoryCard(
              numberText: '٥',
              title: 'الإعراب',
              subtitle: 'إعراب مفصل لكل كلمة وآية في القرآن الكريم وبيان وجوه النحو والدلالة والبلاغة',
              icon: Icons.text_format_rounded,
              color: const Color(0xFF0F5B45),
              onTap: () => context.push('/quran-irab'),
            ),

            // 6. أسباب نزول الآيات
            PortalCategoryCard(
              numberText: '٦',
              title: 'أسباب نزول الآيات',
              subtitle: 'سياق التنزيل والوقائع والأحاديث النبوية الصحيحة في أسباب النزول للواحدي والسيوطي',
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
