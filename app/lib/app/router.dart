import '../features/library/screens/riyad_alsalihin_screen.dart';
import '../features/prayer/sunan_rawatib_screen.dart';
import '../features/radio/islamic_radio_screen.dart';
import '../features/library/screens/islamic_mutoon_screen.dart';
import '../features/zakat/mawarith_calculator_screen.dart';
import '../features/mushaf/tadabbur_journal_screen.dart';
import '../features/mushaf/comparative_tafsir_screen.dart';
import '../features/mushaf/surah_reader_screen.dart';
import '../features/stories/story_detail_screen.dart';
import '../features/tajweed/rule_detail_screen.dart';
import '../features/home/screens/app_screen_directory_screen.dart';
import '../features/audio/scholars_audio_library_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/localization/app_localizations.dart';
import '../core/models/quran_topic.dart';
import '../core/models/surah.dart';
import '../core/models/prophet_story.dart';
import '../core/models/tajweed_rule.dart';
import '../core/services/settings_service.dart';
import '../core/services/stories_service.dart';
import '../core/services/tajweed_service.dart';
import '../core/services/quran_repository.dart';
import '../core/theme/app_theme.dart';
import '../features/adhkar/adhkar_hub_screen.dart';
import '../features/adhkar/adhkar_screen.dart';
import '../features/adhkar/spiritual_mood_remedy_screen.dart';
import '../features/adhkar/tasbih_screen.dart';
import '../features/audio/audio_screen.dart';
import '../features/audio/downloads_manager_screen.dart';
import '../features/audio/widgets/global_mini_player_bar.dart';
import '../features/mushaf/screens/quran_asbab_nuzul_screen.dart';
import '../features/mushaf/screens/quran_irab_screen.dart';
import '../features/mushaf/screens/audio_tafsir_screen.dart';
import '../features/mushaf/screens/qiraat_mushaf_screen.dart';
import '../features/library/screens/approved_sources_screen.dart';
import '../features/prayer/prayer_times_detail_screen.dart';
import '../features/backup/backup_restore_screen.dart';
import '../features/egypt/egyptian_heritage_screen.dart';
import '../features/hadith/hadith_detail_screen.dart';
import '../features/hadith/hadith_library_screen.dart';
import '../features/home/home_screen.dart';
import '../features/home/momen_duaa_screen.dart';
import '../features/khatma/khatma_screen.dart';
import '../features/library/islamic_library_screen.dart';
import '../features/library/screens/asma_allah_shamail_screen.dart';
import '../features/library/screens/fiqh_library_screen.dart';
import '../features/library/screens/hajj_umrah_companion_screen.dart';
import '../features/library/screens/islamic_history_screen.dart';
import '../features/library/screens/quran_sciences_screen.dart';
import '../features/library/screens/unified_library_search_screen.dart';
import '../features/mushaf/gharib_quran_screen.dart';
import '../features/mushaf/memorization_screen.dart';
import '../features/mushaf/mushaf_screen.dart';
import '../features/mushaf/page_mode_mushaf_screen.dart';
import '../features/mushaf/quran_hub_screen.dart';
import '../features/mushaf/quran_notes_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/prayer/adhan_control_screen.dart';
import '../features/prayer/battery_reliability_screen.dart';
import '../features/prayer/fajr_qiyam_alarm_screen.dart';
import '../features/prayer/hijri_calendar_screen.dart';
import '../features/prayer/prayer_screen.dart';
import '../features/prayer/prayer_tracker_screen.dart';
import '../features/prayer/qibla_compass_screen.dart';
import '../features/prayer/voluntary_fasting_screen.dart';
import '../features/ramadan/ramadan_screen.dart';
import '../features/search/quran_search_screen.dart';
import '../features/settings/about_developer_screen.dart';
import '../features/settings/contact_support_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/stories/stories_screen.dart';
import '../features/studio/daawah_card_studio_screen.dart';
import '../features/tajweed/tajweed_screen.dart';
import '../features/topics/quran_topics_screen.dart';
import '../features/topics/topic_detail_screen.dart';
import '../features/wird/daily_wird_screen.dart';
import '../features/zakat/kaffarah_fidyah_screen.dart';
import '../features/zakat/zakat_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _rootNavigatorKey = rootNavigatorKey;

/// Top-level hub routes (and hub alias) hosted inside [ShellRoute] / [MainScaffold].
const Set<String> kHubShellRoutePaths = {
  '/home',
  '/mushaf',
  '/quran-hub',
  '/prayer',
  '/adhkar-hub',
  '/library',
};

/// Reusable AppBar leading back button for isolated full-page feature screens.
/// Pops the current route when possible, or falls back to `/home` on direct deep links.
class IsolatedBackButton extends StatelessWidget {
  const IsolatedBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final isArabic = SettingsService.instance.isArabic;
    return IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      tooltip: isArabic ? 'رجوع' : 'Back',
      onPressed: () {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          GoRouter.maybeOf(context)?.go('/home');
        }
      },
    );
  }
}

/// Hosts an isolated full-page feature/detail route on [rootNavigatorKey]
/// without [MainScaffold]'s persistent bottom navigation bar, while preserving
/// [GlobalMiniPlayerBar] playback/stop controls and reachable back/home actions on deep links.
class IsolatedFeatureRouteHost extends StatelessWidget {
  final Widget child;
  final bool includeMiniPlayer;
  final bool hasOwnDirectBackAction;

  const IsolatedFeatureRouteHost({
    super.key,
    required this.child,
    this.includeMiniPlayer = true,
    this.hasOwnDirectBackAction = false,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final showDirectBackBar = !canPop && !hasOwnDirectBackAction;
    final isArabic = SettingsService.instance.isArabic;
    final theme = Theme.of(context);

    final content = Column(
      children: [
        if (showDirectBackBar)
          Directionality(
            textDirection: SettingsService.instance.textDirection,
            child: Material(
              color: theme.colorScheme.surface,
              child: SafeArea(
                bottom: false,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                  ),
                  alignment: AlignmentDirectional.centerStart,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: TextButton.icon(
                    key: const ValueKey('isolated_direct_back_home_button'),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: Text(isArabic ? 'رجوع للرئيسية' : 'Back to Home'),
                    onPressed: () => GoRouter.maybeOf(context)?.go('/home'),
                  ),
                ),
              ),
            ),
          ),
        Expanded(child: child),
        if (includeMiniPlayer) const GlobalMiniPlayerBar(),
      ],
    );

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !canPop) {
          GoRouter.maybeOf(context)?.go('/home');
        }
      },
      child: content,
    );
  }
}

GoRoute _isolatedFeatureRoute({
  required String path,
  required GoRouterWidgetBuilder builder,
  bool includeMiniPlayer = true,
  bool hasOwnDirectBackAction = false,
}) {
  return GoRoute(
    path: path,
    parentNavigatorKey: _rootNavigatorKey,
    builder: (context, state) => IsolatedFeatureRouteHost(
      includeMiniPlayer: includeMiniPlayer,
      hasOwnDirectBackAction: hasOwnDirectBackAction,
      child: builder(context, state),
    ),
  );
}

class MainScaffold extends StatefulWidget {
  final Widget child;
  const MainScaffold({super.key, required this.child});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  String _safeLocation(BuildContext context) {
    try {
      return GoRouterState.of(context).uri.path;
    } catch (_) {
      return '/home';
    }
  }

  int _calculateSelectedIndex(BuildContext context) {
    final String location = _safeLocation(context);
    if (location.startsWith('/mushaf') || location.startsWith('/quran-hub')) {
      return 1;
    }
    if (location.startsWith('/prayer')) {
      return 2;
    }
    if (location.startsWith('/adhkar-hub')) {
      return 3;
    }
    if (location.startsWith('/library')) {
      return 4;
    }
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/mushaf');
        break;
      case 2:
        context.go('/prayer');
        break;
      case 3:
        context.go('/adhkar-hub');
        break;
      case 4:
        context.go('/library');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = _safeLocation(context);
    final isHubRoute = kHubShellRoutePaths.contains(location);
    final selectedIndex = _calculateSelectedIndex(context).clamp(0, 4);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        return Scaffold(
          body: widget.child,
          bottomNavigationBar: !isHubRoute
              ? const GlobalMiniPlayerBar()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const GlobalMiniPlayerBar(),
                    Directionality(
                      textDirection: SettingsService.instance.textDirection,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          border: Border(
                            top: BorderSide(
                              color: theme.colorScheme.outlineVariant,
                              width: 1,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: NavigationBar(
                          selectedIndex: selectedIndex,
                          onDestinationSelected: (index) =>
                              _onItemTapped(index, context),
                          height: 70,
                          elevation: 0,
                          backgroundColor: Colors.transparent,
                          indicatorColor: AppColors.primaryGreen
                              .withValues(alpha: isDark ? 0.28 : 0.15),
                          labelBehavior:
                              NavigationDestinationLabelBehavior.alwaysShow,
                          destinations: [
                            NavigationDestination(
                              icon: const Icon(Icons.home_outlined),
                              selectedIcon: const Icon(Icons.home_rounded,
                                  color: AppColors.primaryGreen),
                              label: context.tr('nav_home'),
                              tooltip: context.tr('tooltip_home'),
                            ),
                            NavigationDestination(
                              icon: const Icon(Icons.menu_book_outlined),
                              selectedIcon: const Icon(Icons.menu_book_rounded,
                                  color: AppColors.primaryGreen),
                              label: context.tr('nav_quran'),
                              tooltip: context.tr('tooltip_quran'),
                            ),
                            NavigationDestination(
                              icon: const Icon(Icons.access_time_outlined),
                              selectedIcon: const Icon(
                                  Icons.access_time_filled_rounded,
                                  color: AppColors.primaryGreen),
                              label: context.tr('nav_prayer'),
                              tooltip: context.tr('tooltip_prayer'),
                            ),
                            NavigationDestination(
                              icon: const Icon(Icons.fingerprint_outlined),
                              selectedIcon: const Icon(
                                  Icons.fingerprint_rounded,
                                  color: AppColors.primaryGreen),
                              label: context.tr('nav_adhkar'),
                              tooltip: context.tr('tooltip_adhkar'),
                            ),
                            NavigationDestination(
                              icon: const Icon(Icons.auto_stories_outlined),
                              selectedIcon: const Icon(
                                  Icons.auto_stories_rounded,
                                  color: AppColors.primaryGreen),
                              label: context.tr('nav_library'),
                              tooltip: context.tr('tooltip_library'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/momen-duaa',
  routes: [
    GoRoute(
      path: '/momen-duaa',
      builder: (context, state) => const MomenDuaaScreen(),
    ),
    GoRoute(
      path: '/duaa',
      builder: (context, state) => const MomenDuaaScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/adhan-control',
      builder: (context, state) {
        final prayer = state.uri.queryParameters['prayer'] ?? 'الظهر';
        final isIqamah = state.uri.queryParameters['isIqamah'] == 'true';
        final autoPlay = state.uri.queryParameters['autoPlay'] != 'false';
        return AdhanControlScreen(
          prayerName: prayer,
          isIqamah: isIqamah,
          autoPlay: autoPlay,
        );
      },
    ),

    // Five top-level hubs (+ /quran-hub alias) hosted inside MainScaffold
    ShellRoute(
      builder: (context, state, child) => MainScaffold(child: child),
      routes: [
        GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
        GoRoute(path: '/mushaf', builder: (context, state) => const QuranHubScreen()),
        GoRoute(path: '/quran-hub', builder: (context, state) => const QuranHubScreen()),
        GoRoute(path: '/prayer', builder: (context, state) => const PrayerScreen()),
        GoRoute(path: '/adhkar-hub', builder: (context, state) => const AdhkarHubScreen()),
        GoRoute(path: '/library', builder: (context, state) => const IslamicLibraryScreen()),
      ],
    ),

    // Root-isolated full-page feature & detail routes (outside MainScaffold / bottom nav)
    _isolatedFeatureRoute(path: '/mushaf-reader', builder: (context, state) => const MushafScreen()),
    _isolatedFeatureRoute(path: '/audio', builder: (context, state) => const AudioScreen()),
    _isolatedFeatureRoute(
      path: '/scholars-audio',
      includeMiniPlayer: false,
      builder: (context, state) => const ScholarsAudioLibraryScreen(),
    ),
    _isolatedFeatureRoute(path: '/egypt-heritage', builder: (context, state) => const EgyptianHeritageScreen()),
    _isolatedFeatureRoute(path: '/islamic-radio', builder: (context, state) => const IslamicRadioScreen()),
    _isolatedFeatureRoute(path: '/fiqh-library', builder: (context, state) => const FiqhLibraryScreen()),
    _isolatedFeatureRoute(path: '/quran-sciences', builder: (context, state) => const QuranSciencesScreen()),
    _isolatedFeatureRoute(path: '/asma-shamail', builder: (context, state) => const AsmaAllahShamailScreen()),
    _isolatedFeatureRoute(path: '/islamic-history', builder: (context, state) => const IslamicHistoryScreen()),
    _isolatedFeatureRoute(
      path: '/library-search',
      includeMiniPlayer: false,
      builder: (context, state) => const UnifiedLibrarySearchScreen(),
    ),
    _isolatedFeatureRoute(path: '/daily-wird', builder: (context, state) => const DailyWirdScreen()),
    _isolatedFeatureRoute(path: '/daawah-studio', builder: (context, state) => const DaawahCardStudioScreen()),
    _isolatedFeatureRoute(
      path: '/settings',
      hasOwnDirectBackAction: true,
      builder: (context, state) => const SettingsScreen(),
    ),
    _isolatedFeatureRoute(path: '/ramadan', builder: (context, state) => const RamadanScreen()),
    _isolatedFeatureRoute(path: '/stories', builder: (context, state) => const StoriesScreen()),
    _isolatedFeatureRoute(path: '/tajweed', builder: (context, state) => const TajweedScreen()),
    _isolatedFeatureRoute(path: '/hajj-umrah', builder: (context, state) => const HajjUmrahCompanionScreen()),
    _isolatedFeatureRoute(path: '/voluntary-fasting', builder: (context, state) => const VoluntaryFastingScreen()),
    _isolatedFeatureRoute(path: '/spiritual-mood', builder: (context, state) => const SpiritualMoodRemedyScreen()),
    _isolatedFeatureRoute(path: '/gharib-quran', builder: (context, state) => const GharibQuranScreen()),
    _isolatedFeatureRoute(path: '/kaffarah-fidyah', builder: (context, state) => const KaffarahFidyahScreen()),
    _isolatedFeatureRoute(
      path: '/adhkar',
      builder: (context, state) {
        final indexParam = state.uri.queryParameters['index'];
        if (indexParam != null) {
          final categoryIndex = int.tryParse(indexParam) ?? 0;
          return AdhkarScreen(initialCategoryIndex: categoryIndex);
        }
        return const AdhkarHubScreen();
      },
    ),
    _isolatedFeatureRoute(path: '/tasbih', builder: (context, state) => const TasbihScreen()),
    _isolatedFeatureRoute(path: '/qibla', builder: (context, state) => const QiblaCompassScreen()),
    _isolatedFeatureRoute(path: '/calendar', builder: (context, state) => const HijriCalendarScreen()),
    _isolatedFeatureRoute(path: '/khatma', builder: (context, state) => const KhatmaScreen()),
    _isolatedFeatureRoute(path: '/battery-guide', builder: (context, state) => const BatteryReliabilityScreen()),
    _isolatedFeatureRoute(path: '/backup', builder: (context, state) => const BackupRestoreScreen()),
    _isolatedFeatureRoute(path: '/prayer-tracker', builder: (context, state) => const PrayerTrackerScreen()),
    _isolatedFeatureRoute(path: '/fajr-qiyam-alarm', builder: (context, state) => const FajrQiyamAlarmScreen()),
    _isolatedFeatureRoute(path: '/downloads', builder: (context, state) => const DownloadsManagerScreen()),
    _isolatedFeatureRoute(path: '/notes', builder: (context, state) => const QuranNotesScreen()),
    _isolatedFeatureRoute(
      path: '/memorization',
      builder: (context, state) {
        final surahId = int.tryParse(state.uri.queryParameters['surahId'] ?? '1') ?? 1;
        final fromAyah = int.tryParse(state.uri.queryParameters['fromAyah'] ?? '1') ?? 1;
        final toAyah = int.tryParse(state.uri.queryParameters['toAyah'] ?? '7') ?? 7;
        return MemorizationScreen(
          initialSurahId: surahId,
          initialFromAyah: fromAyah,
          initialToAyah: toAyah,
        );
      },
    ),
    _isolatedFeatureRoute(path: '/zakat', builder: (context, state) => const ZakatScreen()),
    _isolatedFeatureRoute(
      path: '/hadith',
      builder: (context, state) {
        final bookId = state.uri.queryParameters['bookId'];
        return HadithLibraryScreen(initialBookId: bookId);
      },
    ),
    _isolatedFeatureRoute(
      path: '/hadith-detail',
      builder: (context, state) {
        final id = int.tryParse(state.uri.queryParameters['id'] ?? '1') ?? 1;
        return HadithDetailScreen(hadithId: id);
      },
    ),
    _isolatedFeatureRoute(
      path: '/topics',
      builder: (context, state) {
        final catStr = state.uri.queryParameters['category'];
        TopicCategory? cat;
        if (catStr != null) {
          try {
            cat = TopicCategory.values.firstWhere((c) => c.name == catStr, orElse: () => TopicCategory.values.first);
          } catch (_) {}
        }
        return QuranTopicsScreen(initialCategory: cat);
      },
    ),
    _isolatedFeatureRoute(
      path: '/topic-detail',
      builder: (context, state) {
        final id = state.uri.queryParameters['id'] ?? 'patience';
        return TopicDetailScreen(topicId: id);
      },
    ),
    _isolatedFeatureRoute(
      path: '/search',
      builder: (context, state) {
        final q = state.uri.queryParameters['q'];
        return QuranSearchScreen(initialQuery: q);
      },
    ),
    _isolatedFeatureRoute(
      path: '/mushaf-pages',
      builder: (context, state) {
        final page = int.tryParse(state.uri.queryParameters['page'] ?? '1') ?? 1;
        return PageModeMushafScreen(initialPage: page);
      },
    ),
    _isolatedFeatureRoute(
      path: '/quran-irab',
      builder: (context, state) => const QuranIrabScreen(),
    ),
    _isolatedFeatureRoute(
      path: '/qiraat',
      hasOwnDirectBackAction: true,
      builder: (context, state) => const QiraatMushafScreen(),
    ),
    _isolatedFeatureRoute(
      path: '/audio-tafsir',
      hasOwnDirectBackAction: true,
      builder: (context, state) => const AudioTafsirScreen(),
    ),
    _isolatedFeatureRoute(
      path: '/approved-sources',
      hasOwnDirectBackAction: true,
      builder: (context, state) => const ApprovedSourcesScreen(),
    ),
    _isolatedFeatureRoute(
      path: '/quran-asbab-nuzul',
      builder: (context, state) => const QuranAsbabNuzulScreen(),
    ),
    _isolatedFeatureRoute(
      path: '/prayer-times-detail',
      builder: (context, state) => const PrayerTimesDetailScreen(),
    ),
    _isolatedFeatureRoute(
      path: '/about-developer',
      builder: (context, state) => const AboutDeveloperScreen(),
    ),
    _isolatedFeatureRoute(
      path: '/support',
      builder: (context, state) => const ContactSupportScreen(),
    ),
    _isolatedFeatureRoute(
      path: '/sunan-rawatib',
      builder: (context, state) => const SunanRawatibScreen(),
    ),
    _isolatedFeatureRoute(
      path: '/riyad-alsalihin',
      builder: (context, state) => const RiyadAlSalihinScreen(),
    ),
    _isolatedFeatureRoute(
      path: '/islamic-mutoon',
      builder: (context, state) => const IslamicMutoonScreen(),
    ),
    _isolatedFeatureRoute(
      path: '/mawarith-calculator',
      builder: (context, state) => const MawarithCalculatorScreen(),
    ),
    _isolatedFeatureRoute(
      path: '/tadabbur-journal',
      builder: (context, state) => const TadabburJournalScreen(),
    ),
    _isolatedFeatureRoute(
      path: '/comparative-tafsir',
      builder: (context, state) => const ComparativeTafsirScreen(),
    ),
    _isolatedFeatureRoute(
      path: '/app-directory',
      builder: (context, state) => const AppScreenDirectoryScreen(),
    ),
    _isolatedFeatureRoute(
      path: '/app-screen-directory',
      builder: (context, state) => const AppScreenDirectoryScreen(),
    ),
    _isolatedFeatureRoute(
      path: '/surah-reader',
      builder: (context, state) {
        if (state.extra is Surah) {
          final initialAyah = int.tryParse(state.uri.queryParameters['ayah'] ?? '1') ?? 1;
          return SurahReaderScreen(surah: state.extra as Surah, initialAyah: initialAyah);
        }
        final surahId = int.tryParse(state.uri.queryParameters['surahId'] ?? '1') ?? 1;
        final initialAyah = int.tryParse(state.uri.queryParameters['ayah'] ?? '1') ?? 1;
        return FutureBuilder<Surah?>(
          future: QuranRepository.getSurahById(surahId),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              return SurahReaderScreen(surah: snapshot.data!, initialAyah: initialAyah);
            }
            final defaultSurah = Surah(
              id: surahId,
              nameAr: 'الفاتحة',
              nameSimple: 'Al-Fatihah',
              revelationPlace: 'makkah',
              revelationOrder: 5,
              ayahCount: 7,
              hasBasmala: false,
              pageStart: 1,
              pageEnd: 1,
            );
            return SurahReaderScreen(surah: defaultSurah, initialAyah: initialAyah);
          },
        );
      },
    ),
    _isolatedFeatureRoute(
      path: '/story-detail',
      builder: (context, state) {
        if (state.extra is ProphetAudioStory) {
          return StoryDetailScreen(story: state.extra as ProphetAudioStory);
        }
        final id = state.uri.queryParameters['id'] ?? 'adam';
        final stories = StoriesService.instance.getAllStories();
        final story = stories.firstWhere(
          (s) => s.id == id,
          orElse: () => stories.first,
        );
        return StoryDetailScreen(story: story);
      },
    ),
    _isolatedFeatureRoute(
      path: '/tajweed-rule',
      builder: (context, state) {
        if (state.extra is TajweedRule) {
          return RuleDetailScreen(rule: state.extra as TajweedRule);
        }
        final id = state.uri.queryParameters['id'] ?? 'noon_sakina_ithhar';
        final rule = TajweedService.instance.getRuleById(id) ??
            TajweedService.instance.getRulesByCategory(TajweedCategory.nunTanween).first;
        return RuleDetailScreen(rule: rule);
      },
    ),
  ],
);
