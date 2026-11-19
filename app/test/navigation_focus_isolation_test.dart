import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/router.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/app/widgets/app_navigation_drawer.dart';
import 'package:almomin/core/services/daily_wird_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/prayer_tracker_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';
import 'package:almomin/features/adhkar/tasbih_screen.dart';
import 'package:almomin/features/audio/widgets/global_mini_player_bar.dart';
import 'package:almomin/features/home/widgets/home_date_header_card.dart';
import 'package:almomin/features/home/widgets/home_next_prayer_card.dart';
import 'package:almomin/features/home/widgets/home_quran_continue_card.dart';
import 'package:almomin/features/mushaf/mushaf_screen.dart';
import 'package:almomin/features/onboarding/onboarding_screen.dart';
import 'package:almomin/features/prayer/hijri_calendar_screen.dart';
import 'package:almomin/features/prayer/prayer_times_detail_screen.dart';
import 'package:almomin/features/settings/settings_screen.dart';

const List<String> _forbiddenHubAndDrawerLabels = [
  'إشراقة اليوم',
  'رحاب القرآن',
  'محراب الصلاة',
  'أُنس الذاكرين',
  'رياض العلم',
  'الدعاء للمرحوم مؤمن إبراهيم رحمه الله — صدقة جارية',
  'ابحث عن أي قسم أو خدمة في التطبيق...',
  'القائمة الإيمانية الشاملة ☰',
  'أقسام النور والوصول السريع',
];

Future<void> _loadBundledFontsForTest() async {
  final cairoFile = File('assets/fonts/Cairo-Regular.ttf');
  if (cairoFile.existsSync()) {
    final bytes = cairoFile.readAsBytesSync();
    final cairoLoader = FontLoader('Cairo');
    cairoLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
    await cairoLoader.load();

    final robotoLoader = FontLoader('Roboto');
    robotoLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
    await robotoLoader.load();
  }

  final amiriLoader = FontLoader('Amiri');
  final amiriReg = File('assets/fonts/Amiri-Regular.ttf');
  if (amiriReg.existsSync()) {
    amiriLoader.addFont(Future.value(ByteData.view(amiriReg.readAsBytesSync().buffer)));
  }
  final amiriBold = File('assets/fonts/Amiri-Bold.ttf');
  if (amiriBold.existsSync()) {
    amiriLoader.addFont(Future.value(ByteData.view(amiriBold.readAsBytesSync().buffer)));
  }
  await amiriLoader.load();

  final quranFile = File('assets/fonts/AmiriQuran-Regular.ttf');
  if (quranFile.existsSync()) {
    final quranLoader = FontLoader('AmiriQuran');
    quranLoader.addFont(Future.value(ByteData.view(quranFile.readAsBytesSync().buffer)));
    await quranLoader.load();
  }

  final iconFile = File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf');
  if (iconFile.existsSync()) {
    final iconLoader = FontLoader('MaterialIcons');
    iconLoader.addFont(Future.value(ByteData.view(iconFile.readAsBytesSync().buffer)));
    await iconLoader.load();
  }
}

void _assertActiveSemanticsIsolated(WidgetTester tester, String routeContext) {
  final traversal = tester.semantics.simulatedAccessibilityTraversal();
  final labels = traversal
      .map((n) => n.getSemanticsData().label)
      .where((l) => l.isNotEmpty)
      .toList();

  expect(labels, isNotEmpty, reason: '$routeContext must expose meaningful semantic content');

  for (final forbidden in _forbiddenHubAndDrawerLabels) {
    expect(
      labels.any((l) => l.contains(forbidden)),
      isFalse,
      reason: '$routeContext leaked forbidden hub/tab/drawer label "$forbidden" into active semantics traversal',
    );
  }
}

Widget _buildRouterApp({double textScale = 1.0}) {
  return MaterialApp.router(
    theme: AppTheme.lightTheme,
    routerConfig: appRouter,
    builder: (context, child) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      );
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadBundledFontsForTest();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'has_completed_onboarding': true,
      'show_tutorial_screens': false,
    });
    await SettingsService.instance.init();
    await PrayerTrackerService.instance.init(forceReload: true);
    await SunanRawatibService.instance.init(forceReload: true);
    await DailyWirdService.instance.init(forceReload: true);
    IslamicAudioService.instance.disableNativePlayerForTesting = true;
    await IslamicAudioService.instance.stop();
  });

  tearDown(() async {
    PrayerService.instance.stopLiveTicker();
    await IslamicAudioService.instance.stop();
    appRouter.go('/momen-duaa');
  });

  group('Repair 1: Full-Page Navigation & Accessibility Focus Isolation', () {
    test('All feature/detail routes are root-isolated outside ShellRoute; ShellRoute retains only 5 hubs + alias', () {
      final topLevelRoutes = appRouter.configuration.routes;
      final shellRoutes = topLevelRoutes.whereType<ShellRoute>().toList();
      expect(shellRoutes.length, equals(1), reason: 'Exactly one ShellRoute should host the hub tabs');

      final shellChildPaths = shellRoutes.single.routes
          .whereType<GoRoute>()
          .map((r) => r.path)
          .toSet();

      expect(
        shellChildPaths,
        equals(kHubShellRoutePaths),
        reason: 'ShellRoute must contain ONLY the 5 top-level hubs plus /quran-hub alias',
      );
      expect(shellChildPaths.length, equals(6));

      final topLevelGoRoutes = topLevelRoutes.whereType<GoRoute>().toList();
      final standalonePaths = {'/momen-duaa', '/duaa', '/onboarding', '/adhan-control', '/scholars-audio'};
      final featureGoRoutes = topLevelGoRoutes
          .where((r) => !standalonePaths.contains(r.path))
          .toList();

      expect(featureGoRoutes.length, greaterThanOrEqualTo(53));
      for (final route in featureGoRoutes) {
        expect(
          kHubShellRoutePaths.contains(route.path),
          isFalse,
          reason: 'Feature route ${route.path} must not be duplicated in ShellRoute',
        );
        expect(
          route.parentNavigatorKey,
          equals(rootNavigatorKey),
          reason: 'Feature route ${route.path} must target rootNavigatorKey for full-page isolation',
        );
      }

      final retiredRoute = topLevelGoRoutes.singleWhere((r) => r.path == '/scholars-audio');
      expect(retiredRoute.redirect, isNotNull);
      expect(retiredRoute.builder, isNull);

      final featurePaths = featureGoRoutes.map((r) => r.path).toSet();
      const expectedFeaturePaths = {
        '/tasbih',
        '/adhkar',
        '/qibla',
        '/calendar',
        '/prayer-times-detail',
        '/prayer-tracker',
        '/sunan-rawatib',
        '/mushaf-reader',
        '/mushaf-pages',
        '/surah-reader',
        '/search',
        '/comparative-tafsir',
        '/audio-tafsir',
        '/qiraat',
        '/approved-sources',
        '/audio',
        '/settings',
        '/hadith',
        '/zakat',
        '/khatma',
        '/daily-wird',
        '/app-screen-directory',
      };
      for (final path in expectedFeaturePaths) {
        expect(featurePaths.contains(path), isTrue, reason: 'Expected root-isolated route $path to exist');
      }
    });

    testWidgets('Navigating to /home?openDrawer=true lands cleanly on Home without auto-opening AppNavigationDrawer', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      appRouter.go('/home?openDrawer=true');
      await tester.pumpWidget(_buildRouterApp());
      await tester.pumpAndSettle();

      expect(find.byType(AppNavigationDrawer), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);

      final traversalLabels = tester.semantics
          .simulatedAccessibilityTraversal()
          .map((n) => n.getSemanticsData().label)
          .where((l) => l.isNotEmpty)
          .toList();
      expect(
        traversalLabels.any((l) => l.contains('ابحث عن أي قسم أو خدمة في التطبيق')),
        isFalse,
        reason: 'Drawer search field must not appear on Home arrival',
      );

      PrayerService.instance.stopLiveTicker();
      semantics.dispose();
    });

    testWidgets('Real router push + back isolates representative feature routes without duplicate back actions', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      appRouter.go('/home');
      await tester.pumpWidget(_buildRouterApp());
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);

      final routesToVerify = <String>[
        '/tasbih',
        '/sunan-rawatib',
        '/prayer-tracker',
        '/settings',
        '/search',
        '/qiraat',
        '/audio-tafsir',
        '/approved-sources',
      ];

      for (final routePath in routesToVerify) {
        appRouter.push(routePath);
        await tester.pumpAndSettle();

        expect(find.byType(IsolatedFeatureRouteHost), findsOneWidget, reason: '$routePath must be hosted in IsolatedFeatureRouteHost');
        expect(find.byType(NavigationBar), findsNothing, reason: '$routePath must not display hub NavigationBar');
        expect(find.byType(AppNavigationDrawer), findsNothing, reason: '$routePath must not open AppNavigationDrawer');
        // No duplicate fallback bar when route can pop normally
        expect(find.byKey(const ValueKey('isolated_direct_back_home_button')), findsNothing,
            reason: 'Pushed $routePath must not add duplicate direct-back banner');

        _assertActiveSemanticsIsolated(tester, routePath);

        final backFinder = find.byType(BackButton);
        final arrowBackFinder = find.byIcon(Icons.arrow_back_rounded);
        expect(
          backFinder.evaluate().length + arrowBackFinder.evaluate().length,
          equals(1),
          reason: '$routePath must expose exactly one visible AppBar back control',
        );

        if (backFinder.evaluate().isNotEmpty) {
          await tester.tap(backFinder.first);
        } else {
          await tester.tap(arrowBackFinder.first);
        }
        await tester.pumpAndSettle();

        expect(find.byType(NavigationBar), findsOneWidget, reason: 'Popping $routePath must return to /home hub');
      }

      PrayerService.instance.stopLiveTicker();
      semantics.dispose();
    });

    testWidgets('Home-card pushes open isolated root routes and back returns cleanly to Home', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      appRouter.go('/home');
      await tester.pumpWidget(_buildRouterApp());
      await tester.pumpAndSettle();

      // 1. HomeDateHeaderCard -> HijriCalendarScreen
      await tester.tap(find.byType(HomeDateHeaderCard));
      await tester.pumpAndSettle();
      expect(find.byType(HijriCalendarScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      _assertActiveSemanticsIsolated(tester, 'HomeDateHeaderCard -> /calendar');
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);

      // 2. HomeNextPrayerCard -> PrayerTimesDetailScreen
      await tester.tap(find.byType(HomeNextPrayerCard));
      await tester.pumpAndSettle();
      expect(find.byType(PrayerTimesDetailScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      _assertActiveSemanticsIsolated(tester, 'HomeNextPrayerCard -> /prayer-times-detail');
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);

      // 3. HomeQuranContinueCard index button -> MushafScreen
      final mushafIndexBtn = find.descendant(
        of: find.byType(HomeQuranContinueCard),
        matching: find.byIcon(Icons.list_alt_rounded),
      );
      await tester.ensureVisible(mushafIndexBtn);
      await tester.pumpAndSettle();
      await tester.tap(mushafIndexBtn);
      await tester.pumpAndSettle();
      expect(find.byType(MushafScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      _assertActiveSemanticsIsolated(tester, 'HomeQuranContinueCard -> /mushaf-reader');
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);

      // 4. HomeAdhkarTasbihRow Tasbih card -> TasbihScreen
      final tasbihCard = find.text('السبحة الذكية');
      await tester.ensureVisible(tasbihCard);
      await tester.pumpAndSettle();
      await tester.tap(tasbihCard);
      await tester.pumpAndSettle();
      expect(find.byType(TasbihScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      _assertActiveSemanticsIsolated(tester, 'HomeAdhkarTasbihRow -> /tasbih');
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);

      PrayerService.instance.stopLiveTicker();
      semantics.dispose();
    });

    testWidgets('Direct deep links on settings, 3 drawer-removed screens, and generic isolated routes expose single visible reachable back action', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 1. Screens with their own IsolatedBackButton: /settings, /qiraat, /audio-tafsir, /approved-sources
      const ownBackRoutes = ['/settings', '/qiraat', '/audio-tafsir', '/approved-sources'];
      for (final path in ownBackRoutes) {
        appRouter.go(path);
        await tester.pumpWidget(_buildRouterApp());
        await tester.pumpAndSettle();

        expect(find.byType(NavigationBar), findsNothing, reason: 'Direct deep link $path must isolate from NavigationBar');
        expect(find.byIcon(Icons.menu_rounded), findsNothing, reason: 'Direct deep link $path must show Back, never drawer menu');
        expect(find.byKey(const ValueKey('isolated_direct_back_home_button')), findsNothing,
            reason: 'Direct deep link $path already has IsolatedBackButton — must not duplicate');
        expect(find.byType(IsolatedBackButton), findsOneWidget);
        expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
        _assertActiveSemanticsIsolated(tester, 'Direct deep link $path');

        // Tap visible on-screen Back button and verify clean return to /home
        await tester.tap(find.byType(IsolatedBackButton));
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsOneWidget, reason: 'Tapping visible Back on deep-linked $path must return to /home');
      }

      // 2. Generic isolated route direct deep link (/tasbih): host provides single visible back-to-home bar
      appRouter.go('/tasbih');
      await tester.pumpWidget(_buildRouterApp());
      await tester.pumpAndSettle();

      expect(find.byType(TasbihScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BackButton), findsNothing, reason: 'AppBar omits BackButton when canPop is false');
      final directBackBtn = find.byKey(const ValueKey('isolated_direct_back_home_button'));
      expect(directBackBtn, findsOneWidget, reason: 'Host must expose single visible back-to-home button on direct deep link');
      _assertActiveSemanticsIsolated(tester, 'Direct deep link /tasbih');

      // Tap visible on-screen back-to-home button
      await tester.tap(directBackBtn);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);

      // 3. System back on direct deep link also returns to /home
      appRouter.go('/tasbih');
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);

      PrayerService.instance.stopLiveTicker();
      semantics.dispose();
    });

    testWidgets('Actual 1.0x and 2.0x isolation with active audio playback, mini-player stop, and back navigation', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const sampleTrack = IslamicAudioTrack(
        id: 'test_quran_scale',
        title: 'سورة الفاتحة',
        subtitle: 'تلاوة تجريبية',
        type: IslamicAudioType.quran,
        durationFormatted: '01:00',
      );

      // 1. Pushed /tasbih with active audio playback at 1.0x -> stop -> back to /home (zero exceptions)
      appRouter.go('/home');
      await tester.pumpWidget(_buildRouterApp(textScale: 1.0));
      await tester.pumpAndSettle();
      await IslamicAudioService.instance.playTrack(sampleTrack);
      await tester.pump();

      appRouter.push('/tasbih');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        MediaQuery.textScalerOf(tester.element(find.byType(TasbihScreen))).scale(10),
        equals(10.0),
      );
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(GlobalMiniPlayerBar), findsOneWidget);
      expect(find.text('سورة الفاتحة'), findsOneWidget);
      _assertActiveSemanticsIsolated(tester, 'Pushed /tasbih with active mini-player at 1.0x');

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(IslamicAudioService.instance.currentTrack, isNull);
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 2. Isolated /settings with active audio playback at BOTH 1.0x and 2.0x -> stop -> visible Back
      for (final scale in [1.0, 2.0]) {
        // Switch router to /settings at 1.0x first so /home is never rebuilt at 2.0x during transition
        appRouter.go('/settings');
        await tester.pumpAndSettle();
        await tester.pumpWidget(_buildRouterApp(textScale: scale));
        await tester.pumpAndSettle();

        await IslamicAudioService.instance.playTrack(sampleTrack);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify effective TextScaler at BOTH SettingsScreen and GlobalMiniPlayerBar
        final settingsCtx = tester.element(find.byType(SettingsScreen));
        final miniPlayerCtx = tester.element(find.byType(GlobalMiniPlayerBar));
        expect(
          MediaQuery.textScalerOf(settingsCtx).scale(10),
          equals(scale * 10),
          reason: 'Effective TextScaler at SettingsScreen must equal ${scale}x',
        );
        expect(
          MediaQuery.textScalerOf(miniPlayerCtx).scale(10),
          equals(scale * 10),
          reason: 'Effective TextScaler at GlobalMiniPlayerBar must equal ${scale}x',
        );

        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byIcon(Icons.menu_rounded), findsNothing);
        expect(find.byType(IsolatedBackButton), findsOneWidget);
        expect(find.byType(GlobalMiniPlayerBar), findsOneWidget);
        expect(find.text('سورة الفاتحة'), findsOneWidget);
        expect(find.byIcon(Icons.close_rounded), findsOneWidget);
        _assertActiveSemanticsIsolated(tester, '/settings with active mini-player at ${scale}x');

        // Stop playback via mini-player stop control
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
        expect(IslamicAudioService.instance.currentTrack, isNull);
        expect(find.text('سورة الفاتحة'), findsNothing);
        expect(tester.takeException(), isNull,
            reason: 'Isolated /settings + GlobalMiniPlayerBar at ${scale}x must produce zero exceptions/overflows');

        // Tap visible Back arrow to return to /home — zero overflows at BOTH 1.0x and 2.0x
        await tester.tap(find.byType(IsolatedBackButton));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'Returning to /home at 412x915 ${scale}x must produce zero exceptions/overflows');
        expect(find.byType(NavigationBar), findsOneWidget);
      }

      PrayerService.instance.stopLiveTicker();
      semantics.dispose();
    });

    testWidgets('Effective TextScaler 1.0x and 2.0x verified inside direct deep-linked SettingsScreen with visible Back arrow', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final scale in [1.0, 2.0]) {
        appRouter.go('/settings');
        if (find.byType(MaterialApp).evaluate().isNotEmpty) {
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(_buildRouterApp(textScale: scale));
        await tester.pumpAndSettle();

        final settingsCtx = tester.element(find.byType(SettingsScreen));
        expect(
          MediaQuery.textScalerOf(settingsCtx).scale(10),
          equals(scale * 10),
          reason: 'Effective TextScaler at SettingsScreen must be ${scale}x via MaterialApp.router builder',
        );

        expect(find.byType(IsolatedFeatureRouteHost), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byIcon(Icons.menu_rounded), findsNothing, reason: 'Direct /settings must show Back arrow, NOT menu icon');
        expect(find.byKey(const ValueKey('isolated_direct_back_home_button')), findsNothing,
            reason: 'Direct /settings uses its own IsolatedBackButton without duplicate host bar');
        expect(find.byType(IsolatedBackButton), findsOneWidget);
        _assertActiveSemanticsIsolated(tester, 'Direct /settings at 360x800 ${scale}x');
        expect(tester.takeException(), isNull,
            reason: 'Direct /settings at 360x800 ${scale}x must render without layout/runtime exception');

        // Tap visible Back arrow to return to /home — zero overflows at BOTH 360x800 1.0x and 2.0x
        await tester.tap(find.byType(IsolatedBackButton));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'Returning to /home at 360x800 ${scale}x must produce zero exceptions/overflows');
        expect(find.byType(NavigationBar), findsOneWidget);
      }

      PrayerService.instance.stopLiveTicker();
      semantics.dispose();
    });

    testWidgets('Onboarding push from HomeScreen isolates on root navigator without bottom NavigationBar', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'has_completed_onboarding': false,
        'show_tutorial_screens': true,
      });
      await SettingsService.instance.init();

      appRouter.go('/home');
      await tester.pumpWidget(_buildRouterApp());
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      _assertActiveSemanticsIsolated(tester, 'OnboardingScreen root push');

      PrayerService.instance.stopLiveTicker();
      semantics.dispose();
    });
  });
}
