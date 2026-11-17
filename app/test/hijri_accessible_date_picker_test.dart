import 'dart:io';
import 'dart:ui' show Tristate;
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

SemanticsNode _findSingleActionableNode(WidgetTester tester, String target) {
  final matches = <SemanticsNode>[];
  for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
    final data = node.getSemanticsData();
    if (data.label == target || data.tooltip == target) {
      matches.add(node);
    }
  }
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

SemanticsNode _findSingleActionableByPrefix(WidgetTester tester, String prefix) {
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
    reason: 'Expected exactly 1 actionable node starting with "$prefix" (got ${matches.length})',
  );
  return matches.single;
}

Future<void> _tapSemanticNode(WidgetTester tester, SemanticsNode node) async {
  tester.binding.pipelineOwner.semanticsOwner!.performAction(
    node.id,
    SemanticsAction.tap,
  );
  await tester.pumpAndSettle();
}

String _expectedHijriBanner(DateTime date, {int adjustmentDays = 0}) {
  final h = HijriDateHelper.toHijri(date, adjustmentDays: adjustmentDays);
  final monthName = HijriDateHelper.hijriMonths[h['month']! - 1];
  return '${h['day']} $monthName ${h['year']} هـ';
}

Future<void> _openCalendarAndDatePicker(
  WidgetTester tester, {
  required Size viewport,
  required double textScale,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = viewport;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  appRouter.go('/calendar');
  await tester.pumpWidget(_buildRouterApp(textScale: textScale));
  await tester.pumpAndSettle();

  await _reopenDatePicker(tester);
}

Future<void> _reopenDatePicker(WidgetTester tester) async {
  final listScrollable = find
      .descendant(
        of: find.byKey(const ValueKey('hijri_calendar_list_view')),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('hijri_pick_date_button')),
    200,
    scrollable: listScrollable,
  );
  await tester.pumpAndSettle();
  await _tapSemanticNode(tester, _findSingleActionableNode(tester, 'اختر تاريخاً'));
}

Future<void> _scrollCalendarToTop(WidgetTester tester) async {
  final calScrollable = find
      .descendant(
        of: find.byKey(const ValueKey('hijri_calendar_list_view')),
        matching: find.byType(Scrollable),
      )
      .first;
  tester.state<ScrollableState>(calScrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
}

void _assertDayCellTextUnclippedAt18spBaseline(
  WidgetTester tester, {
  required int day,
  required Rect dialogCardRect,
}) {
  final cellFinder = find.byKey(ValueKey('hijri_picker_day_$day'));
  final textFinder = find.byKey(ValueKey('hijri_picker_day_text_$day'));
  expect(cellFinder, findsOneWidget);
  expect(textFinder, findsOneWidget);

  final cellRect = tester.getRect(cellFinder);
  final textRect = tester.getRect(textFinder);
  final textWidget = tester.widget<Text>(textFinder);
  expect(textWidget.data, equals('$day'));
  expect(textWidget.overflow, isNot(TextOverflow.ellipsis));

  // Preserve stock theme bodyLarge 18.0sp baseline (no font shrinking below 18.0sp)
  final elem = tester.element(textFinder);
  final effectiveStyle = DefaultTextStyle.of(elem).style.merge(textWidget.style);
  expect(
    effectiveStyle.fontSize,
    greaterThanOrEqualTo(18.0),
    reason: 'Day "$day" must preserve 18.0sp bodyLarge baseline without font shrinking',
  );

  // Target >= 48x48 and strictly inside dialog width
  expect(cellRect.width, greaterThanOrEqualTo(48.0));
  expect(cellRect.height, greaterThanOrEqualTo(48.0));
  expect(cellRect.left, greaterThanOrEqualTo(dialogCardRect.left));
  expect(cellRect.right, lessThanOrEqualTo(dialogCardRect.right));

  // Rendered text rect strictly inside cell rect (no clipping)
  expect(textRect.left, greaterThanOrEqualTo(cellRect.left));
  expect(textRect.right, lessThanOrEqualTo(cellRect.right));
  expect(textRect.top, greaterThanOrEqualTo(cellRect.top));
  expect(textRect.bottom, lessThanOrEqualTo(cellRect.bottom));

  // Intrinsic unclipped TextPainter width at live MediaQuery.textScaler & inherited Cairo font must fit inside cell
  final painter = TextPainter(
    text: TextSpan(text: '$day', style: effectiveStyle),
    textDirection: TextDirection.rtl,
    textScaler: MediaQuery.textScalerOf(elem),
  )..layout();
  expect(
    painter.width,
    lessThanOrEqualTo(cellRect.width - 8.0),
    reason: 'Day "$day" intrinsic width (${painter.width}) must fit inside cell width (${cellRect.width})',
  );
  expect(
    textRect.width,
    greaterThanOrEqualTo(painter.width - 1.0),
    reason: 'Day "$day" rendered text width (${textRect.width}) must not clip intrinsic width (${painter.width})',
  );
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

  group('Repair 7: Large-text accessible calendar date picker', () {
    for (final viewport in const [Size(360, 800), Size(412, 915)]) {
      testWidgets(
        'Actual router /calendar picker at ${viewport.width.toInt()}x${viewport.height.toInt()} 1.0x retains native DatePickerDialog cleanly',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await _openCalendarAndDatePicker(
            tester,
            viewport: viewport,
            textScale: 1.0,
          );

          final pickerFinder = find.byType(DatePickerDialog);
          expect(pickerFinder, findsOneWidget);
          expect(
            MediaQuery.textScalerOf(tester.element(pickerFinder)).scale(1.0),
            closeTo(1.0, 0.001),
          );
          _findSingleActionableNode(tester, 'الإلغاء');
          _findSingleActionableNode(tester, 'حسنًا');

          await _tapSemanticNode(tester, _findSingleActionableNode(tester, 'الإلغاء'));
          expect(pickerFinder, findsNothing);
          expect(tester.takeException(), isNull);
          PrayerService.instance.stopLiveTicker();
          semantics.dispose();
        },
      );

      testWidgets(
        'Actual router /calendar picker at ${viewport.width.toInt()}x${viewport.height.toInt()} 2.0x preserves 18sp baseline, unclamped 2.0x, unellipsized header, and unclipped 2-digit days (10/11/18/28/30)',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final today = DateTime.now();
          await _openCalendarAndDatePicker(
            tester,
            viewport: viewport,
            textScale: 2.0,
          );

          final dialogFinder =
              find.byKey(const ValueKey('hijri_accessible_date_picker_dialog'));
          expect(dialogFinder, findsOneWidget);

          // Effective text scale must remain 2.0 (unclamped)
          expect(
            MediaQuery.textScalerOf(tester.element(dialogFinder)).scale(1.0),
            closeTo(2.0, 0.001),
          );

          final dialogCardRect = tester.getRect(
            find.descendant(of: dialogFinder, matching: find.byType(Material)).first,
          );
          expect(dialogCardRect.left, greaterThanOrEqualTo(0.0));
          expect(dialogCardRect.right, lessThanOrEqualTo(viewport.width));
          expect(dialogCardRect.top, greaterThanOrEqualTo(0.0));
          expect(dialogCardRect.bottom, lessThanOrEqualTo(viewport.height));

          // Full selected date header must be completely unellipsized and inside card width
          final headerFinder = find.byKey(const ValueKey('hijri_picker_selected_date_header'));
          final headerWidget = tester.widget<Text>(headerFinder);
          final expectedHeader =
              '${HijriDateHelper.getDayOfWeek(today)}، ${HijriDateHelper.getGregorianDateString(today)}';
          expect(headerWidget.data, equals(expectedHeader));
          expect(headerWidget.overflow, isNot(TextOverflow.ellipsis));
          expect(headerWidget.maxLines, isNull);
          final headerRect = tester.getRect(headerFinder);
          expect(headerRect.left, greaterThanOrEqualTo(dialogCardRect.left));
          expect(headerRect.right, lessThanOrEqualTo(dialogCardRect.right));

          // Measure actual geometry of key 2-digit days at 18sp baseline x 2.0x
          final pickerScrollable = find
              .descendant(
                of: find.byKey(const ValueKey('hijri_picker_scroll_view')),
                matching: find.byType(Scrollable),
              )
              .first;
          final daysInCurrentMonth = DateUtils.getDaysInMonth(today.year, today.month);
          final sampleDays = [10, 11, 18, 28, daysInCurrentMonth];
          for (final d in sampleDays) {
            await tester.scrollUntilVisible(
              find.byKey(ValueKey('hijri_picker_day_$d')),
              120,
              scrollable: pickerScrollable,
            );
            await tester.pumpAndSettle();
            _assertDayCellTextUnclippedAt18spBaseline(
              tester,
              day: d,
              dialogCardRect: dialogCardRect,
            );

            final dayNode = _findSingleActionableByPrefix(tester, '$d، ');
            expect(dayNode.getSemanticsData().flagsCollection.isButton, isTrue);
            expect(
              dayNode.getSemanticsData().flagsCollection.isSelected,
              equals(d == today.day ? Tristate.isTrue : Tristate.isFalse),
            );
          }

          // Select day 28 via SemanticsAction.tap -> selection state & header update immediately
          await _tapSemanticNode(tester, _findSingleActionableByPrefix(tester, '28، '));
          expect(
            _findSingleActionableByPrefix(tester, '28، ')
                .getSemanticsData()
                .flagsCollection
                .isSelected,
            equals(Tristate.isTrue),
          );
          final expected28Date = DateTime(today.year, today.month, 28);
          expect(
            tester.widget<Text>(headerFinder).data,
            equals(
              '${HijriDateHelper.getDayOfWeek(expected28Date)}، '
              '${HijriDateHelper.getGregorianDateString(expected28Date)}',
            ),
          );

          // Confirm via SemanticsAction.tap -> HijriCalendarScreen banner updates to exact Gregorian & Hijri date
          await _tapSemanticNode(tester, _findSingleActionableNode(tester, 'حسنًا'));
          expect(dialogFinder, findsNothing);

          await _scrollCalendarToTop(tester);
          expect(
            tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_date_text'))).data,
            equals(_expectedHijriBanner(expected28Date)),
          );
          expect(
            tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_gregorian_text'))).data,
            equals('الموافق ${HijriDateHelper.getGregorianDateString(expected28Date)}'),
          );

          // Real TOUCH day selection (day 10) + real TOUCH confirm ('حسنًا')
          await _reopenDatePicker(tester);
          final pickerScroll2 = find
              .descendant(
                of: find.byKey(const ValueKey('hijri_picker_scroll_view')),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('hijri_picker_day_10')),
            120,
            scrollable: pickerScroll2,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('hijri_picker_day_10')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('hijri_picker_confirm_button')));
          await tester.pumpAndSettle();
          expect(dialogFinder, findsNothing);

          final expected10Date = DateTime(today.year, today.month, 10);
          await _scrollCalendarToTop(tester);
          expect(
            tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_date_text'))).data,
            equals(_expectedHijriBanner(expected10Date)),
          );
          expect(
            tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_gregorian_text'))).data,
            equals('الموافق ${HijriDateHelper.getGregorianDateString(expected10Date)}'),
          );

          // Barrier tap dismiss & system back both preserve 10th
          await _reopenDatePicker(tester);
          await tester.tapAt(const Offset(6, 6));
          await tester.pumpAndSettle();
          expect(dialogFinder, findsNothing);

          await _reopenDatePicker(tester);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(dialogFinder, findsNothing);

          await _scrollCalendarToTop(tester);
          expect(
            tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_date_text'))).data,
            equals(_expectedHijriBanner(expected10Date)),
          );

          expect(tester.takeException(), isNull);
          PrayerService.instance.stopLiveTicker();
          semantics.dispose();
        },
      );
    }

    testWidgets(
      '360x800 2.0x parser handles Arabic-Indic & Eastern digits, leap/non-leap & 30-day validation, exact 1980-01-01..2050-01-01 bounds, disabled bound nav, year clamping, and keyboard viewInsets',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await _openCalendarAndDatePicker(
          tester,
          viewport: const Size(360, 800),
          textScale: 2.0,
        );

        final dialogFinder =
            find.byKey(const ValueKey('hijri_accessible_date_picker_dialog'));
        final inputField = find.byKey(const ValueKey('hijri_picker_date_input'));

        Future<void> switchToInput() async {
          final scroll = find
              .descendant(
                of: find.byKey(const ValueKey('hijri_picker_scroll_view')),
                matching: find.byType(Scrollable),
              )
              .first;
          tester.state<ScrollableState>(scroll).position.jumpTo(0);
          await tester.pumpAndSettle();
          await _tapSemanticNode(
            tester,
            _findSingleActionableNode(tester, 'التبديل إلى الإدخال'),
          );
          expect(inputField, findsOneWidget);
        }

        // 1. Arabic-Indic digits '١٠/٠٣/٢٠٢٧' normalize & confirm cleanly
        await switchToInput();
        await tester.enterText(inputField, '١٠/٠٣/٢٠٢٧');
        await tester.pumpAndSettle();
        await _tapSemanticNode(tester, _findSingleActionableNode(tester, 'حسنًا'));
        expect(dialogFinder, findsNothing);

        final mar10 = DateTime(2027, 3, 10);
        await _scrollCalendarToTop(tester);
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_gregorian_text'))).data,
          equals('الموافق ${HijriDateHelper.getGregorianDateString(mar10)}'),
        );

        // 2. Eastern Arabic-Indic digits '۱۰/۰۳/۲۰۲۷' normalize & confirm cleanly
        await _reopenDatePicker(tester);
        await switchToInput();
        await tester.enterText(inputField, '۱۰/۰۳/۲۰۲۷');
        await tester.pumpAndSettle();
        await _tapSemanticNode(tester, _findSingleActionableNode(tester, 'حسنًا'));
        expect(dialogFinder, findsNothing);

        // 3. Invalid dates rejected: non-leap 29/02/2027, 31/04/2027, before 1980 (31/12/1979), after 2050-01-01 (02/01/2050)
        await _reopenDatePicker(tester);
        await switchToInput();
        for (final badDate in const ['29/02/2027', '31/04/2027', '31/12/1979', '02/01/2050']) {
          await tester.enterText(inputField, badDate);
          await tester.pumpAndSettle();
          await _tapSemanticNode(tester, _findSingleActionableNode(tester, 'حسنًا'));
          expect(
            dialogFinder,
            findsOneWidget,
            reason: 'Invalid/out-of-bounds date "$badDate" must be rejected',
          );
          expect(find.textContaining('يرجى إدخال تاريخ صحيح'), findsOneWidget);
        }

        // 4. Keyboard viewInsets (300px) in Input mode at 360x800 2.0x:
        //    Scroll input into view while keyboard stays open, assert actual EditableText & full TextField
        //    sit strictly inside visible ScrollView viewport and above pinned confirm button,
        //    then touch-focus + edit + touch-confirm leap day 29/02/2028 while keyboard remains open!
        tester.view.viewInsets = const FakeViewPadding(bottom: 300.0);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();

        final scrollViewFinder = find.byKey(const ValueKey('hijri_picker_scroll_view'));
        final kbPickerScrollable = find
            .descendant(of: scrollViewFinder, matching: find.byType(Scrollable))
            .first;
        final kbScrollState = tester.state<ScrollableState>(kbPickerScrollable);
        kbScrollState.position.jumpTo(kbScrollState.position.maxScrollExtent);
        await tester.pumpAndSettle();

        final scrollViewportRect = tester.getRect(scrollViewFinder);
        final cardWithKeyboard = tester.getRect(
          find.descendant(of: dialogFinder, matching: find.byType(Material)).first,
        );
        final confirmBtnWithKb =
            tester.getRect(find.byKey(const ValueKey('hijri_picker_confirm_button')));
        expect(cardWithKeyboard.bottom, lessThanOrEqualTo(500.0));
        expect(confirmBtnWithKb.bottom, lessThanOrEqualTo(500.0));

        final editableFinder = find.descendant(of: inputField, matching: find.byType(EditableText));
        expect(editableFinder, findsOneWidget);
        final editableRectBeforeTap = tester.getRect(editableFinder);
        expect(editableRectBeforeTap.top, greaterThanOrEqualTo(scrollViewportRect.top - 1.0));
        expect(editableRectBeforeTap.bottom, lessThanOrEqualTo(scrollViewportRect.bottom + 1.0));
        expect(editableRectBeforeTap.bottom, lessThanOrEqualTo(confirmBtnWithKb.top + 1.0));

        // Real touch focus + edit while 300px keyboard stays retained
        await tester.tap(editableFinder);
        await tester.pumpAndSettle();
        await tester.enterText(inputField, '29/02/2028');
        await tester.pumpAndSettle();

        final editableRectAfterEdit = tester.getRect(editableFinder);
        final inputRectAfterEdit = tester.getRect(inputField);
        expect(editableRectAfterEdit.top, greaterThanOrEqualTo(scrollViewportRect.top - 1.0));
        expect(editableRectAfterEdit.bottom, lessThanOrEqualTo(scrollViewportRect.bottom + 1.0));
        expect(editableRectAfterEdit.bottom, lessThanOrEqualTo(confirmBtnWithKb.top + 1.0));
        expect(inputRectAfterEdit.top, greaterThanOrEqualTo(scrollViewportRect.top - 1.0));
        expect(inputRectAfterEdit.bottom, lessThanOrEqualTo(scrollViewportRect.bottom + 1.0));

        await tester.tap(find.byKey(const ValueKey('hijri_picker_confirm_button')));
        await tester.pumpAndSettle();
        expect(dialogFinder, findsNothing);

        tester.view.resetViewInsets();
        await tester.pumpAndSettle();

        final leapDay2028 = DateTime(2028, 2, 29);
        await _scrollCalendarToTop(tester);
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_gregorian_text'))).data,
          equals('الموافق ${HijriDateHelper.getGregorianDateString(leapDay2028)}'),
        );

        // 5. Year selection clamping: from 29/02/2028 -> pick year 2027 -> clamps to 28/02/2027!
        await _reopenDatePicker(tester);
        final pickerScroll = find
            .descendant(
              of: find.byKey(const ValueKey('hijri_picker_scroll_view')),
              matching: find.byType(Scrollable),
            )
            .first;
        await _tapSemanticNode(tester, _findSingleActionableByPrefix(tester, 'اختيار العام، '));
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('hijri_picker_year_2027')),
          160,
          scrollable: pickerScroll,
        );
        await tester.pumpAndSettle();
        await _tapSemanticNode(tester, _findSingleActionableNode(tester, '2027'));
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_picker_selected_date_header'))).data,
          contains('28 فبراير 2027 م'),
        );

        // Also test Jan 31 -> Next Month (Feb) -> pick year 2026 -> clamps day 31 -> Feb 28!
        tester.state<ScrollableState>(pickerScroll).position.jumpTo(0);
        await tester.pumpAndSettle();
        await _tapSemanticNode(tester, _findSingleActionableNode(tester, 'الشهر السابق')); // Jan 2027
        final dialogCardRect = tester.getRect(
          find.descendant(of: dialogFinder, matching: find.byType(Material)).first,
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('hijri_picker_day_31')),
          140,
          scrollable: pickerScroll,
        );
        await tester.pumpAndSettle();
        _assertDayCellTextUnclippedAt18spBaseline(
          tester,
          day: 31,
          dialogCardRect: dialogCardRect,
        );
        await _tapSemanticNode(tester, _findSingleActionableByPrefix(tester, '31، '));

        tester.state<ScrollableState>(pickerScroll).position.jumpTo(0);
        await tester.pumpAndSettle();
        await _tapSemanticNode(tester, _findSingleActionableNode(tester, 'الشهر التالي')); // Feb 2027
        await _tapSemanticNode(tester, _findSingleActionableByPrefix(tester, 'اختيار العام، '));
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('hijri_picker_year_2026')),
          160,
          scrollable: pickerScroll,
        );
        await tester.pumpAndSettle();
        await _tapSemanticNode(tester, _findSingleActionableNode(tester, '2026'));
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_picker_selected_date_header'))).data,
          contains('28 فبراير 2026 م'),
        );

        // 6. Exact lower bound 01/01/1980 accepted & prev-month button disabled at bound
        await switchToInput();
        await tester.enterText(inputField, '01/01/1980');
        await tester.pumpAndSettle();
        await _tapSemanticNode(tester, _findSingleActionableNode(tester, 'التبديل إلى التقويم'));
        final prevMonthBtn = tester.widget<ButtonStyleButton>(
          find.byKey(const ValueKey('hijri_picker_prev_month_button')),
        );
        expect(prevMonthBtn.onPressed, isNull, reason: 'Prev month must be disabled at Jan 1980');
        await _tapSemanticNode(tester, _findSingleActionableNode(tester, 'حسنًا'));
        expect(dialogFinder, findsNothing);

        await _scrollCalendarToTop(tester);
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_gregorian_text'))).data,
          equals('الموافق ${HijriDateHelper.getGregorianDateString(DateTime(1980, 1, 1))}'),
        );

        // 7. Exact upper bound 01/01/2050 accepted, next-month button disabled, day 2 disabled (NOT whole year 2050!)
        await _reopenDatePicker(tester);
        await switchToInput();
        await tester.enterText(inputField, '01/01/2050');
        await tester.pumpAndSettle();
        await _tapSemanticNode(tester, _findSingleActionableNode(tester, 'التبديل إلى التقويم'));
        final nextMonthBtn = tester.widget<ButtonStyleButton>(
          find.byKey(const ValueKey('hijri_picker_next_month_button')),
        );
        expect(nextMonthBtn.onPressed, isNull, reason: 'Next month must be disabled at Jan 2050');
        final day1Ink = tester.widget<InkWell>(find.byKey(const ValueKey('hijri_picker_day_1')));
        final day2Ink = tester.widget<InkWell>(find.byKey(const ValueKey('hijri_picker_day_2')));
        expect(day1Ink.onTap, isNotNull, reason: 'Jan 1, 2050 must be enabled');
        expect(day2Ink.onTap, isNull, reason: 'Jan 2, 2050 must be disabled (lastDate is 2050-01-01)');

        await _tapSemanticNode(tester, _findSingleActionableNode(tester, 'حسنًا'));
        expect(dialogFinder, findsNothing);

        await _scrollCalendarToTop(tester);
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('hijri_banner_gregorian_text'))).data,
          equals('الموافق ${HijriDateHelper.getGregorianDateString(DateTime(2050, 1, 1))}'),
        );

        expect(tester.takeException(), isNull);
        PrayerService.instance.stopLiveTicker();
        semantics.dispose();
      },
    );
  });
}
