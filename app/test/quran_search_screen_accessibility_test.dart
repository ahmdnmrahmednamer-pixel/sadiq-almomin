import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/core/services/quran_search_service.dart';
import 'package:almomin/core/services/voice_search_service.dart';
import 'package:almomin/core/theme/app_theme.dart' as core_theme;
import 'package:almomin/features/search/quran_search_screen.dart';

const bool _kCapturePixels = bool.fromEnvironment(
  'CAPTURE_REPAIR13_PIXELS',
  defaultValue: false,
);
const String _kCaptureOutDir = String.fromEnvironment(
  'CAPTURE_REPAIR13_OUT_DIR',
  defaultValue: '',
);
const String _kMaterialIconsFontPath = String.fromEnvironment(
  'MATERIAL_ICONS_FONT',
  defaultValue: '',
);

final GlobalKey _kBoundaryKey = GlobalKey();

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
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

Future<void> _capturePng(WidgetTester tester, String fileName) async {
  if (!_kCapturePixels || _kCaptureOutDir.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        _kBoundaryKey.currentContext!.findRenderObject()!
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

Future<void> _settleSearchAsync(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 250));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Widget _buildHostApp({
  required double textScale,
  required double keyboardBottom,
  String? initialQuery,
  bool pushedWithBack = false,
  ThemeData? theme,
}) {
  Widget home = QuranSearchScreen(initialQuery: initialQuery);
  if (pushedWithBack) {
    home = _AutoPushSearchHost(initialQuery: initialQuery);
  }
  return RepaintBoundary(
    key: _kBoundaryKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? AppTheme.lightTheme,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: keyboardBottom),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        );
      },
      home: home,
    ),
  );
}

class _AutoPushSearchHost extends StatefulWidget {
  final String? initialQuery;

  const _AutoPushSearchHost({this.initialQuery});

  @override
  State<_AutoPushSearchHost> createState() => _AutoPushSearchHostState();
}

class _AutoPushSearchHostState extends State<_AutoPushSearchHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => QuranSearchScreen(initialQuery: widget.initialQuery),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

void _expectWithinHorizontalBounds(
  WidgetTester tester,
  Finder finder,
  double viewportWidth,
  String label,
) {
  expect(finder, findsWidgets, reason: 'Expected $label to exist');
  final rect = tester.getRect(finder.first);
  expect(
    rect.left,
    greaterThanOrEqualTo(-0.5),
    reason: '$label left (${rect.left}) overflowed left edge',
  );
  expect(
    rect.right,
    lessThanOrEqualTo(viewportWidth + 0.5),
    reason: '$label right (${rect.right}) overflowed viewport ($viewportWidth)',
  );
}

void _expectAppBarTitleNotEllipsizedOrClipped(
  WidgetTester tester,
  double textScale,
  double viewportWidth,
  String scenarioLabel,
) {
  final titleFinder = find.descendant(
    of: find.byType(AppBar),
    matching: find.text('البحث في القرآن الكريم'),
  );
  expect(
    titleFinder,
    findsOneWidget,
    reason: '[$scenarioLabel] AppBar title text must be preserved verbatim',
  );

  final textWidget = tester.widget<Text>(titleFinder);
  expect(
    textWidget.overflow,
    isNot(TextOverflow.ellipsis),
    reason: '[$scenarioLabel] AppBar title must not use TextOverflow.ellipsis',
  );

  final rp = tester.renderObject<RenderParagraph>(titleFinder);
  final titleRect = tester.getRect(titleFinder);
  final appBarRect = tester.getRect(find.byType(AppBar));

  expect(
    rp.didExceedMaxLines,
    isFalse,
    reason:
        '[$scenarioLabel] AppBar RenderParagraph exceeded maxLines=${textWidget.maxLines} at width=${rp.size.width}',
  );
  expect(
    titleRect.left,
    greaterThanOrEqualTo(-0.5),
    reason: '[$scenarioLabel] AppBar title left clipped',
  );
  expect(
    titleRect.right,
    lessThanOrEqualTo(viewportWidth + 0.5),
    reason: '[$scenarioLabel] AppBar title right clipped',
  );
  expect(
    titleRect.top,
    greaterThanOrEqualTo(appBarRect.top - 0.5),
    reason: '[$scenarioLabel] AppBar title top clipped outside AppBar',
  );
  expect(
    titleRect.bottom,
    lessThanOrEqualTo(appBarRect.bottom + 0.5),
    reason:
        '[$scenarioLabel] AppBar title bottom (${titleRect.bottom}) clipped outside AppBar (${appBarRect.bottom})',
  );
}

SemanticsNode _findTappableSemanticNode(WidgetTester tester, String target) {
  final matches = <SemanticsNode>[];
  for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
    final data = node.getSemanticsData();
    if ((data.label == target ||
            data.tooltip == target ||
            data.label.contains(target)) &&
        data.hasAction(SemanticsAction.tap)) {
      matches.add(node);
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
    SharedPreferences.setMockInitialValues({
      'quran_search_history_v1': <String>[
        'آية الكرسي',
        'الرحمن الرحيم',
        'سورة الكهف',
        'خواتيم البقرة',
        'الله نور السماوات',
      ],
    });
    VoiceSearchService.resetTestMode();
    VoiceSearchService.isTestMode = true;
    VoiceSearchService.testMockRecognizedWords = 'آية الدين';
  });

  tearDown(() {
    VoiceSearchService.resetTestMode();
  });

  group('Repair 13: QuranSearchScreen Layout, Title, Keyboard, Contrast & Semantics', () {
    testWidgets(
      'Zero overflows, uncapped TextScaler, non-ellipsized AppBar title (root & pushed), filter/history containment, no-results scroll reachability, and changed-element contrast across 360x800 & 412x915 at 1.0x/2.0x + 300px keyboard',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // (size, textScale, kbBottom, initialQuery, pushedWithBack, darkMode, label)
        const matrix = <(Size, double, double, String?, bool, bool, String)>[
          (Size(360, 800), 1.0, 0, null, false, false, 'initial_360_1x_light'),
          (Size(360, 800), 2.0, 0, null, false, false, 'initial_360_2x_light'),
          (Size(360, 800), 2.0, 0, null, false, true, 'initial_360_2x_dark'),
          (Size(360, 800), 2.0, 300, null, false, false, 'initial_360_2x_kb'),
          (Size(412, 915), 1.0, 0, null, false, false, 'initial_412_1x'),
          (Size(412, 915), 2.0, 0, null, false, false, 'initial_412_2x'),
          (Size(412, 915), 2.0, 300, null, false, false, 'initial_412_2x_kb'),
          (Size(360, 800), 1.0, 0, 'آية الكرسي', false, false, 'results_360_1x'),
          (Size(360, 800), 2.0, 0, 'آية الكرسي', false, false, 'results_360_2x'),
          (Size(360, 800), 2.0, 0, 'آية الكرسي', true, false, 'results_pushed_360_2x'),
          (Size(412, 915), 2.0, 0, 'آية الكرسي', false, false, 'results_412_2x'),
          (Size(360, 800), 2.0, 300, 'كلمةغيرموجودةابدا', false, false, 'noresults_360_2x_kb'),
          (Size(412, 915), 2.0, 300, 'كلمةغيرموجودةابدا', false, false, 'noresults_412_2x_kb'),
        ];

        for (final entry in matrix) {
          final size = entry.$1;
          final scale = entry.$2;
          final kb = entry.$3;
          final query = entry.$4;
          final pushed = entry.$5;
          final darkMode = entry.$6;
          final label = entry.$7;

          final errors = <FlutterErrorDetails>[];
          final prevOnError = FlutterError.onError;
          FlutterError.onError = (details) => errors.add(details);

          try {
            tester.view.physicalSize = size;
            await tester.pumpWidget(
              _buildHostApp(
                textScale: scale,
                keyboardBottom: kb,
                initialQuery: query,
                pushedWithBack: pushed,
                theme: darkMode ? AppTheme.darkTheme : AppTheme.lightTheme,
              ),
            );
            await tester.pump();
            if (pushed) {
              await tester.pump(const Duration(milliseconds: 350));
            }
            await _settleSearchAsync(tester);

            expect(
              errors,
              isEmpty,
              reason:
                  '[$label] Expected zero FlutterErrors/overflows, got: ${errors.map((e) => e.exceptionAsString()).join(" | ")}',
            );

            // Uncapped TextScaler verification inside QuranSearchScreen
            final searchCtx = tester.element(find.byType(QuranSearchScreen));
            expect(
              MediaQuery.textScalerOf(searchCtx).scale(10.0),
              closeTo(10.0 * scale, 0.01),
              reason: '[$label] TextScaler must NOT be capped',
            );

            // AppBar title non-ellipsized & fully contained
            _expectAppBarTitleNotEllipsizedOrClipped(tester, scale, size.width, label);

            // Scope & Filter Wrap + Surah filter button within viewport width
            _expectWithinHorizontalBounds(tester, find.text('الكل'), size.width, '[$label] chip الكل');
            _expectWithinHorizontalBounds(tester, find.textContaining('الآيات'), size.width, '[$label] chip الآيات');
            _expectWithinHorizontalBounds(tester, find.textContaining('السور'), size.width, '[$label] chip السور');
            _expectWithinHorizontalBounds(
              tester,
              find.byTooltip('تصفية حسب السورة'),
              size.width,
              '[$label] surah filter button',
            );

            // Contrast verification for changed selected ChoiceChip checkmark & label
            final selectedChip = tester.widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'الكل'),
            );
            expect(selectedChip.selected, isTrue);
            expect(selectedChip.checkmarkColor, Colors.white);
            final chipBg = selectedChip.selectedColor ?? core_theme.AppColors.primaryGreen;
            expect(
              _contrastRatio(selectedChip.checkmarkColor!, chipBg),
              greaterThanOrEqualTo(4.5),
              reason: '[$label] Selected ChoiceChip checkmark contrast must be >= 4.5:1',
            );
            expect(
              _contrastRatio(selectedChip.labelStyle!.color!, chipBg),
              greaterThanOrEqualTo(4.5),
              reason: '[$label] Selected ChoiceChip label contrast must be >= 4.5:1',
            );

            // Initial state: History header containment & changed clear-history button contrast
            if (query == null) {
              _expectWithinHorizontalBounds(
                tester,
                find.text('سجل البحث الأخير'),
                size.width,
                '[$label] history title',
              );
              _expectWithinHorizontalBounds(
                tester,
                find.text('مسح السجل'),
                size.width,
                '[$label] clear history button',
              );

              final clearText = tester.widget<Text>(find.text('مسح السجل'));
              final bg = darkMode ? AppTheme.darkTheme.scaffoldBackgroundColor : AppTheme.lightTheme.scaffoldBackgroundColor;
              expect(
                _contrastRatio(clearText.style!.color!, bg),
                greaterThanOrEqualTo(4.5),
                reason: '[$label] Clear history text contrast must be >= 4.5:1',
              );
            }

            // No-results state with keyboard: scrollable and guidance text reachable above keyboard
            if (query == 'كلمةغيرموجودةابدا') {
              final scrollFinder = find.byKey(const ValueKey('search_no_results_scroll_view'));
              expect(scrollFinder, findsOneWidget);
              final guidanceFinder = find.textContaining('تأكد من كتابة الكلمة');
              await tester.scrollUntilVisible(
                guidanceFinder,
                120,
                scrollable: find.descendant(
                  of: scrollFinder,
                  matching: find.byType(Scrollable),
                ),
              );
              await tester.pump();
              final guidanceRect = tester.getRect(guidanceFinder);
              expect(
                guidanceRect.bottom,
                lessThanOrEqualTo(size.height - kb + 1.0),
                reason:
                    '[$label] No-results guidance text bottom (${guidanceRect.bottom}) must be reachable above keyboard (${size.height - kb})',
              );
            }

            // Clean unmount before next scenario
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(milliseconds: 250));
          } finally {
            FlutterError.onError = prevOnError;
          }
        }
      },
    );

    testWidgets(
      'Semantic activation preserves filter selection, history tap/clear, query execution, and voice search follow-up at 360x800 @ 2.0x',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(360, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final errors = <FlutterErrorDetails>[];
        final prevOnError = FlutterError.onError;
        FlutterError.onError = (details) => errors.add(details);

        final semanticsHandle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _buildHostApp(
              textScale: 2.0,
              keyboardBottom: 0,
              initialQuery: null,
            ),
          );
          await _settleSearchAsync(tester);

          // 1. Semantic activation on history chip ('آية الكرسي') triggers query search
          expect(find.text('سجل البحث الأخير'), findsOneWidget);
          final historyLabelFinder = find.descendant(
            of: find.byType(InputChip),
            matching: find.text('آية الكرسي'),
          );
          expect(historyLabelFinder, findsOneWidget);
          final historyNode = tester.getSemantics(historyLabelFinder);
          expect(historyNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            historyNode.id,
            SemanticsAction.tap,
          );
          await _settleSearchAsync(tester);

          expect(
            tester.widget<TextField>(find.byType(TextField)).controller?.text,
            'آية الكرسي',
          );
          expect(find.text('سجل البحث الأخير'), findsNothing);
          expect(find.text('البقرة — آية 255'), findsOneWidget);
          _expectAppBarTitleNotEllipsizedOrClipped(tester, 2.0, 360, 'semantic_after_history_tap');

          // 2. Semantic activation on scope filter chips ('الآيات', 'السور', 'الكل')
          final ayahsChipNode = _findTappableSemanticNode(tester, 'الآيات');
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            ayahsChipNode.id,
            SemanticsAction.tap,
          );
          await tester.pump();
          expect(
            tester.widget<ChoiceChip>(find.byType(ChoiceChip).at(1)).selected,
            isTrue,
          );

          final allChipNode = _findTappableSemanticNode(tester, 'الكل');
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            allChipNode.id,
            SemanticsAction.tap,
          );
          await tester.pump();
          expect(
            tester.widget<ChoiceChip>(find.byType(ChoiceChip).at(0)).selected,
            isTrue,
          );

          // 3. Semantic activation on Surah filter PopupMenuButton
          final filterMenuNode = _findTappableSemanticNode(tester, 'تصفية حسب السورة');
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            filterMenuNode.id,
            SemanticsAction.tap,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('2. سورة البقرة'), findsOneWidget);
          final baqarahMenuNode = _findTappableSemanticNode(tester, '2. سورة البقرة');
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            baqarahMenuNode.id,
            SemanticsAction.tap,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await _settleSearchAsync(tester);
          expect(find.textContaining('البقرة'), findsWidgets);

          // 4. Clear query via semantic activation -> returns to initial state with history
          final clearFinder = find.byTooltip('إغلاق أو مسح');
          expect(clearFinder, findsOneWidget);
          final clearQueryNode = tester.getSemantics(clearFinder);
          expect(clearQueryNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            clearQueryNode.id,
            SemanticsAction.tap,
          );
          await _settleSearchAsync(tester);
          expect(find.text('سجل البحث الأخير'), findsOneWidget);

          // 5. Semantic activation on 'مسح السجل' clears displayed history section
          final clearHistoryNode = _findTappableSemanticNode(tester, 'مسح السجل');
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            clearHistoryNode.id,
            SemanticsAction.tap,
          );
          await _settleSearchAsync(tester);
          expect(find.text('سجل البحث الأخير'), findsNothing);

          // 6. Voice search follow-up: open voice sheet via AppBar mic semantic tap, return alias 'آية الدين'
          // (ordinary Surah & verse-phrase voice follow-ups are verified in quran_search_functional_regression_test.dart)
          final voiceBtnNode = _findTappableSemanticNode(
            tester,
            'البحث الصوتي عن الآيات بالميكروفون',
          );
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            voiceBtnNode.id,
            SemanticsAction.tap,
          );
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));

          expect(find.text('البحث الصوتي في القرآن الكريم'), findsOneWidget);
          final submitVoiceNode = _findTappableSemanticNode(tester, 'بحث بالآية');
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            submitVoiceNode.id,
            SemanticsAction.tap,
          );
          await tester.pump(const Duration(milliseconds: 400));
          await _settleSearchAsync(tester);

          // Returned voice query populated TextField and executed search
          final tf = tester.widget<TextField>(find.byType(TextField));
          expect(tf.controller?.text, 'آية الدين');
          expect(find.text('البقرة — آية 282'), findsOneWidget);

          expect(
            errors,
            isEmpty,
            reason:
                'Expected zero FlutterErrors during semantic interaction flow, got: ${errors.map((e) => e.exceptionAsString()).join(" | ")}',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 250));
        } finally {
          semanticsHandle.dispose();
          FlutterError.onError = prevOnError;
        }
      },
    );

    testWidgets(
      'Real-font AFTER PNG captures across 360/412, 1x/2x, +300px keyboard, initial/results/pushed/no-results',
      (tester) async {
        if (!_kCapturePixels || _kCaptureOutDir.isEmpty) return;

        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const scenarios = <(String, Size, double, double, String?, bool, bool)>[
          ('repair13_after_search_initial_360x800_1x.png', Size(360, 800), 1.0, 0, null, false, false),
          ('repair13_after_search_initial_360x800_2x.png', Size(360, 800), 2.0, 0, null, false, false),
          ('repair13_after_search_initial_360x800_2x_kb.png', Size(360, 800), 2.0, 300, null, false, false),
          ('repair13_after_search_initial_412x915_1x.png', Size(412, 915), 1.0, 0, null, false, false),
          ('repair13_after_search_initial_412x915_2x.png', Size(412, 915), 2.0, 0, null, false, false),
          ('repair13_after_search_initial_412x915_2x_kb.png', Size(412, 915), 2.0, 300, null, false, false),
          ('repair13_after_search_results_360x800_1x.png', Size(360, 800), 1.0, 0, 'آية الكرسي', false, false),
          ('repair13_after_search_results_360x800_2x.png', Size(360, 800), 2.0, 0, 'آية الكرسي', false, false),
          ('repair13_after_search_results_pushed_360x800_2x.png', Size(360, 800), 2.0, 0, 'آية الكرسي', true, false),
          ('repair13_after_search_results_412x915_2x.png', Size(412, 915), 2.0, 0, 'آية الكرسي', false, false),
          ('repair13_after_search_noresults_360x800_2x_kb.png', Size(360, 800), 2.0, 300, 'كلمةغيرموجودةابدا', false, false),
          ('repair13_after_search_noresults_bottom_360x800_2x_kb.png', Size(360, 800), 2.0, 300, 'كلمةغيرموجودةابدا', false, true),
        ];

        for (final s in scenarios) {
          final fileName = s.$1;
          final size = s.$2;
          final scale = s.$3;
          final kb = s.$4;
          final query = s.$5;
          final pushed = s.$6;
          final scrollBottom = s.$7;

          SharedPreferences.setMockInitialValues({});
          await QuranSearchService.instance.clearHistory();

          tester.view.physicalSize = size;
          await tester.pumpWidget(
            _buildHostApp(
              textScale: scale,
              keyboardBottom: kb,
              initialQuery: query,
              pushedWithBack: pushed,
            ),
          );
          await tester.pump();
          if (pushed) {
            await tester.pump(const Duration(milliseconds: 350));
          }
          await _settleSearchAsync(tester);

          if (scrollBottom) {
            final scrollFinder = find.byKey(const ValueKey('search_no_results_scroll_view'));
            await tester.scrollUntilVisible(
              find.textContaining('تأكد من كتابة الكلمة'),
              120,
              scrollable: find.descendant(
                of: scrollFinder,
                matching: find.byType(Scrollable),
              ),
            );
            await tester.pump();
          }

          await _capturePng(tester, fileName);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 250));
        }
      },
    );
  });
}
