import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/widgets/app_navigation_drawer.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/portal_category_card.dart';
import 'shamela_library_screen.dart';

/// بوابة «المكتبة الإسلامية ورياض العلم» (IslamicLibraryScreen)
/// مقسمة إلى ٦ محاور علمية رئيسية واضحة ومستقلة:
/// 1. رياض الصالحين والحديث النبوي
/// 2. قصص الأنبياء المسموعة والمقروءة
/// 3. المتون العلمية وأحكام التجويد
/// 4. حاسبة المواريث والتركات الشرعية
/// 5. دليل الحج والعمرة التفاعلي
/// 6. إذاعة القرآن والتراث الإسلامي
class IslamicLibraryScreen extends StatelessWidget {
  final int initialTabIndex;

  const IslamicLibraryScreen({super.key, this.initialTabIndex = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        drawer: const AppNavigationDrawer(),
        appBar: AppBar(
          title: const Text('المكتبة الإسلامية ورياض العلم'),
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
              tooltip: 'البحث في المكتبة',
              onPressed: () => context.push('/library-search'),
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
                  Icon(Icons.auto_stories_rounded, color: AppColors.accentGold, size: 36),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'وَقُل رَّبِّ زِدْنِي عِلْماً',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Amiri',
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'السنة النبوية، قصص الأنبياء، المتون، والفقه',
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

            // المكتبة الشاملة الشرعية
            PortalCategoryCard(
              numberText: 'ش',
              title: 'المكتبة الشاملة الشرعية',
              subtitle: 'بحث في الأقسام الشرعية وقراءة أونلاين وحفظ الكتب داخل التطبيق للقراءة دون اتصال',
              icon: Icons.menu_book_rounded,
              color: AppColors.primaryGreen,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ShamelaLibraryScreen(),
                ),
              ),
            ),

            // 1. رياض الصالحين وصحيح الحديث
            PortalCategoryCard(
              numberText: '١',
              title: 'رياض الصالحين وصحيح الحديث',
              subtitle: 'أبواب وكتب رياض الصالحين للإمام النووي مع شروح الأحاديث والفوائد التربوية والإيمانية',
              icon: Icons.collections_bookmark_rounded,
              color: AppColors.primaryGreen,
              badgeText: 'رياض الصالحين',
              onTap: () => context.push('/riyad-alsalihin'),
            ),

            // 2. قصص الأنبياء المسموعة والمقروءة
            PortalCategoryCard(
              numberText: '٢',
              title: 'قصص الأنبياء المسموعة والمقروءة',
              subtitle: 'سلسلة قصص الأنبياء من آدم عليه السلام حتى خاتم المرسلين ﷺ بصوت نبيل العوضي وقراءة تفصيلية',
              icon: Icons.menu_book_rounded,
              color: const Color(0xFF1E8260),
              badgeText: '١٢ قصة صوتية',
              onTap: () => context.push('/stories'),
            ),

            // 3. المتون العلمية وأحكام التجويد
            PortalCategoryCard(
              numberText: '٣',
              title: 'المتون العلمية وأحكام التجويد',
              subtitle: 'تحفة الأطفال، الجزرية، القواعد الفقهية، العقيدة الطحاوية، وموسوعة أحكام التجويد',
              icon: Icons.school_rounded,
              color: const Color(0xFFB8893A),
              onTap: () => context.push('/islamic-mutoon'),
            ),

            // 4. حاسبة المواريث والتركات الشرعية
            PortalCategoryCard(
              numberText: '٤',
              title: 'حاسبة المواريث الشرعية',
              subtitle: 'حساب وقسمة الأنصبة الشرعية والتركات ومقادير الفروض والعصبات بالأدلة الفقهية',
              icon: Icons.balance_rounded,
              color: const Color(0xFF2E7D32),
              onTap: () => context.push('/mawarith-calculator'),
            ),

            // 5. دليل الحج والعمرة التفاعلي
            PortalCategoryCard(
              numberText: '٥',
              title: 'دليل الحج والعمرة التفاعلي',
              subtitle: 'مناسك الحج والعمرة خطوة بخطوة مع عداد أشواط الطواف والسعي التفاعلي والأدعية',
              icon: Icons.flight_takeoff_rounded,
              color: const Color(0xFF0F5B45),
              onTap: () => context.push('/hajj-umrah'),
            ),

            // 6. إذاعة القرآن والتراث الإسلامي
            PortalCategoryCard(
              numberText: '٦',
              title: 'إذاعة القرآن والتراث الإسلامي',
              subtitle: 'بث إذاعة القرآن الكريم من القاهرة، نوادر التلاوات، ابتهالات النقشبندي، ومجالس الشعراوي',
              icon: Icons.radio_rounded,
              color: const Color(0xFF25739B),
              badgeText: 'راديو مباشر',
              onTap: () => context.push('/egypt-heritage'),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
