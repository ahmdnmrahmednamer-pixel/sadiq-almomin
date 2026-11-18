import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/router.dart';
import 'package:almomin/core/services/daily_wird_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/prayer_tracker_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/prayer/prayer_tracker_screen.dart';

Future<void> _loadBundledFonts() async {
  Future<void> loadFont(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      final file = File(path);
      if (file.existsSync()) {
        final bytes = await file.readAsBytes();
        loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      }
    }
    await loader.load();
  }

  await loadFont('Cairo', ['assets/fonts/Cairo-Regular.ttf']);
  await loadFont('Roboto', ['assets/fonts/Cairo-Regular.ttf']);
  await loadFont('Amiri', [
    'assets/fonts/Amiri-Regular.ttf',
    'assets/fonts/Amiri-Bold.ttf',
  ]);
  await loadFont('MaterialIcons', [
    'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
  ]);
}

Future<void> _resetServices({bool seedMissedReasons = false}) async {
  SharedPreferences.setMockInitialValues({
    'app_language': 'ar',
    'has_completed_onboarding': true,
    'show_tutorial_screens': false,
  });
  IslamicAudioService.instance.disableNativePlayerForTesting = true;
  await SettingsService.instance.init();
  await PrayerTrackerService.instance.init(forceReload: true);
  await SunanRawatibService.instance.init();
  await DailyWirdService.instance.init();

  if (seedMissedReasons) {
    final today = DateTime.now();
    await PrayerTrackerService.instance.setPrayerFormStatus(
      prayerNameAr: 'الفجر',
      status: PrayerPerformanceStatus.missed,
      reasonText: 'نسيان ضبط المنبه أو كتم صوت الهاتف',
      date: today,
    );
    await PrayerTrackerService.instance.setPrayerFormStatus(
      prayerNameAr: 'الظهر',
      status: PrayerPerformanceStatus.lateQada,
      reasonText: 'التواجد خارج المنزل أو في المواصلات',
      date: today,
    );
    await PrayerTrackerService.instance.setPrayerFormStatus(
      prayerNameAr: 'العصر',
      status: PrayerPerformanceStatus.onTimeCongregation,
      date: today,
    );
  }
}

Future<void> _pumpPrayerTrackerViaRouter(
  WidgetTester tester, {
  required Size size,
  required double textScale,
  ValueNotifier<double>? keyboardInsetNotifier,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;

  final insetNotifier = keyboardInsetNotifier ?? ValueNotifier<double>(0.0);
  appRouter.go('/prayer-tracker');
  await tester.pumpWidget(
    ValueListenableBuilder<double>(
      valueListenable: insetNotifier,
      builder: (context, bottomInset, child) {
        return MediaQuery(
          data: MediaQueryData(
            size: size,
            devicePixelRatio: 1.0,
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: bottomInset),
          ),
          child: child!,
        );
      },
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: appRouter,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(PrayerTrackerScreen), findsOneWidget);
}

/// Scrolls [target] into view and asserts FULL horizontal and vertical
/// containment inside [scrollViewFinder]'s visible viewport.
/// Targets taller than the viewport must be verified separately.
Future<Rect> _scrollToAndAssertVisibleInViewport(
  WidgetTester tester,
  Finder target, {
  required double screenWidth,
  Finder? scrollViewFinder,
  double? maxAllowedBottom,
  double alignment = 0.3,
  String? label,
}) async {
  expect(target, findsAtLeastNWidgets(1), reason: 'Missing target: $label');
  final element = tester.element(target.first);
  await Scrollable.ensureVisible(element, alignment: alignment);
  await tester.pumpAndSettle();

  final svFinder = scrollViewFinder ?? find.byType(SingleChildScrollView).first;
  final viewportRect = tester.getRect(svFinder);
  final rect = tester.getRect(target.first);

  expect(
    rect.left,
    greaterThanOrEqualTo(viewportRect.left - 0.5),
    reason: '${label ?? target} clipped on left: $rect vs $viewportRect',
  );
  expect(
    rect.right,
    lessThanOrEqualTo(screenWidth + 0.5),
    reason: '${label ?? target} clipped on right ($screenWidth): $rect',
  );
  expect(
    rect.height,
    lessThanOrEqualTo(viewportRect.height + 0.5),
    reason:
        '${label ?? target} taller than viewport (${rect.height} > ${viewportRect.height}); use tall-target check',
  );
  expect(
    rect.top,
    greaterThanOrEqualTo(viewportRect.top - 0.5),
    reason:
        '${label ?? target} top clipped above viewport: $rect vs $viewportRect',
  );
  expect(
    rect.bottom,
    lessThanOrEqualTo(viewportRect.bottom + 0.5),
    reason:
        '${label ?? target} bottom clipped below viewport: $rect vs $viewportRect',
  );
  if (maxAllowedBottom != null) {
    expect(
      rect.bottom,
      lessThanOrEqualTo(maxAllowedBottom + 0.5),
      reason:
          '${label ?? target} extends below keyboard/inset bound ($maxAllowedBottom): $rect',
    );
  }
  return rect;
}

/// Verifies a potentially tall text block is horizontally contained and that
/// both its top edge and bottom edge can be scrolled into the visible viewport.
Future<void> _assertTallBlockScrollReachable(
  WidgetTester tester,
  Finder target, {
  required double screenWidth,
  Finder? scrollViewFinder,
  required String label,
}) async {
  expect(target, findsAtLeastNWidgets(1), reason: 'Missing tall target: $label');
  final svFinder = scrollViewFinder ?? find.byType(SingleChildScrollView).first;
  final viewportRect = tester.getRect(svFinder);

  await Scrollable.ensureVisible(tester.element(target.first), alignment: 0.0);
  await tester.pumpAndSettle();
  final topRect = tester.getRect(target.first);
  expect(topRect.left, greaterThanOrEqualTo(viewportRect.left - 0.5));
  expect(topRect.right, lessThanOrEqualTo(screenWidth + 0.5));
  expect(
    topRect.top,
    greaterThanOrEqualTo(viewportRect.top - 0.5),
    reason: '$label top edge could not be scrolled into viewport: $topRect',
  );

  await Scrollable.ensureVisible(tester.element(target.first), alignment: 1.0);
  await tester.pumpAndSettle();
  final bottomRect = tester.getRect(target.first);
  expect(
    bottomRect.bottom,
    lessThanOrEqualTo(viewportRect.bottom + 0.5),
    reason: '$label bottom edge could not be scrolled into viewport: $bottomRect',
  );
}

void _performSemanticTap(WidgetTester tester, Finder finder, String label) {
  expect(finder, findsOneWidget, reason: 'Expected unique semantic node: $label');
  final node = tester.getSemantics(finder);
  expect(
    node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
    isTrue,
    reason: 'Semantic node "$label" must support SemanticsAction.tap',
  );
  tester.binding.pipelineOwner.semanticsOwner!
      .performAction(node.id, ui.SemanticsAction.tap);
}

int _countSemanticOccurrences(SemanticsNode root, String substring) {
  var count = 0;
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    count += substring.allMatches(data.label).length;
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadBundledFonts();
  });

  tearDown(() {
    PrayerService.instance.stopLiveTicker();
  });

  testWidgets(
    'PrayerTracker preserves 1.0x layout and religious wording at 360x800 and 412x915',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      for (final size in const [Size(360, 800), Size(412, 915)]) {
        await _resetServices(seedMissedReasons: true);
        await _pumpPrayerTrackerViaRouter(tester, size: size, textScale: 1.0);

        final screenCtx = tester.element(find.byType(PrayerTrackerScreen));
        expect(MediaQuery.textScalerOf(screenCtx).scale(1.0), equals(1.0));

        // AppBar stays single-line kToolbarHeight at 1.0x
        final appBar = tester.widget<AppBar>(find.byType(AppBar));
        expect(appBar.toolbarHeight, equals(kToolbarHeight));

        // Exact religious dedication banner & Hadith preserved
        expect(
          find.text(
            'حافظ على صلواتك في أوقاتها 🤲 «إِنَّ الصَّلَاةَ كَانَتْ عَلَى الْمُؤْمِنِينَ كِتَاباً مَوْقُوتاً»',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'عن أم حبيبة رضي الله عنها قالت: سمعت رسول الله ﷺ يقول: «مَنْ صَلَّى فِي يَوْمٍ وَلَيْلَةٍ ثِنْتَيْ عَشْرَةَ رَكْعَةً بُنِيَ لَهُ بَيْتٌ فِي الْجَنَّةِ: أَرْبَعًا قَبْلَ الظُّهْرِ، وَرَكْعَتَيْنِ بَعْدَهَا، وَرَكْعَتَيْنِ بَعْدَ الْمَغْرِبِ، وَرَكْعَتَيْنِ بَعْدَ الْعِشَاءِ، وَرَكْعَتَيْنِ قَبْلَ صَلَاةِ الْغَدَاةِ (الفجر)» [رواه مسلم].',
          ),
          findsOneWidget,
        );

        // 7-day strip stays single horizontal row at 1.0x
        final recentDays = PrayerTrackerService.instance.getRecent7Days();
        final dayTops = <double>{};
        for (final day in recentDays) {
          final dayNum = day.dateStr.split('-').last;
          final rect = tester.getRect(find.text(dayNum).first);
          dayTops.add(rect.top.roundToDouble());
        }
        expect(
          dayTops.length,
          equals(1),
          reason: 'Expected single-row 7-day strip at 1.0x on $size',
        );

        // Progress card header stays single row at 1.0x
        final progressTitleRect =
            tester.getRect(find.text('إنجاز اليوم في الصلاة'));
        final progressCountRect = tester.getRect(find.text('2 من 5 صلوات'));
        expect(
          (progressTitleRect.top - progressCountRect.top).abs(),
          lessThanOrEqualTo(12.0),
          reason: 'Progress header should remain single-row at 1.0x on $size',
        );

        // Weekly diagnostic 4 stat tiles stay 4-column single row at 1.0x
        await _scrollToAndAssertVisibleInViewport(
          tester,
          find.text('صليت في الأسبوع'),
          screenWidth: size.width,
          label: 'weekly stat 1 ($size 1.0x)',
        );
        final stat1Rect = tester.getRect(find.text('صليت في الأسبوع'));
        final stat2Rect = tester.getRect(find.text('في وقتها'));
        final stat3Rect = tester.getRect(find.text('قضاء'));
        final stat4Rect = tester.getRect(find.text('فاتتك / مسجلة فائتة'));
        expect((stat1Rect.top - stat2Rect.top).abs(), lessThanOrEqualTo(24.0));
        expect((stat2Rect.top - stat3Rect.top).abs(), lessThanOrEqualTo(24.0));
        expect((stat3Rect.top - stat4Rect.top).abs(), lessThanOrEqualTo(24.0));

        expect(tester.takeException(), isNull, reason: 'Zero errors at 1.0x on $size');
      }
    },
  );

  testWidgets(
    'PrayerTracker renders without overflow or clipping at 2.0x on 360x800 and 412x915 with full viewport containment',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      try {
        for (final size in const [Size(360, 800), Size(412, 915)]) {
          await _resetServices(seedMissedReasons: true);
          await _pumpPrayerTrackerViaRouter(tester, size: size, textScale: 2.0);

          // Confirm effective 2.0x text scale is NOT clamped
          final screenCtx = tester.element(find.byType(PrayerTrackerScreen));
          expect(MediaQuery.textScalerOf(screenCtx).scale(1.0), equals(2.0));

          // AppBar title is multi-line, non-ellipsized, within AppBar bounds
          final appBarFinder = find.byType(AppBar);
          final appBarRect = tester.getRect(appBarFinder);
          final titleFinder = find.text('سجل متابعة الصلوات والسنن');
          final titleWidget = tester.widget<Text>(titleFinder);
          expect(titleWidget.overflow, isNot(TextOverflow.ellipsis));
          final titleRect = tester.getRect(titleFinder);
          expect(titleRect.left, greaterThanOrEqualTo(0.0));
          expect(titleRect.right, lessThanOrEqualTo(size.width));
          expect(titleRect.bottom, lessThanOrEqualTo(appBarRect.bottom + 0.5));

          final alarmBtnRect = tester.getRect(
            find.byTooltip('منبّه الاستعداد للفجر وقيام الليل'),
          );
          expect(alarmBtnRect.width, greaterThanOrEqualTo(48.0));
          expect(alarmBtnRect.height, greaterThanOrEqualTo(48.0));
          expect(
            titleRect.overlaps(alarmBtnRect),
            isFalse,
            reason: 'AppBar title must not overlap alarm action on $size 2.0x',
          );

          // Verify date navigation buttons >= 48x48 and fully contained in viewport
          await _scrollToAndAssertVisibleInViewport(
            tester,
            find.byTooltip('اليوم السابق'),
            screenWidth: size.width,
            label: 'prev day button ($size 2.0x)',
          );
          final prevRect = tester.getRect(find.byTooltip('اليوم السابق'));
          final nextRect = tester.getRect(find.byTooltip('اليوم التالي'));
          expect(prevRect.width, greaterThanOrEqualTo(48.0));
          expect(prevRect.height, greaterThanOrEqualTo(48.0));
          expect(nextRect.width, greaterThanOrEqualTo(48.0));
          expect(nextRect.height, greaterThanOrEqualTo(48.0));

          // Verify all 7 weekly strip day tiles are fully contained, >= 48x48, and unclipped
          final recentDays = PrayerTrackerService.instance.getRecent7Days();
          for (final day in recentDays) {
            final dayNum = day.dateStr.split('-').last;
            final semLabel =
                'يوم $dayNum، ${day.completedObligatoryCount} من 5 صلوات';
            final tileFinder = find.bySemanticsLabel(semLabel);
            final tileRect = await _scrollToAndAssertVisibleInViewport(
              tester,
              tileFinder,
              screenWidth: size.width,
              label: 'weekly strip tile $semLabel ($size 2.0x)',
            );
            expect(tileRect.width, greaterThanOrEqualTo(48.0));
            expect(tileRect.height, greaterThanOrEqualTo(48.0));
          }

          // Scroll through all small titles/tiles/reasons asserting FULL viewport containment
          for (final textToCheck in const [
            'حافظ على صلواتك في أوقاتها 🤲 «إِنَّ الصَّلَاةَ كَانَتْ عَلَى الْمُؤْمِنِينَ كِتَاباً مَوْقُوتاً»',
            'إنجاز اليوم في الصلاة',
            '2 من 5 صلوات',
            'السنن الرواتب (12 ركعة):',
            '0 / 12 ركعة',
            'صلاة الفجر',
            'صلاة الظهر',
            'صلاة العصر',
            'صلاة المغرب',
            'صلاة العشاء',
            'قيام الليل والتهجد',
            'فضل السنن الرواتب الاثنتي عشرة ركعة',
            'التقرير الأسبوعي وسجل تشخيص أسباب فوات الصلاة',
            'صليت في الأسبوع',
            'في وقتها',
            'قضاء',
            'فاتتك / مسجلة فائتة',
            'نسيان ضبط المنبه أو كتم صوت الهاتف (1 مرات)',
            'التواجد خارج المنزل أو في المواصلات (1 مرات)',
            '💡 خطة العلاج العملية المقترحة لك:',
          ]) {
            await _scrollToAndAssertVisibleInViewport(
              tester,
              find.text(textToCheck),
              screenWidth: size.width,
              label: '$textToCheck ($size 2.0x)',
            );
          }

          // Explicit tall-block check for full Umm Habiba Hadith text
          await _assertTallBlockScrollReachable(
            tester,
            find.textContaining('عن أم حبيبة رضي الله عنها'),
            screenWidth: size.width,
            label: 'Hadith body ($size 2.0x)',
          );

          // Verify 2x2 weekly stat grid layout at 2.0x (row 1 above row 2)
          await _scrollToAndAssertVisibleInViewport(
            tester,
            find.text('صليت في الأسبوع'),
            screenWidth: size.width,
            label: 'weekly grid top ($size 2.0x)',
          );
          final topRowRect = tester.getRect(find.text('صليت في الأسبوع'));
          final bottomRowRect = tester.getRect(find.text('فاتتك / مسجلة فائتة'));
          expect(
            bottomRowRect.top,
            greaterThan(topRowRect.bottom),
            reason: 'Weekly stats should form 2x2 rows at 2.0x on $size',
          );

          expect(tester.takeException(), isNull, reason: 'Zero errors at 2.0x on $size');
        }
      } finally {
        semanticsHandle.dispose();
      }
    },
  );

  testWidgets(
    'PrayerTracker real touch and SemanticsAction.tap actions update counts, reason sheet, storage, and date at 360x800 and 412x915 2.0x',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      try {
        for (final size in const [Size(360, 800), Size(412, 915)]) {
          await _resetServices(seedMissedReasons: false);
          await _pumpPrayerTrackerViaRouter(tester, size: size, textScale: 2.0);

          expect(PrayerTrackerService.instance.todayRecord.completedObligatoryCount, equals(0));
          expect(find.text('0 من 5 صلوات'), findsOneWidget);

          // 1) Real TOUCH toggle of Fajr obligatory checkbox
          final fajrFinder = find.text('صلاة الفجر');
          await _scrollToAndAssertVisibleInViewport(
            tester,
            fajrFinder,
            screenWidth: size.width,
            label: 'Fajr tile',
          );
          await tester.tap(fajrFinder);
          await tester.pumpAndSettle();

          expect(PrayerTrackerService.instance.todayRecord.fajr, isTrue);
          expect(PrayerTrackerService.instance.todayRecord.completedObligatoryCount, equals(1));
          expect(find.text('1 من 5 صلوات'), findsOneWidget);

          // 2) Real TOUCH toggle of Fajr Sunnah checkbox -> Rawatib 2/12
          final fajrSunnahFinder = find.text('سنة الفجر القبلية (ركعتان مؤكدتان)');
          await _scrollToAndAssertVisibleInViewport(
            tester,
            fajrSunnahFinder,
            screenWidth: size.width,
            label: 'Fajr sunnah tile',
          );
          await tester.tap(fajrSunnahFinder);
          await tester.pumpAndSettle();

          expect(PrayerTrackerService.instance.todayRecord.fajrSunnah, isTrue);
          expect(PrayerTrackerService.instance.todayRecord.completedRawatibRakats, equals(2));
          expect(find.text('2 / 12 ركعة'), findsOneWidget);

          // 3) Real SemanticsAction.tap on Dhuhr "في وقتها" unique semantic chip
          final dhuhrOnTimeFinder = find.bySemanticsLabel('صلاة الظهر - في وقتها');
          await _scrollToAndAssertVisibleInViewport(
            tester,
            dhuhrOnTimeFinder,
            screenWidth: size.width,
            label: 'Dhuhr on-time chip',
          );
          _performSemanticTap(tester, dhuhrOnTimeFinder, 'صلاة الظهر - في وقتها');
          await tester.pumpAndSettle();

          expect(PrayerTrackerService.instance.todayRecord.dhuhr, isTrue);
          expect(
            PrayerTrackerService.instance.todayRecord.getPrayerStatus('الظهر'),
            equals(PrayerPerformanceStatus.onTimeCongregation),
          );
          expect(PrayerTrackerService.instance.todayRecord.completedObligatoryCount, equals(2));
          expect(find.text('2 من 5 صلوات'), findsOneWidget);
          expect(
            tester.getSemantics(dhuhrOnTimeFinder).getSemanticsData().flagsCollection.isSelected,
            equals(ui.Tristate.isTrue),
          );

          // 4) Real SemanticsAction.tap on Asr "فاتتني" -> Reason Entry sheet
          final asrMissedFinder = find.bySemanticsLabel('صلاة العصر - فاتتني');
          await _scrollToAndAssertVisibleInViewport(
            tester,
            asrMissedFinder,
            screenWidth: size.width,
            label: 'Asr missed chip',
          );
          _performSemanticTap(tester, asrMissedFinder, 'صلاة العصر - فاتتني');
          await tester.pumpAndSettle();

          expect(find.text('تسجيل سبب فوات صلاة العصر'), findsOneWidget);
          final modalScrollFinder = find.byType(SingleChildScrollView).last;

          // Verify long quick reason pill fits fully inside modal viewport & >= 48px height
          const chosenReason = 'التسويف وتأجيل الصلاة لآخر الوقت';
          final quickReasonFinder = find.bySemanticsLabel(chosenReason);
          final reasonRect = await _scrollToAndAssertVisibleInViewport(
            tester,
            quickReasonFinder,
            screenWidth: size.width,
            scrollViewFinder: modalScrollFinder,
            label: 'quick reason pill ($size)',
          );
          expect(reasonRect.height, greaterThanOrEqualTo(48.0));

          // Activate quick reason via SemanticsAction.tap
          _performSemanticTap(tester, quickReasonFinder, chosenReason);
          await tester.pumpAndSettle();
          expect(
            tester.getSemantics(quickReasonFinder).getSemanticsData().flagsCollection.isSelected,
            equals(ui.Tristate.isTrue),
          );

          // Scroll to & assert FULL containment of Save button, then activate via SemanticsAction.tap
          final saveFinder = find.text('حفظ الحالة والسبب في سجل المحاسبة الأسبوعي');
          final saveBtnFinder = find.ancestor(
            of: saveFinder,
            matching: find.byType(ElevatedButton),
          );
          final saveRect = await _scrollToAndAssertVisibleInViewport(
            tester,
            saveBtnFinder,
            screenWidth: size.width,
            scrollViewFinder: modalScrollFinder,
            alignment: 0.8,
            label: 'save reason button ($size)',
          );
          expect(saveRect.height, greaterThanOrEqualTo(48.0));
          _performSemanticTap(tester, saveBtnFinder, 'Save reason button');
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 400));

          // Verify state, visible reason banner (full containment), and persistent storage reload
          expect(
            PrayerTrackerService.instance.todayRecord.getPrayerStatus('العصر'),
            equals(PrayerPerformanceStatus.missed),
          );
          expect(
            PrayerTrackerService.instance.todayRecord.getReasonForPrayer('العصر'),
            equals(chosenReason),
          );
          await _scrollToAndAssertVisibleInViewport(
            tester,
            find.text('📌 سبب عدم الصلاة في وقتها: $chosenReason'),
            screenWidth: size.width,
            label: 'saved Asr reason banner ($size)',
          );
          await PrayerTrackerService.instance.init(forceReload: true);
          expect(PrayerTrackerService.instance.todayRecord.completedObligatoryCount, equals(2));
          expect(PrayerTrackerService.instance.todayRecord.completedRawatibRakats, equals(2));
          expect(
            PrayerTrackerService.instance.todayRecord.getReasonForPrayer('العصر'),
            equals(chosenReason),
          );

          // 5) Real SemanticsAction.tap on Previous Day & Weekly Strip return to Today
          final prevBtn = find.byTooltip('اليوم السابق');
          await _scrollToAndAssertVisibleInViewport(
            tester,
            prevBtn,
            screenWidth: size.width,
            label: 'prev day button',
          );
          final todayKey = PrayerTrackerService.formatDateKey(DateTime.now());
          final yesterdayKey = PrayerTrackerService.formatDateKey(
            DateTime.now().subtract(const Duration(days: 1)),
          );
          expect(find.text('اليوم ($todayKey)'), findsOneWidget);

          _performSemanticTap(tester, prevBtn, 'اليوم السابق');
          await tester.pumpAndSettle();
          expect(find.text(yesterdayKey), findsOneWidget);

          // Tap today's weekly strip tile via SemanticsAction.tap to return to today
          final todayDayNum = todayKey.split('-').last;
          final todayTileLabel = 'يوم $todayDayNum، 2 من 5 صلوات';
          final todayTileFinder = find.bySemanticsLabel(todayTileLabel);
          await _scrollToAndAssertVisibleInViewport(
            tester,
            todayTileFinder,
            screenWidth: size.width,
            label: todayTileLabel,
          );
          _performSemanticTap(tester, todayTileFinder, todayTileLabel);
          await tester.pumpAndSettle();
          expect(find.text('اليوم ($todayKey)'), findsOneWidget);
          expect(
            tester.getSemantics(todayTileFinder).getSemanticsData().flagsCollection.isSelected,
            equals(ui.Tristate.isTrue),
          );

          expect(
            tester.takeException(),
            isNull,
            reason: 'Zero errors across full interaction flow on $size',
          );
        }
      } finally {
        semanticsHandle.dispose();
      }
    },
  );

  testWidgets(
    'Reason modal EditableText exposes unique contextual semantic label/value and supports touch focus, edit, save, and reload with 300px keyboard insets at 360x800 and 412x915 2.0x',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      try {
        for (final size in const [Size(360, 800), Size(412, 915)]) {
          final keyboardInset = ValueNotifier<double>(0.0);
          addTearDown(keyboardInset.dispose);

          await _resetServices(seedMissedReasons: false);
          await _pumpPrayerTrackerViaRouter(
            tester,
            size: size,
            textScale: 2.0,
            keyboardInsetNotifier: keyboardInset,
          );

          // Open Maghrib Qada reason modal via SemanticsAction.tap
          final maghribQadaChip = find.bySemanticsLabel('صلاة المغرب - قضاء');
          await _scrollToAndAssertVisibleInViewport(
            tester,
            maghribQadaChip,
            screenWidth: size.width,
            label: 'Maghrib qada chip ($size)',
          );
          _performSemanticTap(tester, maghribQadaChip, 'صلاة المغرب - قضاء');
          await tester.pumpAndSettle();

          const expectedFieldLabel = 'أنا لم أصلِّ / أخرت صلاة المغرب بسبب...';
          const customReason = 'تأخرت بسبب الزحام الشديد في الطريق';
          final modalScrollFinder = find.byType(SingleChildScrollView).last;

          // Visible label text is preserved and unclipped (no floating ellipsis)
          await _scrollToAndAssertVisibleInViewport(
            tester,
            find.text(expectedFieldLabel),
            screenWidth: size.width,
            scrollViewFinder: modalScrollFinder,
            label: 'visible field label ($size)',
          );

          // Actual EditableText exposes explicit contextual semantic label WITHOUT duplicated speech
          final editableFinder = find.byType(EditableText);
          expect(editableFinder, findsOneWidget);
          final editableSemBefore =
              tester.getSemantics(editableFinder).getSemanticsData();
          expect(
            editableSemBefore.flagsCollection.isTextField,
            isTrue,
            reason: 'EditableText must expose textField semantics on $size',
          );
          expect(
            editableSemBefore.label,
            contains(expectedFieldLabel),
            reason:
                'EditableText semantic label must include contextual label on $size (got "${editableSemBefore.label}")',
          );
          expect(
            expectedFieldLabel.allMatches(editableSemBefore.label).length,
            equals(1),
            reason: 'EditableText label must not duplicate speech on $size',
          );
          final rootSemantics =
              tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
          expect(
            _countSemanticOccurrences(rootSemantics, expectedFieldLabel),
            equals(1),
            reason:
                'Contextual field label must appear exactly once in semantics tree (no duplicate speech) on $size',
          );

          // Simulate 300px on-screen keyboard retained during touch focus, edit, and save
          const double kbHeight = 300.0;
          final double keyboardTop = size.height - kbHeight;
          keyboardInset.value = kbHeight;
          await tester.pumpAndSettle();

          // Scroll TextField fully into modal viewport & strictly above 300px keyboard
          final textFieldFinder = find.byType(TextField);
          await _scrollToAndAssertVisibleInViewport(
            tester,
            textFieldFinder,
            screenWidth: size.width,
            scrollViewFinder: modalScrollFinder,
            maxAllowedBottom: keyboardTop,
            alignment: 0.2,
            label: 'reason TextField above 300px keyboard ($size)',
          );

          // Real touch focus + text edit while keyboard remains at 300px
          await tester.tap(textFieldFinder);
          await tester.pumpAndSettle();
          expect(tester.testTextInput.isVisible, isTrue);

          await tester.enterText(textFieldFinder, customReason);
          await tester.pumpAndSettle();

          // Verify actual EditableText semantic value updated & field stays fully contained above keyboard
          final editableSemAfter =
              tester.getSemantics(editableFinder).getSemanticsData();
          expect(editableSemAfter.label, contains(expectedFieldLabel));
          expect(editableSemAfter.value, equals(customReason));
          expect(find.text(customReason), findsOneWidget);

          await _scrollToAndAssertVisibleInViewport(
            tester,
            textFieldFinder,
            screenWidth: size.width,
            scrollViewFinder: modalScrollFinder,
            maxAllowedBottom: keyboardTop,
            alignment: 0.2,
            label: 'edited reason TextField above 300px keyboard ($size)',
          );

          // Scroll Save button fully into modal viewport & strictly above 300px keyboard, then save
          final saveBtnFinder = find.ancestor(
            of: find.text('حفظ الحالة والسبب في سجل المحاسبة الأسبوعي'),
            matching: find.byType(ElevatedButton),
          );
          final saveRect = await _scrollToAndAssertVisibleInViewport(
            tester,
            saveBtnFinder,
            screenWidth: size.width,
            scrollViewFinder: modalScrollFinder,
            maxAllowedBottom: keyboardTop,
            alignment: 0.9,
            label: 'save button above 300px keyboard ($size)',
          );
          expect(saveRect.height, greaterThanOrEqualTo(48.0));

          // Save via real touch on 360x800 and SemanticsAction.tap on 412x915
          if (size.width <= 360) {
            await tester.tap(saveBtnFinder);
          } else {
            _performSemanticTap(tester, saveBtnFinder, 'Save reason button');
          }
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 400));

          // Dismiss keyboard after save & verify persisted state + visible UI update
          keyboardInset.value = 0.0;
          await tester.pumpAndSettle();

          expect(
            PrayerTrackerService.instance.todayRecord.getPrayerStatus('المغرب'),
            equals(PrayerPerformanceStatus.lateQada),
          );
          expect(
            PrayerTrackerService.instance.todayRecord.getReasonForPrayer('المغرب'),
            equals(customReason),
          );
          expect(
            PrayerTrackerService.instance.todayRecord.completedObligatoryCount,
            equals(1),
          );
          expect(find.text('1 من 5 صلوات'), findsOneWidget);
          await _scrollToAndAssertVisibleInViewport(
            tester,
            find.text('📌 سبب عدم الصلاة في وقتها: $customReason'),
            screenWidth: size.width,
            label: 'saved Maghrib reason banner ($size)',
          );

          // Reload from SharedPreferences to verify true persistence
          await PrayerTrackerService.instance.init(forceReload: true);
          expect(
            PrayerTrackerService.instance.todayRecord.getPrayerStatus('المغرب'),
            equals(PrayerPerformanceStatus.lateQada),
          );
          expect(
            PrayerTrackerService.instance.todayRecord.getReasonForPrayer('المغرب'),
            equals(customReason),
          );
          expect(
            PrayerTrackerService.instance.todayRecord.completedObligatoryCount,
            equals(1),
          );

          expect(
            tester.takeException(),
            isNull,
            reason: 'Zero errors during 300px keyboard flow on $size',
          );
        }
      } finally {
        semanticsHandle.dispose();
      }
    },
  );
}
