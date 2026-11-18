import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/router.dart';
import 'package:almomin/app/theme/app_colors.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/core/services/daily_wird_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/prayer_tracker_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';
import 'package:almomin/core/services/voice_search_service.dart';
import 'package:almomin/features/khatma/khatma_screen.dart';
import 'package:almomin/features/mushaf/mushaf_screen.dart';
import 'package:almomin/features/mushaf/page_mode_mushaf_screen.dart';
import 'package:almomin/features/mushaf/quran_hub_screen.dart';
import 'package:almomin/features/search/quran_search_screen.dart';
import 'package:almomin/features/search/widgets/quran_voice_search_sheet.dart';

const bool _kCapturePixels = bool.fromEnvironment(
  'CAPTURE_REPAIR11_PIXELS',
  defaultValue: false,
);
const String _kCaptureOutDir = String.fromEnvironment(
  'CAPTURE_REPAIR11_OUT_DIR',
  defaultValue: '',
);
const String _kMaterialIconsFontPath = String.fromEnvironment(
  'MATERIAL_ICONS_FONT',
  defaultValue: '',
);

final GlobalKey _kCaptureBoundaryKey = GlobalKey();

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

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
  required double textScale,
  ThemeData? theme,
}) {
  return RepaintBoundary(
    key: _kCaptureBoundaryKey,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: theme ?? AppTheme.lightTheme,
      routerConfig: appRouter,
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

void _assertMushafHeaderUnclippedAndHighContrast(
  WidgetTester tester,
  String tag, {
  required ThemeData theme,
}) {
  final appBarFinder = find.descendant(
    of: find.byType(MushafScreen),
    matching: find.byType(AppBar),
  );
  expect(appBarFinder, findsOneWidget);

  final titleFinder = find.descendant(
    of: appBarFinder,
    matching: find.text('المصحف الشريف'),
  );
  expect(
    titleFinder,
    findsOneWidget,
    reason: 'MushafScreen AppBar must display "المصحف الشريف" at $tag',
  );

  // Zero ellipsis / zero clipping
  final paragraph = tester.renderObject<RenderParagraph>(titleFinder);
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: 'MushafScreen title "المصحف الشريف" must not ellipsize at $tag',
  );

  final titleElement = tester.element(titleFinder);
  final titleWidget = tester.widget<Text>(titleFinder);
  final resolvedStyle =
      DefaultTextStyle.of(titleElement).style.merge(titleWidget.style);
  final painter = TextPainter(
    text: TextSpan(text: 'المصحف الشريف', style: resolvedStyle),
    textDirection: Directionality.of(titleElement),
    textScaler: MediaQuery.textScalerOf(titleElement),
    maxLines: 1,
  )..layout();

  final titleRect = tester.getRect(titleFinder);
  final appBarRect = tester.getRect(appBarFinder);

  expect(
    painter.width,
    lessThanOrEqualTo(titleRect.width + 1.0),
    reason:
        'Title intrinsic width (${painter.width}) exceeded rendered width (${titleRect.width}) at $tag',
  );
  expect(
    painter.height,
    lessThanOrEqualTo(titleRect.height + 1.0),
    reason:
        'Title intrinsic height (${painter.height}) exceeded rendered height (${titleRect.height}) at $tag',
  );
  painter.dispose();

  expect(titleRect.top, greaterThanOrEqualTo(appBarRect.top - 0.5));
  expect(titleRect.left, greaterThanOrEqualTo(appBarRect.left - 0.5));
  expect(titleRect.right, lessThanOrEqualTo(appBarRect.right + 0.5));

  // No overlap with BackButton or trailing action buttons
  final backFinder = find.descendant(
    of: appBarFinder,
    matching: find.byType(BackButton),
  );
  if (backFinder.evaluate().isNotEmpty) {
    expect(
      titleRect.overlaps(tester.getRect(backFinder.first)),
      isFalse,
      reason: 'Title must not overlap BackButton at $tag',
    );
  }
  final overflowFinder = find.byKey(const ValueKey('mushaf_header_overflow_menu'));
  if (overflowFinder.evaluate().isNotEmpty) {
    expect(
      titleRect.overlaps(tester.getRect(overflowFinder)),
      isFalse,
      reason: 'Title must not overlap overflow action menu button at $tag',
    );
  }

  // Accessible header semantics
  final hasHeaderSemantics = tester.semantics
      .simulatedAccessibilityTraversal()
      .any((n) {
    final d = n.getSemanticsData();
    return d.label == 'المصحف الشريف' && d.flagsCollection.isHeader;
  });
  expect(
    hasHeaderSemantics,
    isTrue,
    reason: 'MushafScreen title must expose accessible header semantics at $tag',
  );

  // TabBar contrast (WCAG AA >= 4.5:1 on both selected and unselected labels)
  final tabBarFinder = find.descendant(
    of: appBarFinder,
    matching: find.byType(TabBar),
  );
  expect(tabBarFinder, findsOneWidget);
  final tabBar = tester.widget<TabBar>(tabBarFinder);
  final bgColor = theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface;
  final selectedColor = tabBar.labelColor!;
  final unselectedColor = tabBar.unselectedLabelColor!;

  final selectedContrast = _contrastRatio(selectedColor, bgColor);
  final unselectedContrast = _contrastRatio(unselectedColor, bgColor);

  expect(
    selectedContrast,
    greaterThanOrEqualTo(4.5),
    reason:
        'Selected TabBar label contrast ($selectedContrast) vs AppBar bg must meet WCAG AA >= 4.5 at $tag',
  );
  expect(
    unselectedContrast,
    greaterThanOrEqualTo(4.5),
    reason:
        'Unselected TabBar label contrast ($unselectedContrast) vs AppBar bg must meet WCAG AA >= 4.5 at $tag',
  );

  // Verify TabBar label text is not vertically clipped
  final tabBarRect = tester.getRect(tabBarFinder);
  final firstTabTextRect = tester.getRect(find.text('السور (١١٤)'));
  expect(
    firstTabTextRect.top,
    greaterThanOrEqualTo(tabBarRect.top - 0.5),
    reason: 'TabBar label top clipped at $tag',
  );
  expect(
    firstTabTextRect.bottom,
    lessThanOrEqualTo(tabBarRect.bottom + 0.5),
    reason: 'TabBar label bottom clipped at $tag',
  );
}

SemanticsNode _findSemanticNodeByLabel(WidgetTester tester, String target) {
  final matches = <SemanticsNode>[];
  for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
    final data = node.getSemanticsData();
    if (data.label == target || data.tooltip == target || data.label.contains(target)) {
      if (data.hasAction(SemanticsAction.tap)) {
        matches.add(node);
      }
    }
  }
  expect(
    matches,
    isNotEmpty,
    reason: 'Expected tappable semantic node matching "$target"',
  );
  return matches.first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadRealFonts();
  });

  setUp(() async {
    VoiceSearchService.resetTestMode();
    VoiceSearchService.isTestMode = true;
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
    IslamicAudioService.instance.disableNativePlayerForTesting = true;
    await IslamicAudioService.instance.stop();
  });

  tearDown(() async {
    VoiceSearchService.resetTestMode();
    PrayerService.instance.stopLiveTicker();
    await IslamicAudioService.instance.stop();
    appRouter.go('/momen-duaa');
  });

  group('Repair 11: Mushaf Header Geometry, TabBar Contrast & Preserved Actions', () {
    testWidgets(
      'MushafScreen AppBar title renders unclipped without ellipsis and TabBar meets WCAG AA contrast (>= 4.5:1) across 360x800, 412x915 (1.0x/2.0x), wide 700x900, and all 4 AppThemeModes',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // 1. Phone matrix at 1.0x and 2.0x on light theme
        const matrix = <(Size, double, String)>[
          (Size(360, 800), 1.0, '360x800_1x'),
          (Size(360, 800), 2.0, '360x800_2x'),
          (Size(412, 915), 1.0, '412x915_1x'),
          (Size(412, 915), 2.0, '412x915_2x'),
          (Size(700, 900), 1.0, '700x900_1x_wide'),
        ];

        for (final (size, scale, tag) in matrix) {
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          appRouter.go('/mushaf');
          await tester.pumpWidget(_buildRouterApp(textScale: scale));
          await tester.pumpAndSettle();

          appRouter.push('/mushaf-reader');
          await tester.pumpAndSettle();

          expect(
            MediaQuery.textScalerOf(tester.element(find.byType(MushafScreen))).scale(10),
            equals(scale * 10),
            reason: 'No hidden TextScaler cap on MushafScreen at $tag',
          );

          _assertMushafHeaderUnclippedAndHighContrast(
            tester,
            tag,
            theme: AppTheme.lightTheme,
          );

          if (size.width >= 600) {
            // Wide mode keeps all 5 direct IconButtons with original tooltips
            expect(find.byTooltip('فتح المصحف بالصفحات الكاملة (604)'), findsOneWidget);
            expect(find.byTooltip('مخطط الختمات والورد القرآني'), findsOneWidget);
            expect(find.byTooltip('البحث الصوتي عن الآيات'), findsOneWidget);
            expect(find.byTooltip('بوابة علوم القرآن والتفاسير'), findsOneWidget);
            expect(find.byTooltip('البحث القرآني السريع'), findsOneWidget);
          } else {
            expect(find.byKey(const ValueKey('mushaf_header_overflow_menu')), findsOneWidget);
          }

          expect(tester.takeException(), isNull, reason: 'Zero exceptions at $tag');
        }

        // 2. All 4 canonical theme modes (light, sepia, dark, black) pass WCAG AA >= 4.5:1
        tester.view.physicalSize = const Size(360, 800);
        for (final mode in AppThemeMode.values) {
          final theme = AppTheme.of(mode);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          appRouter.go('/mushaf');
          await tester.pumpWidget(_buildRouterApp(textScale: 1.0, theme: theme));
          await tester.pumpAndSettle();

          appRouter.push('/mushaf-reader');
          await tester.pumpAndSettle();

          _assertMushafHeaderUnclippedAndHighContrast(
            tester,
            'theme_${mode.name}',
            theme: theme,
          );
          expect(tester.takeException(), isNull);
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        semantics.dispose();
      },
    );

    testWidgets(
      'All 5 preserved Mushaf header actions work via BOTH pointer tap and SemanticsAction.tap at 360x800 (1.0x full destination push/back + 2.0x menu/semantics/hub/tabs zero-exception verification)',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Part A: 360x800 @ 1.0x — All 5 header actions push real destination screens + Back with zero exceptions
        appRouter.go('/mushaf');
        await tester.pumpWidget(_buildRouterApp(textScale: 1.0));
        await tester.pumpAndSettle();

        appRouter.push('/mushaf-reader');
        await tester.pumpAndSettle();

        expect(find.byType(MushafScreen), findsOneWidget);
        expect(find.textContaining('متابعة من صفحة 42 (سورة البقرة)'), findsOneWidget);

        Future<void> openOverflow({required bool viaSemantics}) async {
          if (viaSemantics) {
            final node = _findSemanticNodeByLabel(tester, 'خيارات المصحف');
            tester.binding.pipelineOwner.semanticsOwner!
                .performAction(node.id, SemanticsAction.tap);
          } else {
            await tester.tap(find.byKey(const ValueKey('mushaf_header_overflow_menu')));
          }
          await tester.pumpAndSettle();
        }

        // Action 1: 604-page reader (via pointer tap on overflow)
        await openOverflow(viaSemantics: false);
        expect(find.text('فتح المصحف بالصفحات الكاملة (604)'), findsOneWidget);
        await tester.tap(find.text('فتح المصحف بالصفحات الكاملة (604)'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(PageModeMushafScreen), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(MushafScreen), findsOneWidget);

        // Action 2: Khatma (via SemanticsAction.tap on overflow + SemanticsAction.tap on item)
        await openOverflow(viaSemantics: true);
        final khatmaItem = _findSemanticNodeByLabel(tester, 'مخطط الختمات والورد القرآني');
        tester.binding.pipelineOwner.semanticsOwner!
            .performAction(khatmaItem.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(find.byType(KhatmaScreen), findsOneWidget);
        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();
        expect(find.byType(MushafScreen), findsOneWidget);

        // Action 3: Voice Search sheet (via overflow)
        await openOverflow(viaSemantics: false);
        await tester.tap(find.text('البحث الصوتي عن الآيات'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(QuranVoiceSearchSheet), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(MushafScreen), findsOneWidget);

        // Action 4: Quran Hub (via overflow)
        await openOverflow(viaSemantics: true);
        await tester.tap(find.text('بوابة علوم القرآن والتفاسير'));
        await tester.pumpAndSettle();
        expect(find.byType(QuranHubScreen), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(MushafScreen), findsOneWidget);

        // Action 5: Quick Search (direct AppBar button at 1.0x via SemanticsAction.tap)
        final searchNode = _findSemanticNodeByLabel(tester, 'البحث القرآني السريع');
        tester.binding.pipelineOwner.semanticsOwner!
            .performAction(searchNode.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(find.byType(QuranSearchScreen), findsOneWidget);
        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();
        expect(find.byType(MushafScreen), findsOneWidget);

        // All 4 tabs switch cleanly via SemanticsAction.tap at 1.0x
        for (final tabLabel in const [
          'الأجزاء (٣٠)',
          'صفحات المصحف (٦٠٤)',
          'العلامات المرجعية',
          'السور (١١٤)',
        ]) {
          await tester.ensureVisible(find.text(tabLabel));
          await tester.pumpAndSettle();
          final tabNode = _findSemanticNodeByLabel(tester, tabLabel);
          tester.binding.pipelineOwner.semanticsOwner!
              .performAction(tabNode.id, SemanticsAction.tap);
          await tester.pumpAndSettle();
        }
        expect(find.text('سورة الفاتحة'), findsOneWidget);

        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();
        expect(find.byType(QuranHubScreen), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'Zero exceptions at 1.0x');

        // Part B: 360x800 @ 2.0x — Overflow menu contains all 5 tappable semantic items unclipped,
        // activates QuranHubScreen + Back cleanly, switches all 4 tabs via SemanticsAction.tap, zero exceptions
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        appRouter.go('/mushaf');
        await tester.pumpWidget(_buildRouterApp(textScale: 2.0));
        await tester.pumpAndSettle();

        appRouter.push('/mushaf-reader');
        await tester.pumpAndSettle();

        expect(find.byType(MushafScreen), findsOneWidget);
        expect(find.textContaining('متابعة من صفحة 42 (سورة البقرة)'), findsOneWidget);

        await openOverflow(viaSemantics: true);
        for (final expectedLabel in const [
          'البحث القرآني السريع',
          'فتح المصحف بالصفحات الكاملة (604)',
          'مخطط الختمات والورد القرآني',
          'البحث الصوتي عن الآيات',
          'بوابة علوم القرآن والتفاسير',
        ]) {
          expect(find.text(expectedLabel), findsOneWidget);
          final itemNode = _findSemanticNodeByLabel(tester, expectedLabel);
          expect(itemNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        }

        // Activate QuranHubScreen via SemanticsAction.tap at 2.0x and return cleanly
        final hubItem = _findSemanticNodeByLabel(tester, 'بوابة علوم القرآن والتفاسير');
        tester.binding.pipelineOwner.semanticsOwner!
            .performAction(hubItem.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(find.byType(QuranHubScreen), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(MushafScreen), findsOneWidget);

        // Switch all 4 tabs via SemanticsAction.tap at 2.0x
        for (final tabLabel in const [
          'الأجزاء (٣٠)',
          'صفحات المصحف (٦٠٤)',
          'العلامات المرجعية',
          'السور (١١٤)',
        ]) {
          await tester.ensureVisible(find.text(tabLabel));
          await tester.pumpAndSettle();
          final tabNode = _findSemanticNodeByLabel(tester, tabLabel);
          tester.binding.pipelineOwner.semanticsOwner!
              .performAction(tabNode.id, SemanticsAction.tap);
          await tester.pumpAndSettle();
        }
        expect(find.text('سورة الفاتحة'), findsOneWidget);

        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();
        expect(find.byType(QuranHubScreen), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'Zero exceptions on MushafScreen + overflow menu at 2.0x');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        semantics.dispose();
      },
    );

    testWidgets(
      'Dispatch probe at 360x800 @ 2.0x: all 5 overflow menu callbacks dispatch via SemanticsAction.tap through real PopupMenuButton.onSelected and Navigator.push with zero exceptions',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final dispatched = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(textScaler: const TextScaler.linear(2.0)),
                child: child!,
              );
            },
            home: MushafScreen(
              headerDestinationBuilderForTesting: (actionId, {searchQuery}) {
                final tag = searchQuery == null ? actionId : '$actionId:$searchQuery';
                dispatched.add(tag);
                return (_) => Scaffold(
                      appBar: AppBar(title: Text('PROBE:$tag')),
                      body: Center(child: Text('DISPATCHED:$tag')),
                    );
              },
              voiceSearchLauncherForTesting: (_) async {
                dispatched.add('voiceSearchLaunched');
                return 'الفاتحة';
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          MediaQuery.textScalerOf(tester.element(find.byType(MushafScreen))).scale(10),
          equals(20.0),
          reason: 'Effective TextScaler must be 2.0x with no hidden cap',
        );
        expect(SettingsService.instance.lastReadPageNumber, equals(42));

        Future<void> activateOverflowItemViaSemantics(String menuLabel) async {
          final menuNode = _findSemanticNodeByLabel(tester, 'خيارات المصحف');
          tester.binding.pipelineOwner.semanticsOwner!
              .performAction(menuNode.id, SemanticsAction.tap);
          await tester.pumpAndSettle();

          final itemNode = _findSemanticNodeByLabel(tester, menuLabel);
          expect(itemNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
          tester.binding.pipelineOwner.semanticsOwner!
              .performAction(itemNode.id, SemanticsAction.tap);
          await tester.pumpAndSettle();
        }

        // 1. Quick Search callback dispatch via SemanticsAction.tap
        await activateOverflowItemViaSemantics('البحث القرآني السريع');
        expect(find.text('DISPATCHED:quickSearch'), findsOneWidget);
        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();

        // 2. 604-page reader callback dispatch via SemanticsAction.tap
        await activateOverflowItemViaSemantics('فتح المصحف بالصفحات الكاملة (604)');
        expect(find.text('DISPATCHED:pageMode'), findsOneWidget);
        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();

        // 3. Khatma callback dispatch via SemanticsAction.tap
        await activateOverflowItemViaSemantics('مخطط الختمات والورد القرآني');
        expect(find.text('DISPATCHED:khatma'), findsOneWidget);
        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();

        // 4. Voice Search callback dispatch + query follow-up push via SemanticsAction.tap
        await activateOverflowItemViaSemantics('البحث الصوتي عن الآيات');
        expect(find.text('DISPATCHED:voiceSearchResult:الفاتحة'), findsOneWidget);
        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();

        // 5. Quran Hub callback dispatch via SemanticsAction.tap
        await activateOverflowItemViaSemantics('بوابة علوم القرآن والتفاسير');
        expect(find.text('DISPATCHED:quranHub'), findsOneWidget);
        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();

        expect(
          dispatched,
          equals([
            'quickSearch',
            'pageMode',
            'khatma',
            'voiceSearchLaunched',
            'voiceSearchResult:الفاتحة',
            'quranHub',
          ]),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'All 5 overflow menu callbacks at 360x800 2.0x must dispatch with zero exceptions',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        semantics.dispose();
      },
    );

    testWidgets(
      'Real-font PNG captures for MushafScreen across all 4 tabs and open action menu at 360x800 and 412x915 (1.0x and 2.0x)',
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
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          appRouter.go('/mushaf');
          await tester.pumpWidget(_buildRouterApp(textScale: scale));
          await tester.pumpAndSettle();

          appRouter.push('/mushaf-reader');
          await tester.pumpAndSettle();

          _assertMushafHeaderUnclippedAndHighContrast(
            tester,
            'capture_$tag',
            theme: AppTheme.lightTheme,
          );

          // Tab 1: Surahs
          await _capturePng(tester, 'repair11_mushaf_tab1_surahs_$tag.png');

          // On 360x800 (1.0x & 2.0x), also capture Tabs 2, 3, and 4
          if (size.width == 360) {
            await tester.ensureVisible(find.text('الأجزاء (٣٠)'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('الأجزاء (٣٠)'));
            await tester.pumpAndSettle();
            await _capturePng(tester, 'repair11_mushaf_tab2_juz_$tag.png');

            await tester.ensureVisible(find.text('صفحات المصحف (٦٠٤)'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('صفحات المصحف (٦٠٤)'));
            await tester.pumpAndSettle();
            await _capturePng(tester, 'repair11_mushaf_tab3_pages_$tag.png');

            await tester.ensureVisible(find.text('العلامات المرجعية'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('العلامات المرجعية'));
            await tester.pumpAndSettle();
            await _capturePng(tester, 'repair11_mushaf_tab4_bookmarks_$tag.png');

            await tester.ensureVisible(find.text('السور (١١٤)'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('السور (١١٤)'));
            await tester.pumpAndSettle();
          }

          // Open overflow action menu and capture PNG at all 4 viewport/scale combos
          await tester.tap(find.byKey(const ValueKey('mushaf_header_overflow_menu')));
          await tester.pumpAndSettle();
          expect(find.text('فتح المصحف بالصفحات الكاملة (604)'), findsOneWidget);
          expect(find.text('مخطط الختمات والورد القرآني'), findsOneWidget);
          expect(find.text('البحث الصوتي عن الآيات'), findsOneWidget);
          expect(find.text('بوابة علوم القرآن والتفاسير'), findsOneWidget);
          if (scale >= 1.35) {
            expect(find.text('البحث القرآني السريع'), findsOneWidget);
          }
          await _capturePng(tester, 'repair11_mushaf_action_menu_$tag.png');

          // Dismiss menu cleanly
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull, reason: 'Zero exceptions during capture $tag');
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        semantics.dispose();
      },
    );
  });
}
