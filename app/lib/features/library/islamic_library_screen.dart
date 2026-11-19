import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/widgets/app_navigation_drawer.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/portal_category_card.dart';
import 'shamela_library_screen.dart';

/// بوابة «المكتبة الإسلامية ورياض العلم» (IslamicLibraryScreen)
/// المكتبة الشاملة وأدوات مستقلة: القصص والمواريث والحج والإذاعة.
/// - المكتبة الشاملة (مستقلة)
/// 1. قصص الأنبياء
/// 2. حاسبة المواريث والتركات الشرعية
/// 3. الحج والعمرة
/// 4. الإذاعة والتراث
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
          title: const Text('رياض العلم'),
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
                          'كتب شرعية وأدوات عملية',
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

            const SizedBox(height: 14),

            // المكتبة الشاملة
            PortalCategoryCard(
              numberText: 'ش',
              title: 'المكتبة الشاملة',
              subtitle: '',
              icon: Icons.menu_book_rounded,
              color: AppColors.primaryGreen,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ShamelaLibraryScreen(),
                ),
              ),
            ),

            PortalCategoryCard(
              numberText: 'ق',
              title: 'قارئ الكتب',
              subtitle: 'الكتب المحمّلة',
              icon: Icons.offline_pin_outlined,
              color: AppColors.primaryGreen,
              onTap: () => context.push('/downloaded-books'),
            ),

            // 1. قصص الأنبياء
            PortalCategoryCard(
              numberText: '١',
              title: 'قصص الأنبياء',
              subtitle: '',
              icon: Icons.menu_book_rounded,
              color: const Color(0xFF1E8260),
              onTap: () => context.push('/stories'),
            ),

            // 2. حاسبة المواريث والتركات الشرعية
            PortalCategoryCard(
              numberText: '٢',
              title: 'المواريث',
              subtitle: '',
              icon: Icons.balance_rounded,
              color: const Color(0xFF2E7D32),
              onTap: () => context.push('/mawarith-calculator'),
            ),

            // 3. الحج والعمرة
            PortalCategoryCard(
              numberText: '٣',
              title: 'الحج والعمرة',
              subtitle: '',
              icon: Icons.flight_takeoff_rounded,
              color: const Color(0xFF0F5B45),
              onTap: () => context.push('/hajj-umrah'),
            ),

            // 4. الإذاعة والتراث
            PortalCategoryCard(
              numberText: '٤',
              title: 'الإذاعة والتراث',
              subtitle: '',
              icon: Icons.radio_rounded,
              color: const Color(0xFF25739B),
              onTap: () => context.push('/egypt-heritage'),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
