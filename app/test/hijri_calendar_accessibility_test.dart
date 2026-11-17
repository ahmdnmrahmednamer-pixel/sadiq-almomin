import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/router.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/core/localization/app_localizations.dart';
import 'package:almomin/core/services/daily_wird_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/prayer_tracker_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';
import 'package:almomin/features/home/widgets/home_date_header_card.dart';
import 'package:almomin/features/prayer/hijri_calendar_screen.dart';

const List<(String, String)> _canonicalOccasions = [
  ('رأس السنة الهجرية', 'بداية العام الهجري الجديد واستذكار الهجرة النبوية الشريفة'),
  ('يوم عاشوراء', 'نجاة نبي الله موسى عليه السلام، ويستحب صيامه وتاسوعاء قبله'),
  ('المولد النبوي الشريف', 'مولد خير الأنام محمد ﷺ رحمة للعالمين'),
  ('الإسراء والمعراج', 'معجزة الإسراء بالرسول ﷺ وفرض الصلوات الخمس'),
  ('ليلة النصف من شعبان', 'تحويل القبلة إلى المسجد الحرام وليلة المغفرة والرحمة'),
  ('أول أيام شهر رمضان المبارك', 'شهر الصيام والقرآن وليلة القدر التي هي خير من ألف شهر'),
  ('عيد الفطر المبارك', 'فرحة إتمام الصيام وجائزة العابدين وزكاة الفطر'),
  ('يوم عرفة', 'خير يوم طلعت عليه الشمس، وصيامه يكفر سنة ماضية وقادمة'),
  ('عيد الأضحى المبارك', 'يوم النحر وأيام التشريق وذكر الله وذبح الأضاحي'),
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
    locale: const Locale('ar'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      );
    },
  );
}

List<SemanticsNode> _findSemanticNodesExact(WidgetTester tester, String target) {
  final matches = <SemanticsNode>[];
  for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
    final data = node.getSemanticsData();
    if (data.label == target || data.tooltip == target) {
      matches.add(node);
    }
  }
  return matches;
}

SemanticsNode _findSingleActionableNode(WidgetTester tester, String target) {
  final matches = _findSemanticNodesExact(tester, target);
  expect(
    matches.length,
    equals(1),
    reason: 'Expected exactly 1 semantic node for "$target" (got ${matches.length})',
  );
  final node = matches.single;
  expect(
    node.getSemanticsData().hasAction(SemanticsAction.tap),
    isTrue,
    reason: 'Semantic node "$target" must expose SemanticsAction.tap',
  );
  return node;
}

Future<void> _performSemanticTap(WidgetTester tester, String target) async {
  final node = _findSingleActionableNode(tester, target);
  tester.binding.pipelineOwner.semanticsOwner!.performAction(
    node.id,
    SemanticsAction.tap,
  );
  await tester.pumpAndSettle();
}

Future<void> _performSemanticTapByLabelPrefix(WidgetTester tester, String prefix) async {
  final matches = <SemanticsNode>[];
  for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
    final data = node.getSemanticsData();
    if (data.label.startsWith(prefix) && data.hasAction(SemanticsAction.tap)) {
      matches.add(node);
    }
  }
  expect(
    matches.length,
    equals(1),
    reason: 'Expected exactly 1 actionable semantic node starting with "$prefix" (got ${matches.length})',
  );
  tester.binding.pipelineOwner.semanticsOwner!.performAction(
    matches.single.id,
    SemanticsAction.tap,
  );
  await tester.pumpAndSettle();
}

String _expectedHijriBanner(DateTime date, {int adjustmentDays = 0}) {
  final h = HijriDateHelper.toHijri(date, adjustmentDays: adjustmentDays);
  final monthName = HijriDateHelper.hijriMonths[h['month']! - 1];
  return '${h['day']} $monthName ${h['year']} هـ';
}

bool _isRectFullyInsideViewport(Rect rect, Rect viewport, {double tolerance = 1.0}) {
  return rect.width > 0 &&
      rect.height > 0 &&
      rect.left >= viewport.left - tolerance &&
      rect.right <= viewport.right + tolerance &&
      rect.top >= viewport.top - tolerance &&
      rect.bottom <= viewport.bottom + tolerance;
}

void _assertNoTextTruncationInScreen(WidgetTester tester, Finder screenFinder) {
  final texts = tester.widgetList<Text>(
    find.descendant(of: screenFinder, matching: find.byType(Text)),
  );
  expect(texts, isNotEmpty);
  for (final text in texts) {
    expect(
      text.overflow,
      isNot(TextOverflow.ellipsis),
      reason: 'HijriCalendarScreen text "${text.data}" must not hide content with ellipsis',
    );
    expect(
      text.maxLines,
      isNull,
      reason: 'HijriCalendarScreen text "${text.data}" must not clamp maxLines',
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
    await SettingsService.instance.setHijriAdjustmentDays(0);
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

  group('Repair 6: HijriCalendarScreen responsive layout, bounds & accessibility', () {
    for (final viewport in const [Size(360, 800), Size(412, 915)]) {
      for (final scale in const [1.0, 2.0]) {
        testWidgets(
          'Actual appRouter /calendar renders cleanly at '
          '${viewport.width.toInt()}x${viewport.height.toInt()} ${scale}x with zero overflows, truly visible occasions & unique semantics',
          (tester) async {
            final semantics = tester.ensureSemantics();
            tester.view.devicePixelRatio = 1.0;
            tester.view.physicalSize = viewport;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            appRouter.go('/calendar');
            await tester.pumpWidget(_buildRouterApp(textScale: scale));
            await tester.pumpAndSettle();

            final screenFinder = find.byType(HijriCalendarScreen);
            expect(screenFinder, findsOneWidget);

            // Effective text scale inside screen body must remain unclamped
            final effectiveScale =
                MediaQuery.textScalerOf(tester.element(screenFinder)).scale(1.0);
            expect(effectiveScale, closeTo(scale, 0.001));

            // Full AppBar title present and inside viewport bounds without ellipsis
            final appBarTitle = find.text('التقويم الهجري والمناسبات');
            expect(appBarTitle, findsOneWidget);
            final titleRect = tester.getRect(appBarTitle);
            expect(titleRect.left, greaterThanOrEqualTo(0.0));
            expect(titleRect.right, lessThanOrEqualTo(viewport.width));

            _assertNoTextTruncationInScreen(tester, screenFinder);

            // Banner & AppBar action buttons within viewport and uniquely actionable
            final bannerRect = tester.getRect(find.byKey(const ValueKey('hijri_banner_card')));
            expect(bannerRect.left, greaterThanOrEqualTo(0.0));
            expect(bannerRect.right, lessThanOrEqualTo(viewport.width));

            _findSingleActionableNode(tester, 'إمساكية ومحراب رمضان المبارك');
            _findSingleActionableNode(tester, 'تعديل رؤية الهلال (± يومين)');

            final listViewFinder = find.byKey(const ValueKey('hijri_calendar_list_view'));
            final listViewport = tester.getRect(listViewFinder);
            final listScrollable = find
                .descendant(
                  of: listViewFinder,
                  matching: find.byType(Scrollable),
                )
                .first;

            // Ensure date navigation card is visible and all 3 controls fit within viewport with >= 48x48 targets
            final navCard = find.byKey(const ValueKey('hijri_nav_controls_card'));
            await tester.scrollUntilVisible(navCard, 200, scrollable: listScrollable);
            await tester.pumpAndSettle();

            for (final control in const [
              (ValueKey('hijri_prev_day_button'), 'اليوم السابق'),
              (ValueKey('hijri_pick_date_button'), 'اختر تاريخاً'),
              (ValueKey('hijri_next_day_button'), 'اليوم التالي'),
            ]) {
              final btnFinder = find.byKey(control.$1);
              await tester.scrollUntilVisible(btnFinder, 160, scrollable: listScrollable);
              await tester.pumpAndSettle();
              final rect = tester.getRect(btnFinder);
              expect(rect.left, greaterThanOrEqualTo(0.0));
              expect(rect.right, lessThanOrEqualTo(viewport.width));
              expect(rect.width, greaterThanOrEqualTo(48.0));
              expect(rect.height, greaterThanOrEqualTo(48.0));
              _findSingleActionableNode(tester, control.$2);
            }

            // Scroll through ListView in fine steps and record each occasion ONLY when BOTH its title AND
            // description rects are fully contained inside the visible ListView viewport (never offscreen cache).
            await tester.scrollUntilVisible(
              find.text('المناسبات الإسلامية القادمة'),
              200,
              scrollable: listScrollable,
            );
            await tester.pumpAndSettle();
            final occHeaderRect = tester.getRect(find.text('المناسبات الإسلامية القادمة'));
            expect(_isRectFullyInsideViewport(occHeaderRect, listViewport), isTrue);

            final scrollState = tester.state<ScrollableState>(listScrollable);
            scrollState.position.jumpTo(0);
            await tester.pumpAndSettle();

            final trulyViewedOccasions = <String>{};
            double offset = 0;
            for (int step = 0; step < 80; step++) {
              final currentMax = scrollState.position.maxScrollExtent;
              final clampedOffset = offset.clamp(0.0, currentMax);
              scrollState.position.jumpTo(clampedOffset);
              await tester.pumpAndSettle();

              for (final (occTitle, occDesc) in _canonicalOccasions) {
                if (trulyViewedOccasions.contains(occTitle)) continue;
                final titleFinder = find.text(occTitle);
                final descFinder = find.text(occDesc);
                if (titleFinder.evaluate().isEmpty || descFinder.evaluate().isEmpty) {
                  continue;
                }
                final occTitleRect = tester.getRect(titleFinder.first);
                final occDescRect = tester.getRect(descFinder.first);
                if (_isRectFullyInsideViewport(occTitleRect, listViewport) &&
                    _isRectFullyInsideViewport(occDescRect, listViewport)) {
                  trulyViewedOccasions.add(occTitle);
                }
              }

              final updatedMax = scrollState.position.maxScrollExtent;
              if (clampedOffset >= updatedMax - 0.5) {
                break;
              }
              offset = clampedOffset + 100.0;
            }

            expect(
              trulyViewedOccasions,
              containsAll(_canonicalOccasions.map((e) => e.$1)),
              reason:
                  'All 9 canonical occasions (both title and description) must be fully visible inside ListView viewport across scroll at '
                  '${viewport.width.toInt()}x${viewport.height.toInt()} ${scale}x; viewed: $trulyViewedOccasions',
            );

            expect(tester.takeException(), isNull);
            PrayerService.instance.stopLiveTicker();
            semantics.dispose();
          },
        );
      }
    }

    testWidgets(
      'Day navigation (touch & SemanticsAction.tap), DatePicker selection/cancel/back, and Crescent Adjustment Dialog work accurately at 360x800 2.0x',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(360, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final today = DateTime.now();
        appRouter.go('/calendar');
        await tester.pumpWidget(_buildRouterApp(textScale: 2.0));
        await tester.pumpAndSettle();

        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_date_text'))).data,
          equals(_expectedHijriBanner(today)),
        );
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_gregorian_text'))).data,
          equals('الموافق ${HijriDateHelper.getGregorianDateString(today)}'),
        );

        final listScrollable = find
            .descendant(
              of: find.byKey(const ValueKey('hijri_calendar_list_view')),
              matching: find.byType(Scrollable),
            )
            .first;

        Future<void> scrollToTop() async {
          final state = tester.state<ScrollableState>(listScrollable);
          state.position.jumpTo(0);
          await tester.pumpAndSettle();
        }

        // 1. Touch tap on 'اليوم التالي' advances by +1 day
        final nextBtn = find.byKey(const ValueKey('hijri_next_day_button'));
        await tester.scrollUntilVisible(nextBtn, 200, scrollable: listScrollable);
        await tester.pumpAndSettle();
        await tester.tap(nextBtn);
        await tester.pumpAndSettle();

        await scrollToTop();
        final tomorrow = today.add(const Duration(days: 1));
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_date_text'))).data,
          equals(_expectedHijriBanner(tomorrow)),
        );
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_gregorian_text'))).data,
          equals('الموافق ${HijriDateHelper.getGregorianDateString(tomorrow)}'),
        );

        // 2. SemanticsAction.tap on 'اليوم السابق' returns to today, then another steps to yesterday
        final prevBtn = find.byKey(const ValueKey('hijri_prev_day_button'));
        await tester.scrollUntilVisible(prevBtn, 200, scrollable: listScrollable);
        await tester.pumpAndSettle();
        await _performSemanticTap(tester, 'اليوم السابق');
        await scrollToTop();
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_date_text'))).data,
          equals(_expectedHijriBanner(today)),
        );

        await tester.scrollUntilVisible(prevBtn, 200, scrollable: listScrollable);
        await tester.pumpAndSettle();
        await _performSemanticTap(tester, 'اليوم السابق');
        await scrollToTop();
        final yesterday = today.subtract(const Duration(days: 1));
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_date_text'))).data,
          equals(_expectedHijriBanner(yesterday)),
        );

        // Return back to today via SemanticsAction.tap on 'اليوم التالي'
        await tester.scrollUntilVisible(nextBtn, 200, scrollable: listScrollable);
        await tester.pumpAndSettle();
        await _performSemanticTap(tester, 'اليوم التالي');
        await scrollToTop();
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_date_text'))).data,
          equals(_expectedHijriBanner(today)),
        );

        // 3. 'اختر تاريخاً' via SemanticsAction.tap at 360x800 2.0x:
        //    Verify responsive large-text picker bounds/actions, semantic day selection + confirmation updates banner,
        //    and both cancel button & system back preserve previous date.
        final pickBtn = find.byKey(const ValueKey('hijri_pick_date_button'));
        await tester.scrollUntilVisible(pickBtn, 200, scrollable: listScrollable);
        await tester.pumpAndSettle();
        await _performSemanticTap(tester, 'اختر تاريخاً');

        final datePickerFinder =
            find.byKey(const ValueKey('hijri_accessible_date_picker_dialog'));
        expect(datePickerFinder, findsOneWidget);
        final pickerMaterial = find
            .descendant(of: datePickerFinder, matching: find.byType(Material))
            .first;
        final pickerRect = tester.getRect(pickerMaterial);
        expect(pickerRect.left, greaterThanOrEqualTo(0.0));
        expect(pickerRect.top, greaterThanOrEqualTo(0.0));
        expect(pickerRect.right, lessThanOrEqualTo(360.0));
        expect(pickerRect.bottom, lessThanOrEqualTo(800.0));

        // Actions 'الإلغاء' and 'حسنًا' must be present, inside dialog bounds, and uniquely actionable
        _findSingleActionableNode(tester, 'الإلغاء');
        _findSingleActionableNode(tester, 'حسنًا');
        final okRect = tester.getRect(find.text('حسنًا'));
        final cancelRect = tester.getRect(find.text('الإلغاء'));
        expect(okRect.bottom, lessThanOrEqualTo(pickerRect.bottom));
        expect(cancelRect.bottom, lessThanOrEqualTo(pickerRect.bottom));

        // Pick a distinct 2-digit day in the current month and confirm via SemanticsAction.tap
        final confirmedDay = today.day == 11 ? 12 : 11;
        final confirmedDate = DateTime(today.year, today.month, confirmedDay);
        final pickerScrollable = find
            .descendant(
              of: find.byKey(const ValueKey('hijri_picker_scroll_view')),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('hijri_picker_day_$confirmedDay')),
          140,
          scrollable: pickerScrollable,
        );
        await tester.pumpAndSettle();
        await _performSemanticTapByLabelPrefix(tester, '$confirmedDay، ');
        await _performSemanticTap(tester, 'حسنًا');
        expect(datePickerFinder, findsNothing);

        await scrollToTop();
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_date_text'))).data,
          equals(_expectedHijriBanner(confirmedDate)),
        );
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_gregorian_text'))).data,
          equals('الموافق ${HijriDateHelper.getGregorianDateString(confirmedDate)}'),
        );

        // Re-open DatePicker, select another day, tap 'الإلغاء' -> previous confirmedDate preserved
        await tester.scrollUntilVisible(pickBtn, 200, scrollable: listScrollable);
        await tester.pumpAndSettle();
        await _performSemanticTap(tester, 'اختر تاريخاً');
        expect(datePickerFinder, findsOneWidget);
        await _performSemanticTapByLabelPrefix(tester, '7، ');
        await _performSemanticTap(tester, 'الإلغاء');
        expect(datePickerFinder, findsNothing);

        await scrollToTop();
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_date_text'))).data,
          equals(_expectedHijriBanner(confirmedDate)),
        );

        // Re-open DatePicker, select another day, trigger system back -> previous confirmedDate preserved
        await tester.scrollUntilVisible(pickBtn, 200, scrollable: listScrollable);
        await tester.pumpAndSettle();
        await _performSemanticTap(tester, 'اختر تاريخاً');
        expect(datePickerFinder, findsOneWidget);
        await _performSemanticTapByLabelPrefix(tester, '8، ');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(datePickerFinder, findsNothing);

        await scrollToTop();
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_date_text'))).data,
          equals(_expectedHijriBanner(confirmedDate)),
        );

        // 4. Open Crescent Sighting Adjustment Dialog via SemanticsAction.tap at 360x800 2.0x
        await _performSemanticTap(tester, 'تعديل رؤية الهلال (± يومين)');
        final adjustDialog = find.byKey(const ValueKey('hijri_adjustment_dialog'));
        expect(adjustDialog, findsOneWidget);

        // Both decrement & increment have distinct, unique semantic labels (no duplicate tooltip bug)
        _findSingleActionableNode(tester, 'إنقاص أو تقليل');
        _findSingleActionableNode(tester, 'إضافة أو زيادة');

        // Increment by +1 via SemanticsAction.tap and verify state + persistence
        await _performSemanticTap(tester, 'إضافة أو زيادة');
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_adjust_value_text'))).data,
          equals('+1 يوم'),
        );
        expect(SettingsService.instance.hijriAdjustmentDays, equals(1));

        // Close dialog via SemanticsAction.tap on 'حفظ التعديل'
        await _performSemanticTap(tester, 'حفظ التعديل');
        expect(adjustDialog, findsNothing);

        // Banner reflects saved +1 adjustment on confirmedDate accurately
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_date_text'))).data,
          equals(_expectedHijriBanner(confirmedDate, adjustmentDays: 1)),
        );
        expect(find.text('تعديل الرؤية الشرعية محفوظ: +1 يوم'), findsOneWidget);

        expect(tester.takeException(), isNull);
        PrayerService.instance.stopLiveTicker();
        semantics.dispose();
      },
    );

    testWidgets(
      'HomeDateHeaderCard on /home opens HijriCalendarScreen cleanly at 360x800 2.0x and navigates back',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(360, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        appRouter.go('/home');
        await tester.pumpWidget(_buildRouterApp(textScale: 2.0));
        await tester.pumpAndSettle();

        final dateCard = find.byType(HomeDateHeaderCard);
        expect(dateCard, findsOneWidget);
        await tester.tap(dateCard);
        await tester.pumpAndSettle();

        expect(find.byType(HijriCalendarScreen), findsOneWidget);
        expect(find.text('التقويم الهجري والمناسبات'), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(HomeDateHeaderCard), findsOneWidget);

        expect(tester.takeException(), isNull);
        PrayerService.instance.stopLiveTicker();
        semantics.dispose();
      },
    );
  });
}
