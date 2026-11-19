import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/router.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/core/services/daily_wird_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/prayer_tracker_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';

const List<String> _expectedAllAboutStrings = [
  'عن تطبيق صديق المؤمن',
  'منظومة إسلامية شاملة',
  'مميزات التطبيق ومعالمه الكبرى:',
  'محراب القرآن الكريم وتدبر علومه',
  'القرآن والتفسير والإعراب',
  'مواقيت الصلاة واستوديو الأذان والإقامة',
  'مواقيت الصلاة والأذان والإقامة',
  'المكتبة الصوتية وديوان كبار القراء',
  'تلاوات القرآن الكريم',
  'حصن المسلم والسنة النبوية والسبحة الذكية',
  'أذكار اليوم والسبحة',
  'محاريب العبادات والقبلة والزكاة والأنبياء',
  'القبلة والزكاة وقصص الأنبياء',
  'صفاء المقصد ونقاء العهد الوقفـي',
  'تطبيق مجاني بلا إعلانات',
  'إغلاق',
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
  for (final p in ['assets/fonts/Amiri-Regular.ttf', 'assets/fonts/Amiri-Bold.ttf']) {
    final f = File(p);
    if (f.existsSync()) {
      amiriLoader.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
    }
  }
  await amiriLoader.load();

  final iconFile = File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf');
  if (iconFile.existsSync()) {
    final iconLoader = FontLoader('MaterialIcons');
    iconLoader.addFont(Future.value(ByteData.view(iconFile.readAsBytesSync().buffer)));
    await iconLoader.load();
  }
}

Widget _buildRouterApp({required double textScale}) {
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

List<SemanticsNode> _findSemanticNodesWithText(WidgetTester tester, String target) {
  final matches = <SemanticsNode>[];
  for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
    final data = node.getSemanticsData();
    if (data.label == target || data.tooltip == target) {
      matches.add(node);
    }
  }
  return matches;
}

List<SemanticsNode> _findSemanticNodesContaining(WidgetTester tester, String substring) {
  final matches = <SemanticsNode>[];
  for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
    final data = node.getSemanticsData();
    if (data.label.contains(substring) || data.tooltip.contains(substring)) {
      matches.add(node);
    }
  }
  return matches;
}

SemanticsNode _findSingleActionableNode(WidgetTester tester, String target) {
  final matches = _findSemanticNodesWithText(tester, target);
  expect(
    matches.length,
    equals(1),
    reason: 'Expected exactly 1 semantic node for "$target" (found ${matches.length})',
  );
  final node = matches.single;
  expect(
    node.getSemanticsData().hasAction(SemanticsAction.tap),
    isTrue,
    reason: 'Semantic node "$target" must expose SemanticsAction.tap',
  );
  return node;
}

Future<void> _activateSemanticNode(WidgetTester tester, String target) async {
  final node = _findSingleActionableNode(tester, target);
  tester.binding.pipelineOwner.semanticsOwner!.performAction(
    node.id,
    SemanticsAction.tap,
  );
  await tester.pumpAndSettle();
}

void _assertNoTextTruncationInDialog(WidgetTester tester, Finder dialogFinder) {
  final texts = tester.widgetList<Text>(
    find.descendant(of: dialogFinder, matching: find.byType(Text)),
  );
  expect(texts.length, greaterThanOrEqualTo(_expectedAllAboutStrings.length));
  for (final text in texts) {
    expect(
      text.overflow,
      isNot(TextOverflow.ellipsis),
      reason: 'About modal text "${text.data}" must not hide content with ellipsis',
    );
    expect(
      text.maxLines,
      isNull,
      reason: 'About modal text "${text.data}" must not clamp maxLines',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadBundledFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app_language': 'ar',
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
    appRouter.go('/home');
  });

  group('Repair 5: About modal layout, scrolling, wording & accessibility', () {
    for (final viewport in const [Size(360, 800), Size(412, 915)]) {
      for (final scale in const [1.0, 2.0]) {
        testWidgets(
          'Actual appRouter /home opens About modal cleanly at '
          '${viewport.width.toInt()}x${viewport.height.toInt()} ${scale}x with full scroll, bounds & semantics',
          (tester) async {
            final semantics = tester.ensureSemantics();
            tester.view.devicePixelRatio = 1.0;
            tester.view.physicalSize = viewport;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            appRouter.go('/home');
            await tester.pumpWidget(_buildRouterApp(textScale: scale));
            await tester.pumpAndSettle();

            // Open via SemanticsAction.tap on Home AppBar Info button
            await _activateSemanticNode(tester, 'عن التطبيق');

            final dialogFinder = find.byKey(const ValueKey('settings_about_dialog'));
            expect(dialogFinder, findsOneWidget);

            // Effective text scale must remain unclamped inside the modal
            final effectiveScale =
                MediaQuery.textScalerOf(tester.element(dialogFinder)).scale(1.0);
            expect(effectiveScale, closeTo(scale, 0.001));

            // Dialog visual card must stay strictly within viewport bounds with barrier margin
            final dialogMaterial = find
                .descendant(of: dialogFinder, matching: find.byType(Material))
                .first;
            final cardRect = tester.getRect(dialogMaterial);
            expect(cardRect.left, greaterThanOrEqualTo(12.0));
            expect(cardRect.top, greaterThanOrEqualTo(12.0));
            expect(cardRect.right, lessThanOrEqualTo(viewport.width - 12.0));
            expect(cardRect.bottom, lessThanOrEqualTo(viewport.height - 12.0));

            // All wording must exist verbatim without ellipsis or maxLines truncation
            for (final expectedText in _expectedAllAboutStrings) {
              expect(
                find.descendant(of: dialogFinder, matching: find.text(expectedText)),
                findsOneWidget,
                reason: 'Missing exact About wording: $expectedText',
              );
            }
            _assertNoTextTruncationInDialog(tester, dialogFinder);

            // Section header must stay strictly within the dialog card horizontally (no right/left overflow)
            final sectionHeaderRect = tester.getRect(
              find.descendant(
                of: dialogFinder,
                matching: find.text('مميزات التطبيق ومعالمه الكبرى:'),
              ),
            );
            expect(sectionHeaderRect.left, greaterThanOrEqualTo(cardRect.left));
            expect(sectionHeaderRect.right, lessThanOrEqualTo(cardRect.right));

            // Close button must be inside viewport, >= 48x48, and expose single semantic button with tap
            final closeBtnFinder = find.byKey(const ValueKey('settings_about_close_button'));
            final closeBtnRect = tester.getRect(closeBtnFinder);
            expect(closeBtnRect.left, greaterThanOrEqualTo(cardRect.left));
            expect(closeBtnRect.right, lessThanOrEqualTo(cardRect.right));
            expect(closeBtnRect.bottom, lessThanOrEqualTo(cardRect.bottom));
            expect(closeBtnRect.width, greaterThanOrEqualTo(48.0));
            expect(closeBtnRect.height, greaterThanOrEqualTo(48.0));

            final headerNodes = _findSemanticNodesContaining(tester, 'عن تطبيق صديق المؤمن');
            expect(
              headerNodes.length,
              equals(1),
              reason: 'Dialog header must be announced once without duplicate semantic nodes',
            );
            expect(
              headerNodes.single.getSemanticsData().flagsCollection.isHeader,
              isTrue,
              reason: 'Dialog header must carry semantic header flag',
            );
            final closeSemanticNode = _findSingleActionableNode(tester, 'إغلاق');
            expect(
              closeSemanticNode.getSemanticsData().flagsCollection.isButton,
              isTrue,
              reason: 'Close action must be marked as a semantic button',
            );

            // Scroll to the very bottom of About content and verify the last religious/waqf pillar is fully reachable
            final scrollFinder = find.byKey(const ValueKey('settings_about_scroll_view'));
            expect(scrollFinder, findsOneWidget);
            final scrollViewportRect = tester.getRect(scrollFinder);
            final scrollableFinder = find.descendant(
              of: scrollFinder,
              matching: find.byType(Scrollable),
            );
            final scrollableState = tester.state<ScrollableState>(scrollableFinder.first);
            expect(scrollableState.position.maxScrollExtent, greaterThanOrEqualTo(0));

            final lastPillarTitle = find.text('صفاء المقصد ونقاء العهد الوقفـي');
            final lastPillarDesc = find.text(
              'تطبيق مجاني بلا إعلانات',
            );

            scrollableState.position.jumpTo(scrollableState.position.maxScrollExtent);
            await tester.pumpAndSettle();

            expect(scrollableState.position.pixels,
                closeTo(scrollableState.position.maxScrollExtent, 0.5));
            final lastDescRect = tester.getRect(lastPillarDesc);
            expect(lastDescRect.top, greaterThanOrEqualTo(scrollViewportRect.top - 1.0));
            expect(tester.getRect(lastPillarTitle).top,
                greaterThanOrEqualTo(scrollViewportRect.top - 1.0));
            expect(lastDescRect.left, greaterThanOrEqualTo(cardRect.left));
            expect(lastDescRect.right, lessThanOrEqualTo(cardRect.right));
            expect(lastDescRect.bottom, lessThanOrEqualTo(scrollViewportRect.bottom + 1.0));
            expect(tester.getRect(lastPillarTitle).top, lessThan(lastDescRect.top));

            // Close button remains pinned & reachable after scrolling to bottom
            final closeAfterScrollRect = tester.getRect(closeBtnFinder);
            expect(closeAfterScrollRect.bottom, lessThanOrEqualTo(viewport.height - 12.0));

            // Semantic activation on 'إغلاق' closes the dialog cleanly
            await _activateSemanticNode(tester, 'إغلاق');
            expect(dialogFinder, findsNothing);
            expect(find.byKey(const ValueKey('home_info_button')), findsOneWidget);

            expect(tester.takeException(), isNull);
            PrayerService.instance.stopLiveTicker();
            semantics.dispose();
          },
        );
      }
    }

    testWidgets(
      'Touch close, barrier tap dismiss, and system back all work at 360x800 2.0x',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(360, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        appRouter.go('/home');
        await tester.pumpWidget(_buildRouterApp(textScale: 2.0));
        await tester.pumpAndSettle();

        final dialogFinder = find.byKey(const ValueKey('settings_about_dialog'));

        // 1. Open by touch tap, close by touch tap on 'إغلاق'
        await tester.tap(find.byKey(const ValueKey('home_info_button')));
        await tester.pumpAndSettle();
        expect(dialogFinder, findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('settings_about_close_button')));
        await tester.pumpAndSettle();
        expect(dialogFinder, findsNothing);

        // 2. Re-open, dismiss by touching barrier scrim outside dialog
        await tester.tap(find.byKey(const ValueKey('home_info_button')));
        await tester.pumpAndSettle();
        expect(dialogFinder, findsOneWidget);

        await tester.tapAt(const Offset(6, 6));
        await tester.pumpAndSettle();
        expect(dialogFinder, findsNothing);

        // 3. Re-open, dismiss by system back route pop
        await tester.tap(find.byKey(const ValueKey('home_info_button')));
        await tester.pumpAndSettle();
        expect(dialogFinder, findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(dialogFinder, findsNothing);

        expect(tester.takeException(), isNull);
        PrayerService.instance.stopLiveTicker();
        semantics.dispose();
      },
    );

    testWidgets(
      'Actual appRouter /settings preserves v7.0 entry and opens About modal cleanly at 360x800 1.0x and 2.0x',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(360, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        for (final scale in const [1.0, 2.0]) {
          appRouter.go('/settings');
          await tester.pumpWidget(_buildRouterApp(textScale: scale));
          await tester.pumpAndSettle();

          final aboutTileText = find.text('رسالة التطبيق (الإصدار السابع v7.0)');
          final settingsScrollable = find.byType(Scrollable).first;
          await tester.scrollUntilVisible(
            aboutTileText,
            300,
            scrollable: settingsScrollable,
          );
          await tester.pumpAndSettle();
          expect(aboutTileText, findsOneWidget);

          await tester.tap(aboutTileText);
          await tester.pumpAndSettle();

          final dialogFinder = find.byKey(const ValueKey('settings_about_dialog'));
          expect(dialogFinder, findsOneWidget);
          expect(
            MediaQuery.textScalerOf(tester.element(dialogFinder)).scale(1.0),
            closeTo(scale, 0.001),
          );

          await _activateSemanticNode(tester, 'إغلاق');
          expect(dialogFinder, findsNothing);
          expect(tester.takeException(), isNull);
        }

        PrayerService.instance.stopLiveTicker();
        semantics.dispose();
      },
    );
  });
}
