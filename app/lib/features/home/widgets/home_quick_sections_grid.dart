import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

/// Quick Category Model
class _QuickSectionItem {
  final String title;
  final IconData icon;
  final Color color;
  final String route;

  const _QuickSectionItem({
    required this.title,
    required this.icon,
    required this.color,
    required this.route,
  });
}

/// شبكة الوصول السريع لأقسام التطبيق الرئيسية (HomeQuickSectionsGrid)
/// تعرض الأقسام الأساسية بعناوين مختصرة ودون تكرار دلالي أو فيضان عند التكبير 2.0x
class HomeQuickSectionsGrid extends StatelessWidget {
  const HomeQuickSectionsGrid({super.key});

  static const List<_QuickSectionItem> _items = [
    _QuickSectionItem(
      title: 'المصحف الشريف',
      icon: Icons.menu_book_rounded,
      color: AppColors.primaryGreen,
      route: '/mushaf',
    ),
    _QuickSectionItem(
      title: 'الصلاة والقبلة',
      icon: Icons.access_time_filled_rounded,
      color: Color(0xFF25739B),
      route: '/prayer',
    ),
    _QuickSectionItem(
      title: 'الأذكار والسبحة',
      icon: Icons.volunteer_activism_rounded,
      color: Color(0xFF059669),
      route: '/adhkar-hub',
    ),
    _QuickSectionItem(
      title: 'المكتبة والحديث',
      icon: Icons.auto_stories_rounded,
      color: Color(0xFFB45309),
      route: '/library',
    ),
    _QuickSectionItem(
      title: 'ختمة القرآن',
      icon: Icons.bookmark_added_rounded,
      color: Color(0xFF0F766E),
      route: '/khatma',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              const Expanded(
                child: Text(
                  'الأقسام الرئيسية',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14.0;
            final singleColumn = constraints.maxWidth < 420 && textScale >= 1.5;

            if (singleColumn) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < _items.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _buildCard(context, _items[i], isDark),
                  ],
                ],
              );
            }

            final rows = <Widget>[];
            for (int i = 0; i < _items.length; i += 2) {
              final first = _items[i];
              final second = (i + 1 < _items.length) ? _items[i + 1] : null;
              if (rows.isNotEmpty) {
                rows.add(const SizedBox(height: 10));
              }
              rows.add(
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildCard(context, first, isDark)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: second != null
                            ? _buildCard(context, second, isDark)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              );
            }
            return Column(children: rows);
          },
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context, _QuickSectionItem item, bool isDark) {
    void handleTap() {
      final router = GoRouter.maybeOf(context);
      if (router == null) return;
      if (item.route == '/mushaf' ||
          item.route == '/prayer' ||
          item.route == '/adhkar-hub' ||
          item.route == '/library') {
        router.go(item.route);
      } else {
        router.push(item.route);
      }
    }

    return Semantics(
      label: item.title,
      button: true,
      excludeSemantics: true,
      onTap: handleTap,
      child: Material(
        color: isDark ? const Color(0xFF1B2420) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: handleTap,
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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: item.color.withValues(alpha: 0.25)),
                  ),
                  child: Icon(item.icon, color: item.color, size: 20),
                ),
                const SizedBox(height: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Cairo',
                      ),
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
