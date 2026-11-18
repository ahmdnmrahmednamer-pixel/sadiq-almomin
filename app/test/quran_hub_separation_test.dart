import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/router.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/app/widgets/app_navigation_drawer.dart';
import 'package:almomin/core/services/ayah_notes_service.dart';
import 'package:almomin/core/services/daily_wird_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/memorization_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/prayer_tracker_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';
import 'package:almomin/core/services/tajweed_service.dart';
import 'package:almomin/core/ui/portal_category_card.dart';
import 'package:almomin/features/khatma/khatma_screen.dart';
import 'package:almomin/features/mushaf/memorization_screen.dart';
import 'package:almomin/features/mushaf/mushaf_screen.dart';
import 'package:almomin/features/mushaf/page_mode_mushaf_screen.dart';
import 'package:almomin/features/mushaf/quran_hub_screen.dart';
import 'package:almomin/features/mushaf/quran_notes_screen.dart';
import 'package:almomin/features/search/quran_search_screen.dart';
import 'package:almomin/features/tajweed/tajweed_screen.dart';

const bool _kCapturePixels = bool.fromEnvironment(
  'CAPTURE_REPAIR10_PIXELS',
  defaultValue: false,
);
const String _kCaptureOutDir = String.fromEnvironment(
  'CAPTURE_REPAIR10_OUT_DIR',
  defaultValue: '',
);
const String _kMaterialIconsFontPath = String.fromEnvironment(
  'MATERIAL_ICONS_FONT',
  defaultValue: '',
);

const List<String> _kForbiddenLeakedHubLabels = [
  'إشراقة اليوم',
  'رحاب القرآن',
  'محراب الصلاة',
  'أُنس الذاكرين',
  'رياض العلم',
  'القائمة الإيمانية الشاملة ☰',
  'القرآن الكريم وعلومه',
];

final GlobalKey _kCaptureBoundaryKey = GlobalKey();

Future<void> _loadRealFonts() async {
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
    amiriLoader.addFont(
      Future.value(ByteData.view(amiriReg.readAsBytesSync().buffer)),
    );
  }
  final amiriBold = File('assets/fonts/Amiri-Bold.ttf');
  if (amiriBold.existsSync()) {
    amiriLoader.addFont(
      Future.value(ByteData.view(amiriBold.readAsBytesSync().buffer)),
    );
  }
  await amiriLoader.load();

  final quranFile = File('assets/fonts/AmiriQuran-Regular.ttf');
  if (quranFile.existsSync()) {
    final quranLoader = FontLoader('AmiriQuran');
    quranLoader.addFont(
      Future.value(ByteData.view(quranFile.readAsBytesSync().buffer)),
    );
    await quranLoader.load();
  }

  final candidates = <String>[
    if (_kMaterialIconsFontPath.isNotEmpty) _kMaterialIconsFontPath,
    'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
    'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ];
  for (final path in candidates) {
    final f = File(path);
    if (f.existsSync()) {
      final iconLoader = FontLoader('MaterialIcons');
      iconLoader.addFont(
        Future.value(ByteData.view(f.readAsBytesSync().buffer)),
      );
      await iconLoader.load();
      break;
    }
  }
}

Widget _buildRouterApp({
  required RouterConfig<Object> router,
  required double textScale,
}) {
  return RepaintBoundary(
    key: _kCaptureBoundaryKey,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        );
      },
    ),
  );
}

Future<void> _capturePng(WidgetTester tester, String fileName) async {
  if (!_kCapturePixels || _kCaptureOutDir.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        _kCaptureBoundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = Directory(_kCaptureOutDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    File('${dir.path}/$fileName').writeAsBytesSync(
      byteData!.buffer.asUint8List(),
    );
  });
}

Future<Finder> _scrollCardFullyIntoViewport(
  WidgetTester tester,
  String title, {
  bool expectBottomNav = true,
}) async {
  final cardFinder = find.ancestor(
    of: find.text(title),
    matching: find.byType(PortalCategoryCard),
  );
  final scrollableFinder = find.descendant(
    of: find.byType(QuranHubScreen),
    matching: find.byType(Scrollable),
  );

  // Reset to top first so repeated lookups work regardless of prior scroll offset
  if (scrollableFinder.evaluate().isNotEmpty) {
    final pos = tester.state<ScrollableState>(scrollableFinder.first).position;
    if (pos.pixels != 0) {
      pos.jumpTo(0);
      await tester.pumpAndSettle();
    }
  }

  for (int i = 0; i < 14; i++) {
    if (cardFinder.evaluate().isNotEmpty) {
      await tester.ensureVisible(cardFinder.first);
      await tester.pumpAndSettle();
      break;
    }
    if (scrollableFinder.evaluate().isEmpty) break;
    await tester.drag(scrollableFinder.first, const Offset(0, -280));
    await tester.pumpAndSettle();
  }

  expect(
    cardFinder,
    findsOneWidget,
    reason: 'PortalCategoryCard "$title" must be built and reachable',
  );

  final cardRect = tester.getRect(cardFinder);
  final appBarRect = tester.getRect(
    find.descendant(of: find.byType(QuranHubScreen), matching: find.byType(AppBar)),
  );
  final viewportBottom = expectBottomNav && find.byType(NavigationBar).evaluate().isNotEmpty
      ? tester.getRect(find.byType(NavigationBar)).top
      : tester.view.physicalSize.height / tester.view.devicePixelRatio;

  // Nudge slightly if card straddles top/bottom edge after ensureVisible
  if (cardRect.top < appBarRect.bottom - 1.0 && scrollableFinder.evaluate().isNotEmpty) {
    final pos = tester.state<ScrollableState>(scrollableFinder.first).position;
    final target = (pos.pixels - (appBarRect.bottom - cardRect.top + 16))
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    pos.jumpTo(target);
    await tester.pumpAndSettle();
  } else if (cardRect.bottom > viewportBottom + 1.0 && scrollableFinder.evaluate().isNotEmpty) {
    final pos = tester.state<ScrollableState>(scrollableFinder.first).position;
    final target = (pos.pixels + (cardRect.bottom - viewportBottom + 16))
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    pos.jumpTo(target);
    await tester.pumpAndSettle();
  }

  final finalRect = tester.getRect(cardFinder);
  expect(
    finalRect.top,
    greaterThanOrEqualTo(appBarRect.bottom - 1.0),
    reason: 'Card "$title" top (${finalRect.top}) must be below AppBar (${appBarRect.bottom})',
  );
  expect(
    finalRect.bottom,
    lessThanOrEqualTo(viewportBottom + 1.0),
    reason: 'Card "$title" bottom (${finalRect.bottom}) must be inside visible viewport ($viewportBottom)',
  );
  expect(finalRect.left, greaterThanOrEqualTo(-0.5));
  expect(
    finalRect.right,
    lessThanOrEqualTo((tester.view.physicalSize.width / tester.view.devicePixelRatio) + 0.5),
  );
  return cardFinder;
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
    reason: 'Expected exactly 1 semantic node starting with "$title،" (found ${matches.length})',
  );
  return matches.single;
}

void _assertDestinationIsolated(
  WidgetTester tester,
  Type expectedScreen,
  String contextLabel,
) {
  expect(
    find.byType(expectedScreen),
    findsOneWidget,
    reason: '$contextLabel must navigate to actual $expectedScreen',
  );
  expect(
    find.byType(IsolatedFeatureRouteHost),
    findsOneWidget,
    reason: '$contextLabel must be hosted inside IsolatedFeatureRouteHost',
  );
  expect(
    find.byType(NavigationBar),
    findsNothing,
    reason: '$contextLabel must isolate away from hub NavigationBar',
  );
  expect(
    find.byType(AppNavigationDrawer),
    findsNothing,
    reason: '$contextLabel must not show AppNavigationDrawer',
  );
  expect(
    find.byKey(const ValueKey('isolated_direct_back_home_button')),
    findsNothing,
    reason: 'Pushed $contextLabel must not duplicate direct-back banner',
  );

  final traversalLabels = tester.semantics
      .simulatedAccessibilityTraversal()
      .map((n) => n.getSemanticsData().label)
      .where((l) => l.isNotEmpty)
      .toList();
  expect(traversalLabels, isNotEmpty);
  for (final forbidden in _kForbiddenLeakedHubLabels) {
    expect(
      traversalLabels.any((l) => l.contains(forbidden)),
      isFalse,
      reason: '$contextLabel leaked hub/drawer label "$forbidden" into active semantics',
    );
  }

  expect(
    find.byType(BackButton),
    findsOneWidget,
    reason: '$contextLabel must expose a single AppBar BackButton',
  );
}

void _assertHubAppBarTitleUnclipped(WidgetTester tester, String tag) {
  final appBarFinder = find.descendant(
    of: find.byType(QuranHubScreen),
    matching: find.byType(AppBar),
  );
  expect(appBarFinder, findsOneWidget);

  final titleFinder = find.descendant(
    of: appBarFinder,
    matching: find.text('القرآن الكريم'),
  );
  expect(
    titleFinder,
    findsOneWidget,
    reason: 'QuranHubScreen AppBar must display short visible title "القرآن الكريم" at $tag',
  );

  final paragraph = tester.renderObject<RenderParagraph>(titleFinder);
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: 'AppBar title "القرآن الكريم" must not ellipsize or exceed maxLines at $tag',
  );

  final titleElement = tester.element(titleFinder);
  final titleWidget = tester.widget<Text>(titleFinder);
  final resolvedStyle = DefaultTextStyle.of(titleElement).style.merge(titleWidget.style);
  final painter = TextPainter(
    text: TextSpan(text: 'القرآن الكريم', style: resolvedStyle),
    textDirection: Directionality.of(titleElement),
    textScaler: MediaQuery.textScalerOf(titleElement),
    maxLines: 1,
  )..layout();
  final titleRect = tester.getRect(titleFinder);
  final appBarRect = tester.getRect(appBarFinder);

  expect(
    painter.width,
    lessThanOrEqualTo(titleRect.width + 1.0),
    reason: 'AppBar title intrinsic width (${painter.width}) exceeded rendered width (${titleRect.width}) at $tag (clipped/ellipsized)',
  );
  expect(
    painter.height,
    lessThanOrEqualTo(titleRect.height + 1.0),
    reason: 'AppBar title intrinsic height (${painter.height}) exceeded rendered height (${titleRect.height}) at $tag',
  );
  painter.dispose();

  expect(titleRect.top, greaterThanOrEqualTo(appBarRect.top - 0.5));
  expect(titleRect.bottom, lessThanOrEqualTo(appBarRect.bottom + 0.5));
  expect(titleRect.left, greaterThanOrEqualTo(appBarRect.left - 0.5));
  expect(titleRect.right, lessThanOrEqualTo(appBarRect.right + 0.5));

  // Verify leading menu and trailing search buttons do not overlap title
  final menuRect = tester.getRect(
    find.descendant(of: appBarFinder, matching: find.byIcon(Icons.menu_rounded)),
  );
  final searchRect = tester.getRect(
    find.descendant(of: appBarFinder, matching: find.byIcon(Icons.search_rounded)),
  );
  expect(
    titleRect.overlaps(menuRect),
    isFalse,
    reason: 'AppBar title overlaps leading drawer button at $tag',
  );
  expect(
    titleRect.overlaps(searchRect),
    isFalse,
    reason: 'AppBar title overlaps trailing search button at $tag',
  );

  // Meaningful accessible label preserved as semantic header
  final semanticsNodes = tester.semantics.simulatedAccessibilityTraversal();
  final hasAccessibleHeader = semanticsNodes.any((node) {
    final data = node.getSemanticsData();
    return data.label == 'القرآن الكريم وعلومه' &&
        data.flagsCollection.isHeader;
  });
  expect(
    hasAccessibleHeader,
    isTrue,
    reason: 'QuranHubScreen AppBar must preserve accessible header label "القرآن الكريم وعلومه" at $tag',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadRealFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'has_completed_onboarding': true,
      'show_tutorial_screens': false,
      'last_read_page_number': 42,
      'last_read_surah_name': 'البقرة',
      'bookmarks': <String>['1:1'],
    });
    await SettingsService.instance.init();
    await PrayerTrackerService.instance.init(forceReload: true);
    await SunanRawatibService.instance.init(forceReload: true);
    await DailyWirdService.instance.init(forceReload: true);
    await MemorizationService.instance.init();
    await MemorizationService.instance.clearAll();
    await TajweedService.instance.init();
    await AyahNotesService.instance.init();
    IslamicAudioService.instance.disableNativePlayerForTesting = true;
    await IslamicAudioService.instance.stop();
  });

  tearDown(() async {
    PrayerService.instance.stopLiveTicker();
    await IslamicAudioService.instance.stop();
    appRouter.go('/momen-duaa');
  });

  group('Repair 10: Quran Hub Separation & Copy Discipline', () {
    testWidgets(
      'QuranHubScreen exposes exact 9 independent cards with audio title التلاوات, no Uthmani claim, no count marketing, and all 3 new cards reachable inside viewport at 360x800 (1.0x and 2.0x)',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const expectedTitles = <String>[
          'القرآن المكتوب',
          'التلاوات',
          'المحفّظ',
          'التجويد',
          'خواطري',
          'البحث القرآني',
          'التفاسير',
          'الإعراب',
          'أسباب النزول',
        ];
        const forbiddenCopySnippets = <String>[
          'العثماني',
          '٦٠٤',
          '604',
          '٦١ قارئ',
          '٦٠ قارئ',
          '٩ تفاسير',
          'كبار القراء',
          'محرك بحث فوري متقدم',
        ];

        for (final scale in [1.0, 2.0]) {
          appRouter.go('/mushaf');
          await tester.pumpWidget(_buildRouterApp(router: appRouter, textScale: scale));
          await tester.pumpAndSettle();

          expect(
            MediaQuery.textScalerOf(tester.element(find.byType(QuranHubScreen))).scale(10),
            equals(scale * 10),
            reason: 'No hidden TextScaler cap on QuranHubScreen at ${scale}x',
          );

          final seenCards = <String, PortalCategoryCard>{};
          for (final title in expectedTitles) {
            final cardFinder = await _scrollCardFullyIntoViewport(tester, title);
            final card = tester.widget<PortalCategoryCard>(cardFinder);
            seenCards[card.title] = card;

            expect(
              card.badgeText,
              isNull,
              reason: 'Card "${card.title}" must not display marketing count badgeText',
            );
            for (final forbidden in forbiddenCopySnippets) {
              expect(
                card.title.contains(forbidden) || card.subtitle.contains(forbidden),
                isFalse,
                reason: 'Card "${card.title}" contains forbidden claim/marketing "$forbidden"',
              );
            }
          }

          expect(seenCards.length, equals(9));
          expect(seenCards.containsKey('التلاوات'), isTrue);
          expect(seenCards.containsKey('المحفّظ'), isTrue);
          expect(seenCards.containsKey('التجويد'), isTrue);
          expect(seenCards.containsKey('خواطري'), isTrue);
          expect(tester.takeException(), isNull);
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        semantics.dispose();
      },
    );

    testWidgets(
      'Actual appRouter destination isolation and Back return for all 3 new independent entries (/memorization, /tajweed, /notes) via BOTH tap and SemanticsAction.tap',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        appRouter.go('/mushaf');
        await tester.pumpWidget(_buildRouterApp(router: appRouter, textScale: 1.0));
        await tester.pumpAndSettle();

        const newEntries = <(String, Type)>[
          ('المحفّظ', MemorizationScreen),
          ('التجويد', TajweedScreen),
          ('خواطري', QuranNotesScreen),
        ];

        for (final (title, destinationType) in newEntries) {
          // 1. Real pointer tap activation after confirming full viewport containment
          final cardFinder = await _scrollCardFullyIntoViewport(tester, title);
          await tester.tap(cardFinder);
          await tester.pumpAndSettle();

          _assertDestinationIsolated(
            tester,
            destinationType,
            'Real appRouter tap "$title"',
          );

          await tester.tap(find.byType(BackButton).first);
          await tester.pumpAndSettle();
          expect(find.byType(QuranHubScreen), findsOneWidget);
          expect(find.byType(NavigationBar), findsOneWidget);

          // 2. Native SemanticsAction.tap activation after confirming full viewport containment
          await _scrollCardFullyIntoViewport(tester, title);
          final node = _findSingleCardSemanticNode(tester, title);
          expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
          tester.binding.pipelineOwner.semanticsOwner!
              .performAction(node.id, SemanticsAction.tap);
          await tester.pumpAndSettle();

          _assertDestinationIsolated(
            tester,
            destinationType,
            'Real appRouter SemanticsAction.tap "$title"',
          );

          await tester.tap(find.byType(BackButton).first);
          await tester.pumpAndSettle();
          expect(find.byType(QuranHubScreen), findsOneWidget);
          expect(find.byType(NavigationBar), findsOneWidget);
        }

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        semantics.dispose();
      },
    );

    testWidgets(
      'Dispatch-only probeRouter: remaining 6 QuranHubScreen entries dispatch exact routes via BOTH tap and SemanticsAction.tap at 360x800 (1.0x and 2.0x)',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const remainingRouteChecks = <(String, String)>[
          ('القرآن المكتوب', '/mushaf-reader'),
          ('التلاوات', '/audio'),
          ('البحث القرآني', '/search'),
          ('التفاسير', '/comparative-tafsir'),
          ('الإعراب', '/quran-irab'),
          ('أسباب النزول', '/quran-asbab-nuzul'),
        ];

        for (final scale in [1.0, 2.0]) {
          final dispatched = <String>[];
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
                '/memorization',
                '/tajweed',
                '/notes',
                '/search',
                '/comparative-tafsir',
                '/quran-irab',
                '/quran-asbab-nuzul',
              ])
                GoRoute(
                  path: path,
                  builder: (_, state) {
                    dispatched.add(state.uri.toString());
                    return Scaffold(
                      appBar: AppBar(title: Text('DISPATCH_PROBE:$path')),
                      body: Center(child: Text(path)),
                    );
                  },
                ),
            ],
          );
          addTearDown(probeRouter.dispose);

          await tester.pumpWidget(_buildRouterApp(router: probeRouter, textScale: scale));
          await tester.pumpAndSettle();

          for (final (title, expectedPath) in remainingRouteChecks) {
            // Pointer tap dispatch
            dispatched.clear();
            final cardFinder = await _scrollCardFullyIntoViewport(tester, title);
            await tester.tap(cardFinder);
            await tester.pumpAndSettle();
            expect(dispatched, equals([expectedPath]),
                reason: 'Dispatch-only tap on "$title" (${scale}x) -> $expectedPath');
            probeRouter.pop();
            await tester.pumpAndSettle();

            // SemanticsAction.tap dispatch
            dispatched.clear();
            await _scrollCardFullyIntoViewport(tester, title);
            final node = _findSingleCardSemanticNode(tester, title);
            expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
            tester.binding.pipelineOwner.semanticsOwner!
                .performAction(node.id, SemanticsAction.tap);
            await tester.pumpAndSettle();
            expect(dispatched, equals([expectedPath]),
                reason: 'Dispatch-only SemanticsAction.tap on "$title" (${scale}x) -> $expectedPath');
            probeRouter.pop();
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        semantics.dispose();
      },
    );

    testWidgets(
      'MushafScreen removes ONLY the 3 nested global shortcuts and duplicate Tajweed AppBar action while preserving 4 tabs, local Surah search, continue reading, 604 pages, Khatma, and Quran search',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        appRouter.go('/mushaf');
        await tester.pumpWidget(_buildRouterApp(router: appRouter, textScale: 1.0));
        await tester.pumpAndSettle();

        appRouter.push('/mushaf-reader');
        await tester.pumpAndSettle();

        expect(find.byType(MushafScreen), findsOneWidget);

        // 1. Removed 3 nested global shortcuts + duplicate Tajweed AppBar button
        expect(find.text('المحفّظ والتكرار'), findsNothing);
        expect(find.text('خواطري وملاحظاتي'), findsNothing);
        expect(find.text('أحكام التجويد'), findsNothing);
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byIcon(Icons.palette_outlined),
          ),
          findsNothing,
        );

        // 2. Preserved quick chips: Khatma + Quran Search
        expect(find.text('مخطط الختمات'), findsOneWidget);
        expect(find.text('البحث القرآني'), findsOneWidget);

        // 3. Preserved continue-reading 604-page banner with persisted prefs
        expect(find.textContaining('متابعة من صفحة 42 (سورة البقرة)'), findsOneWidget);
        await tester.tap(find.textContaining('متابعة من صفحة 42'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(PageModeMushafScreen), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(MushafScreen), findsOneWidget);

        // 4. Preserved Tab 1: Surahs (114) + local Surah search
        expect(find.text('السور (١١٤)'), findsOneWidget);
        final surahSearchField = find.byType(TextField).first;
        await tester.enterText(surahSearchField, 'البقرة');
        await tester.pumpAndSettle();
        expect(find.text('سورة البقرة'), findsOneWidget);
        await tester.enterText(surahSearchField, '');
        await tester.pumpAndSettle();

        // 5. Preserved Tab 2: Juz (30)
        await tester.tap(find.text('الأجزاء (٣٠)'));
        await tester.pumpAndSettle();
        expect(find.textContaining('الجزء 1'), findsOneWidget);

        // 6. Preserved Tab 3: Pages (604) -> opens PageModeMushafScreen
        await tester.tap(find.text('صفحات المصحف (٦٠٤)'));
        await tester.pumpAndSettle();
        expect(find.textContaining('صفحة ١ —'), findsOneWidget);
        await tester.tap(find.textContaining('صفحة ١ —').first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(PageModeMushafScreen), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(MushafScreen), findsOneWidget);

        // 7. Preserved Tab 4: Saved Bookmarks (persisted 1:1 intact)
        await tester.ensureVisible(find.text('العلامات المرجعية'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('العلامات المرجعية'));
        await tester.pumpAndSettle();
        expect(find.textContaining('سورة الفاتحة'), findsOneWidget);

        // 8. Preserved Khatma quick chip -> KhatmaScreen + Back
        await tester.tap(find.text('مخطط الختمات'));
        await tester.pumpAndSettle();
        expect(find.byType(KhatmaScreen), findsOneWidget);
        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();
        expect(find.byType(MushafScreen), findsOneWidget);

        // 9. Preserved Quran Search quick chip -> QuranSearchScreen + Back
        await tester.tap(find.text('البحث القرآني'));
        await tester.pumpAndSettle();
        expect(find.byType(QuranSearchScreen), findsOneWidget);
        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();
        expect(find.byType(MushafScreen), findsOneWidget);

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'Real-font pixels and unclipped layout for QuranHubScreen (top/middle/bottom) and MushafScreen at 360x800 and 412x915 at 1.0x and 2.0x',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const matrix = <(Size, double, String)>[
          (Size(360, 800), 1.0, '360x800_1x'),
          (Size(360, 800), 2.0, '360x800_2x'),
          (Size(412, 915), 1.0, '412x915_1x'),
          (Size(412, 915), 2.0, '412x915_2x'),
        ];

        for (final (size, scale, tag) in matrix) {
          tester.view.physicalSize = size;

          // A. QuranHubScreen top / middle / bottom
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          appRouter.go('/mushaf');
          await tester.pumpWidget(_buildRouterApp(router: appRouter, textScale: scale));
          await tester.pumpAndSettle();

          expect(
            MediaQuery.textScalerOf(tester.element(find.byType(QuranHubScreen))).scale(10),
            equals(scale * 10),
          );
          _assertHubAppBarTitleUnclipped(tester, tag);

          final hubScrollable = find.descendant(
            of: find.byType(QuranHubScreen),
            matching: find.byType(Scrollable),
          );
          final pos = tester.state<ScrollableState>(hubScrollable.first).position;

          // Top (strictly offset 0)
          pos.jumpTo(0);
          await tester.pumpAndSettle();
          expect(pos.pixels, equals(0.0));
          await _capturePng(tester, 'repair10_quranhub_top_$tag.png');

          // Middle (showing التلاوات / المحفّظ / التجويد / خواطري)
          pos.jumpTo((pos.maxScrollExtent * 0.45).clamp(pos.minScrollExtent, pos.maxScrollExtent));
          await tester.pumpAndSettle();
          await _capturePng(tester, 'repair10_quranhub_mid_$tag.png');

          // Bottom
          pos.jumpTo(pos.maxScrollExtent);
          await tester.pumpAndSettle();
          await _capturePng(tester, 'repair10_quranhub_bottom_$tag.png');

          expect(
            tester.takeException(),
            isNull,
            reason: 'QuranHubScreen must have zero exceptions/overflows at $tag',
          );

          // B. MushafScreen (pushed from hub so BackButton renders realistically)
          appRouter.push('/mushaf-reader');
          await tester.pumpAndSettle();

          expect(find.byType(MushafScreen), findsOneWidget);
          expect(
            MediaQuery.textScalerOf(tester.element(find.byType(MushafScreen))).scale(10),
            equals(scale * 10),
          );
          expect(find.text('مخطط الختمات'), findsOneWidget);
          expect(find.text('البحث القرآني'), findsOneWidget);
          expect(find.text('المحفّظ والتكرار'), findsNothing);
          expect(find.text('خواطري وملاحظاتي'), findsNothing);
          expect(find.text('أحكام التجويد'), findsNothing);

          // Verify zero vertical clipping on remaining quick chips at both 1.0x and 2.0x
          for (final chipLabel in const ['مخطط الختمات', 'البحث القرآني']) {
            final labelFinder = find.text(chipLabel);
            final chipFinder = find.ancestor(of: labelFinder, matching: find.byType(InkWell)).first;
            final chipRect = tester.getRect(chipFinder);
            final labelRect = tester.getRect(labelFinder);
            expect(
              labelRect.top,
              greaterThanOrEqualTo(chipRect.top - 0.5),
              reason: 'Quick chip "$chipLabel" top clipped at $tag',
            );
            expect(
              labelRect.bottom,
              lessThanOrEqualTo(chipRect.bottom + 0.5),
              reason: 'Quick chip "$chipLabel" bottom clipped at $tag',
            );
          }

          await _capturePng(tester, 'repair10_mushaf_$tag.png');

          expect(
            tester.takeException(),
            isNull,
            reason: 'MushafScreen must have zero exceptions/overflows at $tag',
          );

          await tester.tap(find.byType(BackButton).first);
          await tester.pumpAndSettle();
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        semantics.dispose();
      },
    );
  });
}
