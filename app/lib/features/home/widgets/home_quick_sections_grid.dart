import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

/// Quick Category Model
class _QuickSectionItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String route;
  final String badgeText;

  const _QuickSectionItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.route,
    required this.badgeText,
  });
}

/// شبكة الوصول السريع لأقسام النور (HomeQuickSectionsGrid)
/// توفر وصولاً فورياً منظماً ومباشراً إلى كافة محاور وأقسام التطبيق الرئيسية
class HomeQuickSectionsGrid extends StatelessWidget {
  const HomeQuickSectionsGrid({super.key});

  static const List<_QuickSectionItem> _items = [
    _QuickSectionItem(
      title: 'المصحف الشريف',
      subtitle: 'قراءة، تلاوات، تفاسير، وقراءات',
      icon: Icons.menu_book_rounded,
      color: AppColors.primaryGreen,
      route: '/mushaf',
      badgeText: '١١٤ سورة',
    ),
    _QuickSectionItem(
      title: 'محراب الصلاة والقبلة',
      subtitle: 'المواقيت، المؤذنون الـ ٧، والمنبه',
      icon: Icons.access_time_filled_rounded,
      color: Color(0xFF25739B),
      route: '/prayer',
      badgeText: 'مواقيت دقيقة',
    ),
    _QuickSectionItem(
      title: 'الأذكار والسبحة',
      subtitle: 'حصن المسلم، الأوراد، والرقية',
      icon: Icons.volunteer_activism_rounded,
      color: Color(0xFF059669),
      route: '/adhkar-hub',
      badgeText: 'حصن المسلم',
    ),
    _QuickSectionItem(
      title: 'مكتبة كبار العلماء',
      subtitle: 'الشعراوي، كشك، ابن عثيمين، والدروس',
      icon: Icons.mic_external_on_rounded,
      color: Color(0xFF7C3AED),
      route: '/scholars-audio',
      badgeText: '٧٠٠+ محاضرة',
    ),
    _QuickSectionItem(
      title: 'المكتبة والحديث النبوي',
      subtitle: 'رياض الصالحين، القصص، والفقه',
      icon: Icons.auto_stories_rounded,
      color: Color(0xFFB45309),
      route: '/library',
      badgeText: 'موسوعة شاملة',
    ),
    _QuickSectionItem(
      title: 'دليل الشاشات الشامل',
      subtitle: 'فهرس تفصيلي لـ ٦٣ باباً وشاشة إيمانية',
      icon: Icons.grid_view_rounded,
      color: AppColors.accentGold,
      route: '/app-screen-directory',
      badgeText: '٦٣ شاشة',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: AppColors.accentGold,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'أقسام النور والوصول السريع',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Cairo',
                ),
              ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.primaryGreen),
                label: const Text(
                  'عرض الفهرس الكامل',
                  style: TextStyle(fontSize: 12, color: AppColors.primaryGreen, fontWeight: FontWeight.bold),
                ),
                onPressed: () => context.push('/app-screen-directory'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // 2-Column Responsive Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.25,
          ),
          itemBuilder: (context, index) {
            final item = _items[index];
            return _buildCard(context, item, isDark);
          },
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context, _QuickSectionItem item, bool isDark) {
    return Semantics(
      label: '${item.title} — ${item.subtitle}',
      button: true,
      child: Material(
        color: isDark ? const Color(0xFF1B2420) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (item.route == '/mushaf' || item.route == '/prayer' || item.route == '/adhkar-hub' || item.route == '/library') {
              context.go(item.route);
            } else {
              context.push(item.route);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: item.color.withValues(alpha: isDark ? 0.35 : 0.2),
                width: 1.2,
              ),
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E2823), const Color(0xFF17201C)]
                    : [Colors.white, item.color.withValues(alpha: 0.04)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Row: Icon + Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: item.color.withValues(alpha: 0.25)),
                      ),
                      child: Icon(item.icon, color: item.color, size: 20),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.badgeText,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: item.color,
                        ),
                      ),
                    ),
                  ],
                ),

                // Bottom Content: Title + Subtitle
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Cairo',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
