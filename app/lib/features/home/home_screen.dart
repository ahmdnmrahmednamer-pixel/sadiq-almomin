import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/router.dart';
import '../../app/widgets/app_navigation_drawer.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/daily_wird_service.dart';
import '../../core/services/prayer_service.dart';
import '../../core/services/prayer_tracker_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/sunan_rawatib_service.dart';
import '../onboarding/onboarding_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/widgets/settings_about_modal.dart';
import 'widgets/home_adhkar_tasbih_row.dart';
import 'widgets/home_daily_progress_card.dart';
import 'widgets/home_date_header_card.dart';
import 'widgets/home_next_prayer_card.dart';
import 'widgets/home_quick_sections_grid.dart';
import 'widgets/home_quran_continue_card.dart';

/// شاشة التطبيق الرئيسية (HomeScreen)
/// لوحة يومية مبسطة تعرض التاريخ، الصلاة القادمة، إنجاز اليوم الفعلي، والوصول السريع للأقسام
class HomeScreen extends StatefulWidget {
  final DateTime Function()? clock;

  const HomeScreen({
    super.key,
    this.clock,
  });

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
    PrayerTrackerService.instance.init();
    SunanRawatibService.instance.init();
    DailyWirdService.instance.init();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!SettingsService.instance.hasCompletedOnboarding &&
          SettingsService.instance.showTutorialScreens &&
          mounted) {
        final router = GoRouter.maybeOf(context);
        if (router != null) {
          router.push('/onboarding');
        } else {
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(builder: (_) => const OnboardingScreen()),
          );
        }
      }
    });
  }

  void _openSettings(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.push('/settings');
    } else {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => const IsolatedFeatureRouteHost(
            hasOwnDirectBackAction: true,
            child: SettingsScreen(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([SettingsService.instance, PrayerService.instance]),
      builder: (context, _) {
        final s = SettingsService.instance;
        final prayerData = PrayerService.instance.currentData;
        final now = (widget.clock ?? DateTime.now)();
        final dayName = HijriDateHelper.getDayOfWeek(now);
        final hijriStr = HijriDateHelper.getHijriDateString(now);
        final gregStr = HijriDateHelper.getGregorianDateString(now);

        return Directionality(
          textDirection: s.textDirection,
          child: Scaffold(
            key: _scaffoldKey,
            drawer: const AppNavigationDrawer(),
            appBar: AppBar(
              leading: IconButton(
                key: const ValueKey('home_menu_button'),
                icon: const Icon(Icons.menu_rounded),
                tooltip: 'القائمة',
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              title: Text(context.tr('app_name')),
              actions: [
                IconButton(
                  key: const ValueKey('home_settings_button'),
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'الإعدادات',
                  onPressed: () => _openSettings(context),
                ),
                IconButton(
                  key: const ValueKey('home_info_button'),
                  icon: const Icon(Icons.info_outline_rounded),
                  tooltip: 'عن التطبيق',
                  onPressed: () => showSettingsAboutModal(context),
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

                // 2. Next Prayer & Location Card
                HomeNextPrayerCard(prayerData: prayerData),
                const SizedBox(height: 12),

                // 3. Truthful Daily Progress Dashboard (Obligatory / Sunan / Daily Wird)
                HomeDailyProgressCard(clock: widget.clock),
                const SizedBox(height: 12),

                // 4. Continue Quran Card
                const HomeQuranContinueCard(),
                const SizedBox(height: 12),

                // 5. Adhkar & Tasbih Row
                const HomeAdhkarTasbihRow(),
                const SizedBox(height: 14),

                // 6. Core Feature Quick Access Grid
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
