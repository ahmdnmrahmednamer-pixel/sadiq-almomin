import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/widgets/app_navigation_drawer.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/prayer_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../onboarding/onboarding_screen.dart';
import '../settings/widgets/settings_language_modal.dart';
import '../search/widgets/quran_voice_search_sheet.dart';
import '../search/quran_search_screen.dart';
import 'widgets/home_date_header_card.dart';
import 'widgets/home_next_prayer_card.dart';
import 'widgets/home_quran_continue_card.dart';
import 'widgets/home_adhkar_tasbih_row.dart';
import 'widgets/home_quick_sections_grid.dart';

/// شاشة التطبيق الرئيسية (HomeScreen)
/// مصممة بهدوء وسكينة إيمانية، وتتيح الوصول لكافة الأقسام والشيوخ والمؤذنين عبر القائمة الجانبية (Navigation Menu)
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
    PrayerService.instance.init();

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
      animation: Listenable.merge([SettingsService.instance, PrayerService.instance]),
      builder: (context, _) {
        final s = SettingsService.instance;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final prayerData = PrayerService.instance.currentData;
        final dayName = HijriDateHelper.getDayOfWeek();
        final hijriStr = HijriDateHelper.getHijriDateString();
        final gregStr = HijriDateHelper.getGregorianDateString();

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
                  icon: const Icon(Icons.mic_rounded),
                  tooltip: 'البحث الصوتي عن الآيات',
                  onPressed: () async {
                    final query = await QuranVoiceSearchSheet.show(context);
                    if (query != null && query.trim().isNotEmpty && mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => QuranSearchScreen(initialQuery: query.trim()),
                        ),
                      );
                    }
                  },
                ),
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
            body: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // 1. Header Date Card (Hijri & Gregorian)
                HomeDateHeaderCard(
                  dayName: dayName,
                  hijriStr: hijriStr,
                  gregStr: gregStr,
                ),
                const SizedBox(height: 12),

                // 2. Next Prayer & Location Card (الوقت المتبقي على الصلاة القادمة وموقعك الحالي الفعلي)
                HomeNextPrayerCard(prayerData: prayerData),
                const SizedBox(height: 12),

                // 3. Open Navigation Menu Interactive Banner
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [AppColors.night900, AppColors.emerald900.withOpacity(0.4)]
                            : [AppColors.mint100.withOpacity(0.5), AppColors.paper50],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primaryGreen.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGreen.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.menu_open_rounded, color: AppColors.primaryGreen, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'القائمة الإيمانية الشاملة ☰',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'الإعدادات، عن التطبيق، المطور، والتواصل في القائمة الجانبية',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDark ? Colors.white70 : AppColors.mutedText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                          child: const Text('فتح القائمة', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 4. Continue Quran Card
                const HomeQuranContinueCard(),
                const SizedBox(height: 12),

                // 5. Adhkar & Tasbih Row
                const HomeAdhkarTasbihRow(),
                const SizedBox(height: 14),

                // 6. Quick Access Sections Grid
                const HomeQuickSectionsGrid(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
