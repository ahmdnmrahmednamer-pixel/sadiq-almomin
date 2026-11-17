import 'dart:io';
import 'dart:ui' show Tristate;
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

const List<String> _tabLabels = [
  'إشراقة اليوم',
  'رحاب القرآن',
  'محراب الصلاة',
  'أُنس الذاكرين',
  'رياض العلم',
];

const List<String> _tabPaths = [
  '/home',
  '/mushaf',
  '/prayer',
  '/adhkar-hub',
  '/library',
];

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

List<SemanticsNode> _findNavBarTabNodes(WidgetTester tester, String tabLabel) {
  final matches = <SemanticsNode>[];
  for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
    final data = node.getSemanticsData();
    if (data.label.contains(tabLabel) && data.label.contains('of 5')) {
      matches.add(node);
    }
  }
  return matches;
}

void _assertNavBarGeometryAndLabels(
  WidgetTester tester, {
  required Size viewport,
  required double scale,
  required int expectedSelectedIndex,
}) {
  final navBarFinder = find.byType(NavigationBar);
  expect(navBarFinder, findsOneWidget);

  final navBar = tester.widget<NavigationBar>(navBarFinder);
  expect(navBar.destinations.length, equals(5));
  expect(navBar.selectedIndex, equals(expectedSelectedIndex));

  final navBarRect = tester.getRect(navBarFinder);
  expect(navBarRect.bottom, lessThanOrEqualTo(viewport.height + 0.5),
      reason: 'NavigationBar must remain fully inside viewport height at ${viewport.width.toInt()}x${viewport.height.toInt()} ${scale}x');

  if (viewport.width <= 360 && scale >= 2.0) {
    expect(navBarRect.height, greaterThan(70.0),
        reason: 'NavigationBar height must grow beyond 70px at 360x800 2.0x to avoid vertical label clipping');
  }

  final labelRects = <Rect>[];
  for (int i = 0; i < _tabLabels.length; i++) {
    final label = _tabLabels[i];
    final textFinder = find.descendant(of: navBarFinder, matching: find.text(label));
    expect(textFinder, findsOneWidget, reason: 'Expected exactly 1 label "$label" in NavigationBar');

    final textWidget = tester.widget<Text>(textFinder);
    final effectiveStyle = textWidget.style;
    expect(
      effectiveStyle?.fontWeight,
      equals(i == expectedSelectedIndex ? FontWeight.w700 : FontWeight.w500),
      reason: 'Label "$label" must reflect ${i == expectedSelectedIndex ? "selected (w700)" : "unselected (w500)"} weight',
    );

    final labelRect = tester.getRect(textFinder);
    expect(labelRect.top, greaterThanOrEqualTo(navBarRect.top - 0.5),
        reason: 'Label "$label" clipped at top of NavigationBar at ${viewport.width.toInt()}x${viewport.height.toInt()} ${scale}x');
    expect(labelRect.bottom, lessThanOrEqualTo(navBarRect.bottom + 0.5),
        reason: 'Label "$label" clipped at bottom of NavigationBar at ${viewport.width.toInt()}x${viewport.height.toInt()} ${scale}x');
    expect(labelRect.left, greaterThanOrEqualTo(navBarRect.left - 0.5),
        reason: 'Label "$label" clipped at left of NavigationBar');
    expect(labelRect.right, lessThanOrEqualTo(navBarRect.right + 0.5),
        reason: 'Label "$label" clipped at right of NavigationBar');

    // Verify no horizontal overlap with previously checked tab labels
    for (final prevRect in labelRects) {
      expect(
        labelRect.overlaps(prevRect),
        isFalse,
        reason: 'Label "$label" overlaps adjacent tab label at ${viewport.width.toInt()}x${viewport.height.toInt()} ${scale}x',
      );
    }
    labelRects.add(labelRect);

    // Verify single semantic node per tab (no duplicates), with SemanticsAction.tap & exact selected state
    final tabNodes = _findNavBarTabNodes(tester, label);
    expect(
      tabNodes.length,
      equals(1),
      reason: 'Expected exactly 1 semantic tab node for "$label" (no duplicate nodes)',
    );
    final nodeData = tabNodes.single.getSemanticsData();
    expect(nodeData.hasAction(SemanticsAction.tap), isTrue,
        reason: 'Tab "$label" must expose SemanticsAction.tap');
    expect(
      nodeData.flagsCollection.isSelected == Tristate.isTrue,
      equals(i == expectedSelectedIndex),
      reason: 'Semantic selected state for "$label" must match expectedSelectedIndex=$expectedSelectedIndex',
    );
  }

  // Verify all 5 destination icons fit cleanly above labels inside NavigationBar
  final iconFinders = find.descendant(of: navBarFinder, matching: find.byType(Icon));
  expect(iconFinders, findsNWidgets(5));
  for (int i = 0; i < 5; i++) {
    final iconRect = tester.getRect(iconFinders.at(i));
    expect(iconRect.top, greaterThanOrEqualTo(navBarRect.top - 0.5));
    expect(iconRect.bottom, lessThanOrEqualTo(navBarRect.bottom + 0.5));
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

  group('Repair 3: MainScaffold Adaptive Bottom NavigationBar Accessibility & Layout', () {
    testWidgets('Actual appRouter MainScaffold NavigationBar at 360x800 and 412x915 at 1.0x and 2.0x renders unclipped 5 tabs with valid selected/unselected labels and semantics', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const matrix = <(Size, double)>[
        (Size(360, 800), 1.0),
        (Size(360, 800), 2.0),
        (Size(412, 915), 1.0),
        (Size(412, 915), 2.0),
      ];

      for (final (viewport, scale) in matrix) {
        tester.view.physicalSize = viewport;
        appRouter.go('/home');
        await tester.pumpWidget(_buildRouterApp(router: appRouter, textScale: scale));
        await tester.pumpAndSettle();

        expect(
          MediaQuery.textScalerOf(tester.element(find.byType(MainScaffold))).scale(10),
          equals(scale * 10),
          reason: 'Effective TextScaler at MainScaffold must equal ${scale}x',
        );

        _assertNavBarGeometryAndLabels(
          tester,
          viewport: viewport,
          scale: scale,
          expectedSelectedIndex: 0,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'Actual appRouter /home at ${viewport.width.toInt()}x${viewport.height.toInt()} ${scale}x must produce zero exceptions',
        );
      }

      PrayerService.instance.stopLiveTicker();
      semantics.dispose();
    });

    testWidgets('All 5 NavigationBar tabs activate via SemanticsAction.tap across actual appRouter at 360x800 and 412x915 (1.0x) and update destination + selected state cleanly', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final viewport in const [Size(360, 800), Size(412, 915)]) {
        tester.view.physicalSize = viewport;
        appRouter.go('/home');
        await tester.pumpWidget(_buildRouterApp(router: appRouter, textScale: 1.0));
        await tester.pumpAndSettle();

        for (final targetIndex in const [1, 2, 3, 4, 0]) {
          final targetLabel = _tabLabels[targetIndex];
          final nodes = _findNavBarTabNodes(tester, targetLabel);
          expect(nodes.length, equals(1));
          expect(nodes.single.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

          tester.binding.pipelineOwner.semanticsOwner!
              .performAction(nodes.single.id, SemanticsAction.tap);
          await tester.pumpAndSettle();

          expect(
            appRouter.routeInformationProvider.value.uri.path,
            equals(_tabPaths[targetIndex]),
            reason: 'Semantic tap on "$targetLabel" must route to ${_tabPaths[targetIndex]}',
          );
          _assertNavBarGeometryAndLabels(
            tester,
            viewport: viewport,
            scale: 1.0,
            expectedSelectedIndex: targetIndex,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'Semantic tap to ${_tabPaths[targetIndex]} at ${viewport.width.toInt()}x${viewport.height.toInt()} 1.0x must have zero exceptions',
          );
        }
      }

      PrayerService.instance.stopLiveTicker();
      semantics.dispose();
    });

    testWidgets('All 5 MainScaffold NavigationBar tabs activate via SemanticsAction.tap at 360x800 and 412x915 at 2.0x with unclipped labels and updated selected states', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final viewport in const [Size(360, 800), Size(412, 915)]) {
        tester.view.physicalSize = viewport;
        final shellRouter = GoRouter(
          initialLocation: '/home',
          routes: [
            ShellRoute(
              builder: (context, state, child) => MainScaffold(child: child),
              routes: [
                for (int i = 0; i < _tabPaths.length; i++)
                  GoRoute(
                    path: _tabPaths[i],
                    builder: (_, __) => Scaffold(
                      body: Center(child: Text('HUB:${_tabPaths[i]}')),
                    ),
                  ),
              ],
            ),
          ],
        );
        addTearDown(shellRouter.dispose);

        await tester.pumpWidget(_buildRouterApp(router: shellRouter, textScale: 2.0));
        await tester.pumpAndSettle();

        expect(
          MediaQuery.textScalerOf(tester.element(find.byType(MainScaffold))).scale(10),
          equals(20.0),
        );
        _assertNavBarGeometryAndLabels(
          tester,
          viewport: viewport,
          scale: 2.0,
          expectedSelectedIndex: 0,
        );

        for (final targetIndex in const [1, 2, 3, 4, 0]) {
          final targetLabel = _tabLabels[targetIndex];
          final nodes = _findNavBarTabNodes(tester, targetLabel);
          expect(nodes.length, equals(1));
          expect(nodes.single.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

          tester.binding.pipelineOwner.semanticsOwner!
              .performAction(nodes.single.id, SemanticsAction.tap);
          await tester.pumpAndSettle();

          expect(find.text('HUB:${_tabPaths[targetIndex]}'), findsOneWidget);
          _assertNavBarGeometryAndLabels(
            tester,
            viewport: viewport,
            scale: 2.0,
            expectedSelectedIndex: targetIndex,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'MainScaffold tab switch to ${_tabPaths[targetIndex]} at ${viewport.width.toInt()}x${viewport.height.toInt()} 2.0x must have zero exceptions',
          );
        }
      }

      semantics.dispose();
    });
  });
}
