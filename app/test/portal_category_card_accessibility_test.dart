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
import 'package:almomin/core/ui/portal_category_card.dart';
import 'package:almomin/features/audio/audio_screen.dart';
import 'package:almomin/features/mushaf/comparative_tafsir_screen.dart';
import 'package:almomin/features/mushaf/mushaf_screen.dart';
import 'package:almomin/features/mushaf/quran_hub_screen.dart';
import 'package:almomin/features/mushaf/screens/quran_asbab_nuzul_screen.dart';
import 'package:almomin/features/mushaf/screens/quran_irab_screen.dart';
import 'package:almomin/features/search/quran_search_screen.dart';

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

Widget _buildRouterApp({required RouterConfig<Object> router, required double textScale}) {
  return MaterialApp.router(
    theme: AppTheme.lightTheme,
    routerConfig: router,
    builder: (context, child) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      );
    },
  );
}

SemanticsNode _findSingleCardSemanticNode(WidgetTester tester, String title) {
  final matches = <SemanticsNode>[];
  for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
    final label = node.getSemanticsData().label;
    if (label.startsWith('$title،')) {
      matches.add(node);
    }
  }
  expect(
    matches.length,
    equals(1),
    reason: 'Expected exactly 1 unique semantic node starting with "$title،" (got ${matches.length})',
  );
  return matches.single;
}

Future<void> _scrollCardIntoView(WidgetTester tester, String title) async {
  final cardFinder = find.ancestor(
    of: find.text(title),
    matching: find.byType(PortalCategoryCard),
  );
  for (int i = 0; i < 8; i++) {
    if (cardFinder.evaluate().isNotEmpty) {
      await tester.ensureVisible(cardFinder.first);
      await tester.pumpAndSettle();
      return;
    }
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isEmpty) break;
    await tester.drag(scrollable.first, const Offset(0, -350));
    await tester.pumpAndSettle();
  }
  expect(cardFinder, findsOneWidget, reason: 'PortalCategoryCard "$title" must be reachable');
}

void _assertCardGeometryReadable(
  WidgetTester tester,
  String title, {
  required double scale,
}) {
  final cardFinder = find.ancestor(
    of: find.text(title),
    matching: find.byType(PortalCategoryCard),
  );
  expect(cardFinder, findsOneWidget);
  final card = tester.widget<PortalCategoryCard>(cardFinder);
  final cardRect = tester.getRect(cardFinder);
  final titleRect = tester.getRect(find.descendant(of: cardFinder, matching: find.text(card.title)));
  final subtitleRect =
      tester.getRect(find.descendant(of: cardFinder, matching: find.text(card.subtitle)));

  // Title must never be squeezed into a narrow multi-line vertical column (e.g. 28px wide / 380px+ tall at 360px 2.0x)
  expect(
    titleRect.height,
    lessThanOrEqualTo(scale >= 1.35 ? 180.0 : 64.0),
    reason: 'Card "${card.title}" title height (${titleRect.height}) indicates vertical squeezing at ${scale}x',
  );
  // If a title wraps beyond a single line, its width must span generously across the card (never squeezed by icon/badge)
  final singleLineThreshold = scale >= 1.35 ? 60.0 : 32.0;
  if (titleRect.height > singleLineThreshold) {
    expect(
      titleRect.width,
      greaterThanOrEqualTo(cardRect.width * 0.55),
      reason: 'Wrapped card "${card.title}" title width (${titleRect.width}) was squeezed inside card width ${cardRect.width} at ${scale}x',
    );
  }
  expect(
    subtitleRect.width,
    greaterThanOrEqualTo(cardRect.width * 0.45),
    reason: 'Card "${card.title}" subtitle width (${subtitleRect.width}) was squeezed inside card width ${cardRect.width} at ${scale}x',
  );
  expect(titleRect.top, greaterThanOrEqualTo(cardRect.top - 0.5));
  expect(subtitleRect.bottom, lessThanOrEqualTo(cardRect.bottom + 0.5));
  expect(titleRect.bottom, lessThanOrEqualTo(subtitleRect.top + 1.0),
      reason: 'Title and subtitle must not overlap on card "${card.title}"');

  if (card.badgeText != null && card.badgeText!.trim().isNotEmpty) {
    final badgeRect = tester.getRect(
      find.descendant(of: cardFinder, matching: find.text(card.badgeText!.trim())),
    );
    expect(badgeRect.left, greaterThanOrEqualTo(cardRect.left - 0.5));
    expect(badgeRect.right, lessThanOrEqualTo(cardRect.right + 0.5));
    expect(badgeRect.bottom, lessThanOrEqualTo(cardRect.bottom + 0.5));
  }

  // Unique semantic label (no duplicated title) and native SemanticsAction.tap
  final node = _findSingleCardSemanticNode(tester, card.title);
  final data = node.getSemanticsData();
  expect(data.hasAction(SemanticsAction.tap), isTrue,
      reason: 'Card "${card.title}" must expose SemanticsAction.tap');
  expect(
    RegExp(RegExp.escape(card.title)).allMatches(data.label).length,
    equals(1),
    reason: 'Semantic label for "${card.title}" must not duplicate the title: "${data.label}"',
  );
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

  group('Repair 4: Shared PortalCategoryCard Adaptive Layout & Semantics', () {
    testWidgets('QuranHubScreen actual appRouter renders all 6 PortalCategoryCards unclipped and unsqueezed at 360x800 and 412x915 at 1.0x and 2.0x', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const quranTitles = [
        'القرآن الكريم مكتوب',
        'القرآن الكريم مسموع',
        'البحث في القرآن',
        'التفاسير',
        'الإعراب',
        'أسباب نزول الآيات',
      ];

      const matrix = <(Size, double)>[
        (Size(360, 800), 1.0),
        (Size(360, 800), 2.0),
        (Size(412, 915), 1.0),
        (Size(412, 915), 2.0),
      ];

      for (final (viewport, scale) in matrix) {
        tester.view.physicalSize = viewport;
        appRouter.go('/mushaf');
        await tester.pumpWidget(_buildRouterApp(router: appRouter, textScale: scale));
        await tester.pumpAndSettle();

        expect(
          MediaQuery.textScalerOf(tester.element(find.byType(QuranHubScreen))).scale(10),
          equals(scale * 10),
        );

        for (final title in quranTitles) {
          await _scrollCardIntoView(tester, title);
          _assertCardGeometryReadable(tester, title, scale: scale);
        }

        expect(
          tester.takeException(),
          isNull,
          reason: 'QuranHubScreen at ${viewport.width.toInt()}x${viewport.height.toInt()} ${scale}x must have zero overflows/exceptions',
        );
      }

      PrayerService.instance.stopLiveTicker();
      semantics.dispose();
    });

    testWidgets('SemanticsAction.tap on every QuranHubScreen PortalCategoryCard opens the exact Quran route at 1.0x (real appRouter) and 2.0x (360x800 GoRouter)', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Part A: Real appRouter end-to-end semantic activation across all 6 Quran cards at 1.0x (preserving Quran search & tafsir)
      tester.view.physicalSize = const Size(800, 1400);
      appRouter.go('/mushaf');
      await tester.pumpWidget(_buildRouterApp(router: appRouter, textScale: 1.0));
      await tester.pumpAndSettle();

      final realChecks = <(String, Type)>[
        ('القرآن الكريم مكتوب', MushafScreen),
        ('القرآن الكريم مسموع', AudioScreen),
        ('البحث في القرآن', QuranSearchScreen),
        ('التفاسير', ComparativeTafsirScreen),
        ('الإعراب', QuranIrabScreen),
        ('أسباب نزول الآيات', QuranAsbabNuzulScreen),
      ];

      for (final (title, expectedScreen) in realChecks) {
        await _scrollCardIntoView(tester, title);
        final node = _findSingleCardSemanticNode(tester, title);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        tester.binding.pipelineOwner.semanticsOwner!.performAction(node.id, SemanticsAction.tap);
        await tester.pumpAndSettle();

        expect(find.byType(expectedScreen), findsOneWidget,
            reason: 'SemanticsAction.tap on "$title" must open $expectedScreen');
        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();
        expect(find.byType(QuranHubScreen), findsOneWidget);
      }
      expect(tester.takeException(), isNull);

      // Part B: Narrow 360x800 real QuranHubScreen at BOTH 1.0x and 2.0x verifying SemanticsAction.tap dispatches all 6 exact routes
      tester.view.physicalSize = const Size(360, 800);
      for (final scale in [1.0, 2.0]) {
        final routeEvents = <String>[];
        final probeRouter = GoRouter(
          initialLocation: '/mushaf',
          routes: [
            ShellRoute(
              builder: (_, __, child) => MainScaffold(child: child),
              routes: [
                GoRoute(path: '/mushaf', builder: (_, __) => const QuranHubScreen()),
              ],
            ),
            for (final path in const [
              '/mushaf-reader',
              '/audio',
              '/search',
              '/comparative-tafsir',
              '/quran-irab',
              '/quran-asbab-nuzul',
            ])
              GoRoute(
                path: path,
                builder: (_, state) {
                  routeEvents.add(state.uri.toString());
                  return Scaffold(
                    appBar: AppBar(title: Text('PROBED:$path')),
                    body: Center(child: Text(path)),
                  );
                },
              ),
          ],
        );
        addTearDown(probeRouter.dispose);

        await tester.pumpWidget(_buildRouterApp(router: probeRouter, textScale: scale));
        await tester.pumpAndSettle();

        const routeChecks = <(String, String)>[
          ('القرآن الكريم مكتوب', '/mushaf-reader'),
          ('القرآن الكريم مسموع', '/audio'),
          ('البحث في القرآن', '/search'),
          ('التفاسير', '/comparative-tafsir'),
          ('الإعراب', '/quran-irab'),
          ('أسباب نزول الآيات', '/quran-asbab-nuzul'),
        ];

        for (final (title, expectedPath) in routeChecks) {
          routeEvents.clear();
          await _scrollCardIntoView(tester, title);
          final node = _findSingleCardSemanticNode(tester, title);
          expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
          tester.binding.pipelineOwner.semanticsOwner!.performAction(node.id, SemanticsAction.tap);
          await tester.pumpAndSettle();

          expect(routeEvents, equals([expectedPath]),
              reason: 'SemanticsAction.tap on "$title" at 360x800 ${scale}x must navigate to $expectedPath');
          probeRouter.pop();
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      }

      PrayerService.instance.stopLiveTicker();
      semantics.dispose();
    });

    testWidgets('Other PortalCategoryCard hub callers (/prayer, /adhkar-hub, /library) render without regression at 360x800 at 1.0x and 2.0x', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const hubChecks = <(String, List<String>)>[
        ('/prayer', ['مواقيت الصلاة واستوديو الأذان', 'بوصلة القبلة المشرفة', 'السنن الرواتب']),
        ('/adhkar-hub', ['أذكار الصباح والمساء واليوم', 'المسبحة الإلكترونية الذكية', 'مواقيت وتنبيهات أذكار المسلم']),
        ('/library', ['رياض الصالحين وصحيح الحديث', 'قصص الأنبياء المسموعة والمقروءة', 'إذاعة القرآن والتراث الإسلامي']),
      ];

      for (final scale in [1.0, 2.0]) {
        for (final (route, sampleTitles) in hubChecks) {
          appRouter.go(route);
          await tester.pumpWidget(_buildRouterApp(router: appRouter, textScale: scale));
          await tester.pumpAndSettle();

          for (final title in sampleTitles) {
            await _scrollCardIntoView(tester, title);
            _assertCardGeometryReadable(tester, title, scale: scale);
          }

          expect(
            tester.takeException(),
            isNull,
            reason: 'Hub $route at 360x800 ${scale}x must have zero overflows/exceptions',
          );
        }
      }

      PrayerService.instance.stopLiveTicker();
      semantics.dispose();
    });
  });
}
