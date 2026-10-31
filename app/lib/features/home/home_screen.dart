import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/widgets/app_navigation_drawer.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../onboarding/onboarding_screen.dart';
import '../settings/widgets/settings_language_modal.dart';

/// شاشة التطبيق الرئيسية (HomeScreen) — مصممة لتكون هادئة ونقية وفارغة تماماً
/// حسب رغبة المستخدم، مع سهولة الوصول لكافة الأقسام عبر شريط التنقل السفلي والقائمة الجانبية
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    SettingsService.instance.init();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final uri = GoRouterState.of(context).uri;
        if (uri.queryParameters['openDrawer'] == 'true' && mounted) {
          _scaffoldKey.currentState?.openDrawer();
        }
      } catch (_) {}

      if (!SettingsService.instance.hasCompletedOnboarding &&
          SettingsService.instance.showTutorialScreens &&
          mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final s = SettingsService.instance;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Directionality(
          textDirection: s.textDirection,
          child: Scaffold(
            key: _scaffoldKey,
            drawer: const AppNavigationDrawer(),
            appBar: AppBar(
              leading: Semantics(
                label: 'open navigation menu',
                button: true,
                hint: 'افتح قائمة التنقل',
                child: IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  tooltip: 'open navigation menu',
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
              ),
              title: Text(context.tr('app_name')),
              actions: [
                IconButton(
                  icon: const Icon(Icons.language_rounded),
                  tooltip: context.tr('app_language'),
                  onPressed: () => showSettingsLanguageModal(context),
                ),
                IconButton(
                  icon: const Icon(Icons.search_rounded),
                  tooltip: context.tr('quran_search'),
                  onPressed: () => context.push('/search'),
                ),
              ],
            ),
            // شاشة التطبيق الرئيسية فاضية وهادئة تماماً
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accentGold.withOpacity(isDark ? 0.15 : 0.1),
                        border: Border.all(
                          color: AppColors.accentGold.withOpacity(0.4),
                          width: 2.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accentGold.withOpacity(isDark ? 0.2 : 0.08),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.mosque_rounded,
                        size: 48,
                        color: AppColors.accentGold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Amiri',
                        color: isDark ? AppColors.accentGold : AppColors.primaryGreen,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '«نُورُ المُؤْمِنِ»',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'اختر القسم المطلوب من شريط التنقل السفلي',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
