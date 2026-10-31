import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';

/// القائمة الجانبية (Navigation Drawer) — مصممة وفق أحدث معايير النفاذية وسهولة الاستخدام
/// تحتوي حصرياً على الأقسام الـ 3 المحددة:
/// 1. عن المطور (ورابط المشروع على GitHub)
/// 2. تواصل مع المطور
/// 3. الإعدادات وعن التطبيق
class AppNavigationDrawer extends StatelessWidget {
  const AppNavigationDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final s = SettingsService.instance;

        return Semantics(
          label: 'open navigation menu',
          container: true,
          child: Drawer(
            child: Directionality(
              textDirection: s.textDirection,
              child: Material(
                color: isDark ? const Color(0xFF0F1A15) : Colors.white,
                child: SafeArea(
                  bottom: true,
                  top: false,
                  child: Column(
                    children: [
                      // 1. Serene Header
                      Semantics(
                        label: 'open navigation menu header',
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isDark
                                  ? [
                                      const Color(0xFF0B2B20),
                                      const Color(0xFF071C15),
                                    ]
                                  : [
                                      const Color(0xFF0F5B45),
                                      const Color(0xFF093E2F),
                                    ],
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.accentGold.withOpacity(0.18),
                                  border: Border.all(
                                      color: AppColors.accentGold, width: 2),
                                ),
                                child: const Icon(
                                  Icons.mosque_rounded,
                                  color: AppColors.accentGold,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.tr('app_name'),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        fontFamily: 'Amiri',
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      context.tr('app_subtitle'),
                                      style: const TextStyle(
                                        color: AppColors.softGold,
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
                      ),

                      const SizedBox(height: 12),

                      // 2. The 3 Navigation Items
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(
                              vertical: 6, horizontal: 10),
                          children: [
                            // ================= 1. عن المطور ورابط المشروع على GitHub =================
                            _buildDrawerTile(
                              context: context,
                              icon: Icons.code_rounded,
                              title: 'عن المطور',
                              subtitle: 'ورابط المشروع على GitHub',
                              semanticLabel: 'عن المطور ورابط المشروع على الجيتهاب',
                              color: AppColors.primaryGreen,
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/about-developer');
                              },
                            ),

                            const Divider(height: 16),

                            // ================= 2. تواصل مع المطور =================
                            _buildDrawerTile(
                              context: context,
                              icon: Icons.mail_outline_rounded,
                              title: 'تواصل مع المطور',
                              subtitle: 'إرسال اقتراح، ملاحظة، أو رسالة مباشرة',
                              semanticLabel: 'تواصل مع المطور',
                              color: const Color(0xFF25739B),
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/support');
                              },
                            ),

                            const Divider(height: 16),

                            // ================= 3. الإعدادات وعن التطبيق =================
                            _buildDrawerTile(
                              context: context,
                              icon: Icons.settings_outlined,
                              title: 'الإعدادات وعن التطبيق',
                              subtitle: 'تخصيص الخيارات، المظهر، ومعلومات التطبيق',
                              semanticLabel: 'الإعدادات وعن التطبيق',
                              color: const Color(0xFFB8893A),
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/settings');
                              },
                            ),
                          ],
                        ),
                      ),

                      // 3. Clean Footer
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: isDark
                                  ? const Color(0xFF1A2A22)
                                  : const Color(0xFFE5EDE8),
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'إصدار رسمي v1.0.0',
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 11.5),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.favorite,
                                    color: AppColors.accentGold, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  'لوجه الله تعالى',
                                  style: TextStyle(
                                    color: isDark
                                        ? AppColors.accentGold
                                        : AppColors.primaryGreen,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDrawerTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String semanticLabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF15221B)
              : const Color(0xFFF7FBF8),
          border: Border.all(
            color: color.withOpacity(0.2),
            width: 1.2,
          ),
        ),
        child: ListTile(
          dense: false,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.35)),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          trailing: const Icon(Icons.arrow_forward_ios_rounded,
              size: 16, color: Colors.grey),
          onTap: onTap,
        ),
      ),
    );
  }
}
