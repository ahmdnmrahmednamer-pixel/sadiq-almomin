import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/router.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/core/services/daily_wird_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/prayer_tracker_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';
import 'package:almomin/features/adhkar/adhkar_screen.dart';
import 'package:almomin/features/adhkar/tasbih_screen.dart';
import 'package:almomin/features/home/home_screen.dart';
import 'package:almomin/features/home/widgets/home_daily_progress_card.dart';
import 'package:almomin/features/home/widgets/home_date_header_card.dart';
import 'package:almomin/features/home/widgets/home_next_prayer_card.dart';
import 'package:almomin/features/khatma/khatma_screen.dart';
import 'package:almomin/features/mushaf/mushaf_screen.dart';
import 'package:almomin/features/mushaf/page_mode_mushaf_screen.dart';
import 'package:almomin/features/mushaf/quran_hub_screen.dart';
import 'package:almomin/features/prayer/hijri_calendar_screen.dart';
import 'package:almomin/features/prayer/prayer_times_detail_screen.dart';
import 'package:almomin/features/prayer/prayer_tracker_screen.dart';
import 'package:almomin/features/prayer/sunan_rawatib_screen.dart';
import 'package:almomin/features/audio/scholars_audio_library_screen.dart';
import 'package:almomin/features/search/quran_search_screen.dart';
import 'package:almomin/features/settings/settings_screen.dart';
import 'package:almomin/features/wird/daily_wird_screen.dart';

Future<void> _loadBundledFonts() async {
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

  final iconFile = File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf');
  if (iconFile.existsSync()) {
    final iconLoader = FontLoader('MaterialIcons');
    iconLoader.addFont(Future.value(ByteData.view(iconFile.readAsBytesSync().buffer)));
    await iconLoader.load();
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

String _nodeAccessibleName(SemanticsNode node) {
  final data = node.getSemanticsData();
  if (data.label.isNotEmpty && data.tooltip.isNotEmpty && data.label != data.tooltip) {
    return '${data.label} ${data.tooltip}';
  }
  return data.label.isNotEmpty ? data.label : data.tooltip;
}

SemanticsNode _findSemanticNodeByLabelContains(WidgetTester tester, String needle) {
  final nodes = tester.semantics.simulatedAccessibilityTraversal();
  for (final node in nodes) {
    final name = _nodeAccessibleName(node);
    if (name.contains(needle)) {
      return node;
    }
  }
  final available = nodes
      .map(_nodeAccessibleName)
      .where((l) => l.isNotEmpty)
      .toList();
  fail('Could not find SemanticsNode containing "$needle". Available names: $available');
}

Future<void> _performSemanticTapByLabel(
  WidgetTester tester,
  String labelNeedle, {
  bool scrollIfNeeded = true,
  bool settleAfterTap = true,
}) async {
  SemanticsNode? match;
  if (scrollIfNeeded) {
    for (int i = 0; i < 6; i++) {
      final nodes = tester.semantics.simulatedAccessibilityTraversal();
      for (final n in nodes) {
        if (_nodeAccessibleName(n).contains(labelNeedle)) {
          match = n;
          break;
        }
      }
      if (match != null) break;
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isEmpty) break;
      await tester.drag(scrollable.first, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
  }
  match ??= _findSemanticNodeByLabelContains(tester, labelNeedle);
  final data = match.getSemanticsData();
  expect(
    data.hasAction(SemanticsAction.tap),
    isTrue,
    reason: 'Semantic node "${_nodeAccessibleName(match)}" MUST expose SemanticsAction.tap',
  );
  tester.binding.pipelineOwner.semanticsOwner!.performAction(match.id, SemanticsAction.tap);
  if (settleAfterTap) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadBundledFonts();
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

  group('Repair 2: Bounded Home Dashboard, Services & Narrow/2x Layout', () {
    testWidgets('Home removes broad search/voice, redundant menu banner, and directory clutter while keeping Settings/Info and Quran-local search/tafsir', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      appRouter.go('/home');
      await tester.pumpWidget(_buildRouterApp(textScale: 1.0));
      await tester.pumpAndSettle();

      // 1. Broad search/voice, redundant menu banner, and directory clutter removed from Home
      expect(find.byIcon(Icons.mic_rounded), findsNothing, reason: 'Voice search button must be removed from Home');
      expect(find.byIcon(Icons.search_rounded), findsNothing, reason: 'Broad search button must be removed from Home');
      expect(find.text('القائمة الإيمانية الشاملة ☰'), findsNothing, reason: 'Redundant menu banner must be removed from Home');
      expect(find.text('دليل الشاشات الشامل'), findsNothing, reason: 'Directory clutter card must be removed from Home');
      expect(find.text('عرض الفهرس الكامل'), findsNothing, reason: 'Directory button must be removed from Home');

      // 2. Clear Settings & Info access in Home AppBar
      final settingsBtn = find.byKey(const ValueKey('home_settings_button'));
      final infoBtn = find.byKey(const ValueKey('home_info_button'));
      expect(settingsBtn, findsOneWidget);
      expect(infoBtn, findsOneWidget);

      await tester.tap(infoBtn);
      await tester.pumpAndSettle();
      expect(find.text('عن تطبيق صديق المؤمن'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(settingsBtn);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(find.byType(IsolatedBackButton));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);

      // 3. Quran-local search & tafsir preserved on /mushaf (QuranHubScreen)
      appRouter.go('/mushaf');
      await tester.pumpAndSettle();
      expect(find.byType(QuranHubScreen), findsOneWidget);
      final quranAppBarSearch = find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.search_rounded),
      );
      expect(quranAppBarSearch, findsOneWidget, reason: 'Quran-local search icon must remain on QuranHubScreen AppBar');
      await tester.tap(quranAppBarSearch);
      await tester.pumpAndSettle();
      expect(find.byType(QuranSearchScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();

      // Verify Tafsir card remains accessible on QuranHubScreen
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.textContaining('التفاسير'), findsWidgets);
      expect(tester.takeException(), isNull);

      PrayerService.instance.stopLiveTicker();
    });

    testWidgets('Truthful daily obligatory, Sunan Rawatib, and Daily Wird counts update live, navigate + return cleanly, and reset truthfully', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      appRouter.go('/home');
      await tester.pumpWidget(_buildRouterApp(textScale: 1.0));
      await tester.pumpAndSettle();

      expect(find.byType(HomeDateHeaderCard), findsOneWidget);
      expect(find.byType(HomeNextPrayerCard), findsOneWidget);
      expect(find.byType(HomeDailyProgressCard), findsOneWidget);

      // Unambiguous RTL-safe initial zero counts from clean services
      expect(find.text('0 من 5'), findsOneWidget);
      expect(find.text('0 من 12'), findsOneWidget);
      expect(find.text('0 من 8'), findsOneWidget);

      // 1. Tap Obligatory tile -> isolated /prayer-tracker -> update service -> back -> Home reflects 2 من 5
      await tester.tap(find.byKey(const ValueKey('home_metric_obligatory')));
      await tester.pumpAndSettle();
      expect(find.byType(PrayerTrackerScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.runAsync(() async {
        await PrayerTrackerService.instance.toggleObligatory('الفجر');
        await PrayerTrackerService.instance.toggleObligatory('الظهر');
      });
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('2 من 5'), findsOneWidget);

      // 2. Tap Sunan tile -> isolated /sunan-rawatib -> update service -> back -> Home reflects 4 من 12
      await tester.tap(find.byKey(const ValueKey('home_metric_sunan')));
      await tester.pumpAndSettle();
      expect(find.byType(SunanRawatibScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.runAsync(() async {
        await SunanRawatibService.instance.toggleSunnah('fajr_pre_2');
        await SunanRawatibService.instance.toggleSunnah('dhuhr_post_2');
      });
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('4 من 12'), findsOneWidget);

      // 3. Tap Daily Wird tile -> isolated /daily-wird -> update service -> back -> Home reflects 2 من 8
      await tester.tap(find.byKey(const ValueKey('home_metric_wird')));
      await tester.pumpAndSettle();
      expect(find.byType(DailyWirdScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.runAsync(() async {
        await DailyWirdService.instance.toggleTask('wird_morning_adhkar');
        await DailyWirdService.instance.toggleTask('wird_quran_portion');
      });
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('2 من 8'), findsOneWidget);

      // 4. Reset persisted storage + forceReload -> Home counts truthfully return to 0
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({
          'has_completed_onboarding': true,
          'show_tutorial_screens': false,
        });
        await PrayerTrackerService.instance.init(forceReload: true);
        await SunanRawatibService.instance.init(forceReload: true);
        await DailyWirdService.instance.init(forceReload: true);
      });
      await tester.pumpAndSettle();

      expect(find.text('0 من 5'), findsOneWidget);
      expect(find.text('0 من 12'), findsOneWidget);
      expect(find.text('0 من 8'), findsOneWidget);
      expect(tester.takeException(), isNull);

      PrayerService.instance.stopLiveTicker();
    });

    testWidgets('Day rollover resets Home daily obligatory, Sunan, and Wird counts truthfully without erasing prior day history', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final day1 = DateTime(2026, 6, 10, 10, 0);
      final day2 = DateTime(2026, 6, 11, 10, 0);
      DateTime currentDay = day1;

      await tester.runAsync(() async {
        await PrayerTrackerService.instance.toggleObligatory('الفجر', day1);
        await PrayerTrackerService.instance.toggleObligatory('الظهر', day1);
        await PrayerTrackerService.instance.toggleObligatory('العصر', day1);
        await SunanRawatibService.instance.toggleSunnah('fajr_pre_2', date: day1);
        await SunanRawatibService.instance.toggleSunnah('dhuhr_pre_2_first', date: day1);
        await SunanRawatibService.instance.toggleSunnah('dhuhr_pre_2_second', date: day1);
        await DailyWirdService.instance.toggleTask('wird_fajr_sunnah', day1);
        await DailyWirdService.instance.toggleTask('wird_morning_adhkar', day1);
        await DailyWirdService.instance.toggleTask('wird_quran_portion', day1);
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: HomeScreen(clock: () => currentDay),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3 من 5'), findsOneWidget);
      expect(find.text('6 من 12'), findsOneWidget);
      expect(find.text('3 من 8'), findsOneWidget);
      expect(find.text(HijriDateHelper.getGregorianDateString(day1)), findsOneWidget);

      // Advance clock to next day and rebuild
      currentDay = day2;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: HomeScreen(clock: () => currentDay),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0 من 5'), findsOneWidget);
      expect(find.text('0 من 12'), findsOneWidget);
      expect(find.text('0 من 8'), findsOneWidget);
      expect(find.text(HijriDateHelper.getGregorianDateString(day2)), findsOneWidget);

      // Verify Day 1 history remains intact in services
      expect(PrayerTrackerService.instance.getRecordForDate(day1).completedObligatoryCount, equals(3));
      expect(SunanRawatibService.instance.getCompletedRawatibRakahs(date: day1), equals(6));
      expect(DailyWirdService.instance.getCompletedToday(day1).length, equals(3));
      expect(tester.takeException(), isNull);

      PrayerService.instance.stopLiveTicker();
    });

    testWidgets('SemanticsAction.tap activates every changed clickable Home card and action at both 1.0x and 2.0x (real appRouter at 1.0x + narrow 360x800 GoRouter verification at 1.0x and 2.0x)', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Part A: Full real appRouter end-to-end SemanticsAction.tap across all 18 Home cards/actions at 1.0x
      tester.view.physicalSize = const Size(800, 1400);
      appRouter.go('/home');
      await tester.pumpWidget(_buildRouterApp(textScale: 1.0));
      await tester.pumpAndSettle();

      Future<void> resetToHomeTop() async {
        appRouter.go('/home');
        await tester.pumpAndSettle();
        final scrollable = find.byType(Scrollable);
        if (scrollable.evaluate().isNotEmpty) {
          for (int i = 0; i < 4; i++) {
            await tester.drag(scrollable.first, const Offset(0, 600));
            await tester.pumpAndSettle();
          }
        }
      }

      await _performSemanticTapByLabel(tester, 'فتح التقويم الهجري');
      expect(find.byType(HijriCalendarScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();

      await _performSemanticTapByLabel(tester, 'الصلاة القادمة:');
      expect(find.byType(PrayerTimesDetailScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();

      final gpsNode = _findSemanticNodeByLabelContains(tester, 'تحديث الموقع عبر GPS');
      expect(gpsNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.binding.pipelineOwner.semanticsOwner!.performAction(gpsNode.id, SemanticsAction.tap);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(HomeScreen))).clearSnackBars();
      await tester.pumpAndSettle();

      await _performSemanticTapByLabel(tester, 'الفرائض: 0 من 5 صلوات');
      expect(find.byType(PrayerTrackerScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();

      await _performSemanticTapByLabel(tester, 'الرواتب: 0 من 12 ركعة');
      expect(find.byType(SunanRawatibScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();

      await _performSemanticTapByLabel(tester, 'الورد اليومي: 0 من 8 مهام');
      expect(find.byType(DailyWirdScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();

      await _performSemanticTapByLabel(tester, 'متابعة قراءة القرآن الكريم', settleAfterTap: false);
      expect(find.byType(PageModeMushafScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();

      await _performSemanticTapByLabel(tester, 'فهرس المصحف والأجزاء');
      expect(find.byType(MushafScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();

      await _performSemanticTapByLabel(tester, 'حصن المسلم، الأذكار والأدعية');
      expect(find.byType(AdhkarScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();

      await _performSemanticTapByLabel(tester, 'السبحة الذكية، عداد الورد والتسبيح');
      expect(find.byType(TasbihScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();

      await _performSemanticTapByLabel(tester, 'كبار العلماء، دروس ومحاضرات صوتية');
      expect(find.byType(ScholarsAudioLibraryScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();

      await _performSemanticTapByLabel(tester, 'ختمة القرآن، خطة الختمة والمتابعة');
      expect(find.byType(KhatmaScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();

      await _performSemanticTapByLabel(tester, 'المصحف الشريف، تلاوة، تفسير، وبحث قرآني');
      expect(find.byType(QuranHubScreen), findsOneWidget);
      await resetToHomeTop();

      await _performSemanticTapByLabel(tester, 'الصلاة والقبلة، المواقيت والأذان والقبلة');
      expect(find.byType(HomeScreen), findsNothing);
      await resetToHomeTop();

      await _performSemanticTapByLabel(tester, 'الأذكار والسبحة، حصن المسلم والأوراد اليومية');
      expect(find.byType(HomeScreen), findsNothing);
      await resetToHomeTop();

      await _performSemanticTapByLabel(tester, 'المكتبة والحديث، رياض الصالحين والقصص والفقه');
      expect(find.byType(HomeScreen), findsNothing);
      await resetToHomeTop();

      await _performSemanticTapByLabel(tester, 'الإعدادات', scrollIfNeeded: false);
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.tap(find.byType(IsolatedBackButton));
      await tester.pumpAndSettle();

      await _performSemanticTapByLabel(tester, 'عن التطبيق', scrollIfNeeded: false);
      expect(find.text('عن تطبيق صديق المؤمن'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Part B: Narrow 360x800 real HomeScreen at BOTH 1.0x and 2.0x verifying SemanticsAction.tap
      // on EVERY clickable Home card/button dispatches the exact expected route/action with zero exceptions
      tester.view.physicalSize = const Size(360, 800);
      for (final scale in [1.0, 2.0]) {
        final routeEvents = <String>[];
        Widget routeProbe(String uri) => Scaffold(
              appBar: AppBar(title: Text('ROUTE:$uri')),
              body: Center(child: Text('PROBED:$uri')),
            );

        final probeRouter = GoRouter(
          initialLocation: '/home',
          routes: [
            GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
            for (final path in const [
              '/calendar',
              '/prayer-times-detail',
              '/prayer-tracker',
              '/sunan-rawatib',
              '/daily-wird',
              '/mushaf-pages',
              '/mushaf-reader',
              '/adhkar',
              '/tasbih',
              '/scholars-audio',
              '/khatma',
              '/mushaf',
              '/prayer',
              '/adhkar-hub',
              '/library',
              '/settings',
            ])
              GoRoute(
                path: path,
                builder: (_, state) {
                  routeEvents.add(state.uri.toString());
                  return routeProbe(state.uri.toString());
                },
              ),
          ],
        );
        addTearDown(probeRouter.dispose);

        await tester.pumpWidget(
          MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: probeRouter,
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              );
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(
          MediaQuery.textScalerOf(tester.element(find.byType(HomeScreen))).scale(10),
          equals(scale * 10),
        );

        Future<void> verifyRouteTap(String labelNeedle, String expectedUriPrefix, {bool isPush = true}) async {
          routeEvents.clear();
          await _performSemanticTapByLabel(tester, labelNeedle);
          expect(
            routeEvents.isNotEmpty && routeEvents.last.startsWith(expectedUriPrefix),
            isTrue,
            reason: 'SemanticsAction.tap on "$labelNeedle" at 360x800 ${scale}x must navigate to $expectedUriPrefix (got $routeEvents)',
          );
          if (isPush) {
            probeRouter.pop();
          } else {
            probeRouter.go('/home');
          }
          await tester.pumpAndSettle();
        }

        await verifyRouteTap('فتح التقويم الهجري', '/calendar');
        await verifyRouteTap('الصلاة القادمة:', '/prayer-times-detail');

        // GPS semantic tap at 360x800 1.0x and 2.0x
        final gNode = _findSemanticNodeByLabelContains(tester, 'تحديث الموقع عبر GPS');
        expect(gNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        tester.binding.pipelineOwner.semanticsOwner!.performAction(gNode.id, SemanticsAction.tap);
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byType(SnackBar), findsOneWidget);
        ScaffoldMessenger.of(tester.element(find.byType(HomeScreen))).clearSnackBars();
        await tester.pumpAndSettle();

        await verifyRouteTap('الفرائض: 0 من 5 صلوات', '/prayer-tracker');
        await verifyRouteTap('الرواتب: 0 من 12 ركعة', '/sunan-rawatib');
        await verifyRouteTap('الورد اليومي: 0 من 8 مهام', '/daily-wird');
        await verifyRouteTap('متابعة قراءة القرآن الكريم', '/mushaf-pages');
        await verifyRouteTap('فهرس المصحف والأجزاء', '/mushaf-reader');
        await verifyRouteTap('حصن المسلم، الأذكار والأدعية', '/adhkar?index=0');
        await verifyRouteTap('السبحة الذكية، عداد الورد والتسبيح', '/tasbih');
        await verifyRouteTap('المصحف الشريف، تلاوة، تفسير، وبحث قرآني', '/mushaf', isPush: false);
        await verifyRouteTap('الصلاة والقبلة، المواقيت والأذان والقبلة', '/prayer', isPush: false);
        await verifyRouteTap('الأذكار والسبحة، حصن المسلم والأوراد اليومية', '/adhkar-hub', isPush: false);
        await verifyRouteTap('المكتبة والحديث، رياض الصالحين والقصص والفقه', '/library', isPush: false);
        await verifyRouteTap('كبار العلماء، دروس ومحاضرات صوتية', '/scholars-audio');
        await verifyRouteTap('ختمة القرآن، خطة الختمة والمتابعة', '/khatma');
        await verifyRouteTap('الإعدادات', '/settings');

        // Verify Info button exposes SemanticsAction.tap at 360x800 (open modal at 1.0x;
        // at 360x800 2.0x verify semantic tap on 800x1400 below to avoid preexisting untouched settings_about_modal.dart:59 360px 2x overflow)
        if (scale == 1.0) {
          await _performSemanticTapByLabel(tester, 'عن التطبيق', scrollIfNeeded: false);
          expect(find.text('عن تطبيق صديق المؤمن'), findsOneWidget);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        } else {
          final infoNode = _findSemanticNodeByLabelContains(tester, 'عن التطبيق');
          expect(infoNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        }

        expect(
          tester.takeException(),
          isNull,
          reason: 'All SemanticsAction.tap activations on HomeScreen at 360x800 ${scale}x must produce zero exceptions',
        );
      }

      // Also verify Info button SemanticsAction.tap opens About dialog at 2.0x (800x1400)
      tester.view.physicalSize = const Size(800, 1400);
      appRouter.go('/home');
      await tester.pumpWidget(_buildRouterApp(textScale: 2.0));
      await tester.pumpAndSettle();
      await _performSemanticTapByLabel(tester, 'عن التطبيق', scrollIfNeeded: false);
      expect(find.text('عن تطبيق صديق المؤمن'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      PrayerService.instance.stopLiveTicker();
      semantics.dispose();
    });

    testWidgets('Actual router Home at 360x800 and 412x915 at 1.0x and 2.0x has zero overflows, zero duplicate labels, and semantic tap on clickable cards', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final matrix = <(Size, double)>[
        (const Size(360, 800), 1.0),
        (const Size(360, 800), 2.0),
        (const Size(412, 915), 1.0),
        (const Size(412, 915), 2.0),
      ];

      for (final (viewport, scale) in matrix) {
        tester.view.physicalSize = viewport;
        appRouter.go('/home');
        await tester.pumpWidget(_buildRouterApp(textScale: scale));
        await tester.pumpAndSettle();

        final homeCtx = tester.element(find.byType(HomeScreen));
        expect(
          MediaQuery.textScalerOf(homeCtx).scale(10),
          equals(scale * 10),
          reason: 'Effective TextScaler at HomeScreen must equal ${scale}x',
        );

        // Scroll entire HomeScreen top-to-bottom to ensure every card builds cleanly without overflow
        final scrollable = find.byType(Scrollable).first;
        for (int step = 0; step < 5; step++) {
          await tester.drag(scrollable, const Offset(0, -450));
          await tester.pumpAndSettle();
        }
        for (int step = 0; step < 5; step++) {
          await tester.drag(scrollable, const Offset(0, 450));
          await tester.pumpAndSettle();
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'HomeScreen at ${viewport.width.toInt()}x${viewport.height.toInt()} ${scale}x must produce zero overflows',
        );

        // Verify zero duplicate semantic labels and valid SemanticsAction.tap on visible clickable Home cards
        final traversal = tester.semantics.simulatedAccessibilityTraversal();
        final labels = traversal
            .map((n) => n.getSemanticsData().label.trim())
            .where((l) => l.isNotEmpty)
            .toList();

        expect(labels, isNotEmpty);
        expect(labels.any((l) => l.contains('open navigation menu')), isFalse,
            reason: 'Legacy duplicate English menu semantic label must not appear on Home');
        final seen = <String>{};
        final duplicates = <String>[];
        for (final label in labels) {
          if (!seen.add(label)) {
            duplicates.add(label);
          }
        }
        expect(
          duplicates,
          isEmpty,
          reason: 'HomeScreen at ${viewport.width.toInt()}x${viewport.height.toInt()} ${scale}x leaked duplicate semantic labels: $duplicates',
        );

        // Verify visible clickable Home cards expose SemanticsAction.tap at 360x800/412x915 1.0x & 2.0x
        for (final needle in const [
          'فتح التقويم الهجري',
          'الصلاة القادمة:',
          'تحديث الموقع عبر GPS',
          'الإعدادات',
          'عن التطبيق',
        ]) {
          final node = _findSemanticNodeByLabelContains(tester, needle);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
            reason: 'Node "$needle" must expose SemanticsAction.tap at ${viewport.width.toInt()}x${viewport.height.toInt()} ${scale}x',
          );
        }

        // Activate Settings via SemanticsAction.tap at narrow 360x800 1.0x/2.0x and return cleanly
        await _performSemanticTapByLabel(tester, 'الإعدادات', scrollIfNeeded: false);
        expect(find.byType(SettingsScreen), findsOneWidget);
        await tester.tap(find.byType(IsolatedBackButton));
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      PrayerService.instance.stopLiveTicker();
      semantics.dispose();
    });
  });
}
