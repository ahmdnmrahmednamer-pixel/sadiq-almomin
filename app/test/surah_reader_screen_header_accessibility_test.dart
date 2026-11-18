import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/core/models/surah.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/ui/app_dropdown_field.dart';
import 'package:almomin/features/mushaf/page_mode_mushaf_screen.dart';
import 'package:almomin/features/mushaf/surah_reader_screen.dart';

const bool _kCapturePixels = bool.fromEnvironment(
  'CAPTURE_REPAIR15_PIXELS',
  defaultValue: false,
);
const String _kPixelDir = String.fromEnvironment(
  'REPAIR15_PIXEL_DIR',
  defaultValue: '',
);
const String _kMaterialIcons = String.fromEnvironment(
  'MATERIAL_ICONS_FONT',
  defaultValue: '',
);

final GlobalKey _kBoundaryKey = GlobalKey();

Future<void> _loadRealFonts() async {
  final cairo = File('assets/fonts/Cairo-Regular.ttf');
  if (cairo.existsSync()) {
    final bytes = cairo.readAsBytesSync();
    for (final family in const ['Cairo', 'Roboto']) {
      final loader = FontLoader(family);
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  }
  final amiri = FontLoader('Amiri');
  for (final path in const [
    'assets/fonts/Amiri-Regular.ttf',
    'assets/fonts/Amiri-Bold.ttf',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      amiri.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
    }
  }
  await amiri.load();
  for (final path in [
    if (_kMaterialIcons.isNotEmpty) _kMaterialIcons,
    'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      final loader = FontLoader('MaterialIcons');
      loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
      await loader.load();
      break;
    }
  }
}

Future<void> _capturePng(WidgetTester tester, String fileName) async {
  if (!_kCapturePixels || _kPixelDir.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        _kBoundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    Directory(_kPixelDir).createSync(recursive: true);
    File('$_kPixelDir/$fileName').writeAsBytesSync(byteData!.buffer.asUint8List());
  });
}

class _AutoPushHost extends StatefulWidget {
  final Surah surah;
  const _AutoPushHost(this.surah);

  @override
  State<_AutoPushHost> createState() => _AutoPushHostState();
}

class _AutoPushHostState extends State<_AutoPushHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SurahReaderScreen(surah: widget.surah),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

Widget _buildHost(Surah surah, {required double scale, required bool pushed}) {
  return RepaintBoundary(
    key: _kBoundaryKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        );
      },
      home: pushed ? _AutoPushHost(surah) : SurahReaderScreen(surah: surah),
    ),
  );
}

Future<void> _settleReader(WidgetTester tester) async {
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

List<SemanticsNode> _findAllTappableNodes(
  WidgetTester tester,
  String substring,
) {
  final root = tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
  final matches = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    final combined = '${data.label} ${data.tooltip} ${data.value}';
    if (combined.contains(substring) && data.hasAction(SemanticsAction.tap)) {
      matches.add(node);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  expect(
    matches,
    isNotEmpty,
    reason: 'Expected at least one tappable SemanticsNode matching "$substring"',
  );
  return matches;
}

SemanticsNode _findTappableNode(WidgetTester tester, String substring) {
  return _findAllTappableNodes(tester, substring).first;
}

void _assertCompactMenuContained(WidgetTester tester, double viewportWidth) {
  for (final label in const [
    'تغيير نمط القراءة',
    'تغيير القارئ للتلاوة',
    'الانتقال إلى نمط صفحات المصحف (604 صفحات)',
  ]) {
    final itemFinder = find.text(label);
    expect(itemFinder, findsOneWidget, reason: 'Missing menu item "$label"');
    _assertContainedHorizontally(
      tester.getRect(itemFinder),
      viewportWidth,
      'overflow menu item "$label"',
    );
  }
  _assertContainedHorizontally(
    tester.getRect(find.byType(AppToolbarDropdown<String>)),
    viewportWidth,
    'display mode dropdown while menu open',
  );
  _assertContainedHorizontally(
    tester.getRect(find.byType(AppToolbarDropdown<int>)),
    viewportWidth,
    'theme dropdown while menu open',
  );
}

void _assertExactOutOfScopeOverflows(
  List<({String message, String fullDump})> captured, {
  required String destinationName,
  required List<({String sourceLocation, String direction, int roundedPixels})>
      expectedMultiset,
}) {
  final overflowRe = RegExp(
    r'A RenderFlex overflowed by ([0-9]+(?:\.[0-9]+)?) pixels on the (right|left|top|bottom)\.',
  );
  final locRe = RegExp(r'([a-zA-Z0-9_]+\.dart:\d+:\d+)');
  final observed =
      <({String sourceLocation, String direction, int roundedPixels})>[];

  for (final err in captured) {
    final m = overflowRe.firstMatch(err.message);
    expect(
      m,
      isNotNull,
      reason: 'Unexpected non-overflow error in $destinationName: ${err.message}',
    );
    final loc = locRe.firstMatch(err.fullDump)?.group(1) ?? 'unknown';
    final px = double.parse(m!.group(1)!).round();
    final dir = m.group(2)!;
    // ignore: avoid_print
    print(
      'UNRESOLVED_OUT_OF_SCOPE_DEST_OVERFLOW[$destinationName]: ${err.message} | LOC=$loc',
    );
    observed.add((
      sourceLocation: loc,
      direction: dir,
      roundedPixels: px,
    ));
  }

  expect(
    observed,
    equals(expectedMultiset),
    reason:
        '$destinationName out-of-scope overflow multiset mismatch: observed=$observed expected=$expectedMultiset',
  );
}

void _assertContainedHorizontally(
  Rect rect,
  double viewportWidth,
  String description,
) {
  expect(
    rect.width,
    greaterThan(0),
    reason: '$description must have positive width, got $rect',
  );
  expect(
    rect.left,
    greaterThanOrEqualTo(-0.5),
    reason: '$description clipped on left: $rect (viewportWidth=$viewportWidth)',
  );
  expect(
    rect.right,
    lessThanOrEqualTo(viewportWidth + 0.5),
    reason: '$description clipped on right: $rect (viewportWidth=$viewportWidth)',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadRealFonts();
  });

  testWidgets(
    'SurahReaderScreen header responsive matrix (360/412, 1x/2x, root & pushed, wide) has zero overflow, non-ellipsized title, full containment, and scrollable body',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.init();
      tester.view.devicePixelRatio = 1.0;

      final surahs = await tester.runAsync(() async {
        final list = await QuranRepository.loadSurahs();
        await QuranRepository.getAyahsForSurah(18);
        await QuranRepository.getAyahsForSurah(3);
        return list;
      });
      expect(surahs, isNotNull);
      final kahf = surahs!.firstWhere((s) => s.id == 18);
      final aalImran = surahs.firstWhere((s) => s.id == 3);

      final scenarios = <({
        String id,
        Surah surah,
        Size size,
        double scale,
        bool pushed,
        bool expectCompact,
        String? captureName,
      })>[
        (
          id: '360x800_1x_root',
          surah: kahf,
          size: const Size(360, 800),
          scale: 1.0,
          pushed: false,
          expectCompact: true,
          captureName: 'repair15_after_360x800_1x_root.png',
        ),
        (
          id: '360x800_1x_pushed',
          surah: kahf,
          size: const Size(360, 800),
          scale: 1.0,
          pushed: true,
          expectCompact: true,
          captureName: 'repair15_after_360x800_1x_pushed.png',
        ),
        (
          id: '360x800_2x_pushed',
          surah: kahf,
          size: const Size(360, 800),
          scale: 2.0,
          pushed: true,
          expectCompact: true,
          captureName: 'repair15_after_360x800_2x_pushed.png',
        ),
        (
          id: '360x800_2x_pushed_long_title_aal_imran',
          surah: aalImran,
          size: const Size(360, 800),
          scale: 2.0,
          pushed: true,
          expectCompact: true,
          captureName: 'repair15_after_360x800_2x_pushed_long_title_aal_imran.png',
        ),
        (
          id: '412x915_1x_pushed',
          surah: kahf,
          size: const Size(412, 915),
          scale: 1.0,
          pushed: true,
          expectCompact: true,
          captureName: 'repair15_after_412x915_1x_pushed.png',
        ),
        (
          id: '412x915_2x_pushed',
          surah: kahf,
          size: const Size(412, 915),
          scale: 2.0,
          pushed: true,
          expectCompact: true,
          captureName: 'repair15_after_412x915_2x_pushed.png',
        ),
        (
          id: '600x900_1x_pushed_wide',
          surah: kahf,
          size: const Size(600, 900),
          scale: 1.0,
          pushed: true,
          expectCompact: false,
          captureName: null,
        ),
      ];

      final prevOnError = FlutterError.onError;
      try {
        for (final sc in scenarios) {
          final expectedTitle = 'سورة ${sc.surah.nameAr}';
          final errors = <FlutterErrorDetails>[];
          FlutterError.onError = (details) => errors.add(details);

          tester.view.physicalSize = sc.size;
          await tester.pumpWidget(
            _buildHost(sc.surah, scale: sc.scale, pushed: sc.pushed),
          );
          await _settleReader(tester);

          expect(
            errors,
            isEmpty,
            reason:
                'Scenario ${sc.id} produced unexpected FlutterErrors: ${errors.map((e) => e.exceptionAsString()).join(" | ")}',
          );

          // Verify uncapped TextScaler
          final readerCtx = tester.element(find.byType(SurahReaderScreen));
          expect(
            MediaQuery.textScalerOf(readerCtx).scale(1.0),
            closeTo(sc.scale, 0.001),
            reason: '${sc.id}: TextScaler must remain uncapped',
          );

          // AppBar & non-ellipsized title containment
          final appBarFinder = find.byType(AppBar);
          expect(appBarFinder, findsOneWidget);
          final appBarRect = tester.getRect(appBarFinder);
          _assertContainedHorizontally(appBarRect, sc.size.width, '${sc.id} AppBar');

          final titleFinder = find.descendant(
            of: appBarFinder,
            matching: find.text(expectedTitle),
          );
          expect(titleFinder, findsOneWidget);
          final titleRect = tester.getRect(titleFinder);
          _assertContainedHorizontally(titleRect, sc.size.width, '${sc.id} AppBar title');
          expect(
            titleRect.top,
            greaterThanOrEqualTo(appBarRect.top - 0.5),
            reason: '${sc.id} title clipped above AppBar',
          );
          expect(
            titleRect.bottom,
            lessThanOrEqualTo(appBarRect.bottom + 0.5),
            reason: '${sc.id} title clipped below AppBar',
          );

          final titleParagraph = tester.renderObject<RenderParagraph>(titleFinder);
          expect(
            titleParagraph.didExceedMaxLines,
            isFalse,
            reason: '${sc.id} AppBar title must not ellipsize/truncate',
          );

          // Action buttons containment
          final fontBtn = find.byTooltip('تغيير حجم الخط');
          expect(fontBtn, findsOneWidget);
          _assertContainedHorizontally(
            tester.getRect(fontBtn),
            sc.size.width,
            '${sc.id} font size button',
          );

          if (sc.expectCompact) {
            final moreBtn = find.byTooltip('المزيد من خيارات القراءة');
            expect(moreBtn, findsOneWidget);
            _assertContainedHorizontally(
              tester.getRect(moreBtn),
              sc.size.width,
              '${sc.id} overflow menu button',
            );
          } else {
            for (final tip in const [
              'تغيير نمط القراءة',
              'تغيير القارئ للتلاوة',
              'الانتقال إلى نمط صفحات المصحف (604 صفحات)',
            ]) {
              final btn = find.byTooltip(tip);
              expect(btn, findsOneWidget, reason: '${sc.id} missing wide action $tip');
              _assertContainedHorizontally(
                tester.getRect(btn),
                sc.size.width,
                '${sc.id} $tip',
              );
            }
          }

          // Preserved secondary reading controls bar & dropdowns
          final controlsBar = find.byKey(const ValueKey('surah_reader_controls_bar'));
          expect(controlsBar, findsOneWidget);
          final controlsRect = tester.getRect(controlsBar);
          _assertContainedHorizontally(
            controlsRect,
            sc.size.width,
            '${sc.id} controls bar',
          );
          expect(controlsRect.top, greaterThanOrEqualTo(appBarRect.bottom - 0.5));

          expect(find.text('المصحف المتصل'), findsOneWidget);
          expect(find.byType(AppToolbarDropdown<String>), findsOneWidget);
          expect(find.byType(AppToolbarDropdown<int>), findsOneWidget);
          _assertContainedHorizontally(
            tester.getRect(find.byType(AppToolbarDropdown<String>)),
            sc.size.width,
            '${sc.id} display mode dropdown',
          );
          _assertContainedHorizontally(
            tester.getRect(find.byType(AppToolbarDropdown<int>)),
            sc.size.width,
            '${sc.id} theme dropdown',
          );

          // Actual shipping corpus Ayah text rendered & reading body scrollable
          final listViewFinder = find.byType(ListView);
          expect(listViewFinder, findsOneWidget);
          final listRect = tester.getRect(listViewFinder);
          expect(
            listRect.height,
            greaterThan(sc.size.height * 0.5),
            reason: '${sc.id}: reading body must retain generous vertical viewport',
          );
          expect(find.text('بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ'), findsOneWidget);

          if (sc.captureName != null) {
            await _capturePng(tester, sc.captureName!);
          }

          // Scroll reachability check
          final scrollable = tester.state<ScrollableState>(
            find.descendant(of: listViewFinder, matching: find.byType(Scrollable)),
          );
          final beforeOffset = scrollable.position.pixels;
          await tester.drag(listViewFinder, const Offset(0, -250));
          await tester.pump(const Duration(milliseconds: 200));
          expect(
            scrollable.position.pixels,
            greaterThan(beforeOffset),
            reason: '${sc.id}: reading body must scroll cleanly below header',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 100));
        }
      } finally {
        FlutterError.onError = prevOnError;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );

  testWidgets(
    'SurahReaderScreen header controls support pointer and SemanticsAction.tap activation at 360x800 @ 2.0x and route to PageModeMushafScreen',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.init();
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 800);

      final surahs = await tester.runAsync(() async {
        final list = await QuranRepository.loadSurahs();
        await QuranRepository.getAyahsForSurah(18);
        return list;
      });
      final kahf = surahs!.firstWhere((s) => s.id == 18);

      final errors = <FlutterErrorDetails>[];
      final prevOnError = FlutterError.onError;
      FlutterError.onError = (d) => errors.add(d);
      final semanticsHandle = tester.ensureSemantics();

      try {
        await tester.pumpWidget(_buildHost(kahf, scale: 2.0, pushed: true));
        await _settleReader(tester);

        // 1. Font size button: pointer tap + SemanticsAction.tap
        final initialFont = SettingsService.instance.mushafFontSize;
        await tester.tap(find.byTooltip('تغيير حجم الخط'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        final afterPointerFont = SettingsService.instance.mushafFontSize;
        expect(afterPointerFont, isNot(equals(initialFont)));

        final fontSemNode = _findTappableNode(tester, 'تغيير حجم الخط');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          fontSemNode.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          SettingsService.instance.mushafFontSize,
          isNot(equals(afterPointerFont)),
        );

        // 2. Display mode dropdown:
        //    (a) Pointer open + pointer select -> cards ('بطاقات الآيات والتفسير') at 360x800 @ 2.0x
        await tester.tap(find.byType(AppToolbarDropdown<String>));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(find.text('بطاقات الآيات والتفسير').last);
        await _settleReader(tester);
        expect(find.text('آية ١ / ١١٠'), findsOneWidget);
        expect(find.text('بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ'), findsNothing);
        _assertContainedHorizontally(
          tester.getRect(find.byType(AppToolbarDropdown<String>)),
          360,
          '360x800_2x cards display dropdown',
        );
        await _capturePng(tester, 'repair15_after_360x800_2x_pushed_cards.png');

        // Verify cards mode scroll reachability
        final cardsList = find.byType(ListView);
        final cardsScrollable = tester.state<ScrollableState>(
          find.descendant(of: cardsList, matching: find.byType(Scrollable)),
        );
        await tester.drag(cardsList, const Offset(0, -300));
        await tester.pump(const Duration(milliseconds: 200));
        expect(cardsScrollable.position.pixels, greaterThan(0));

        //    (b) SemanticsAction.tap open + SemanticsAction.tap select -> back to continuous ('المصحف المتصل')
        final modeSemNode = _findTappableNode(tester, 'نمط عرض الآيات');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          modeSemNode.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final continuousOptionNode = _findAllTappableNodes(
          tester,
          'المصحف المتصل',
        ).last;
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          continuousOptionNode.id,
          SemanticsAction.tap,
        );
        await _settleReader(tester);
        expect(find.text('بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ'), findsOneWidget);
        expect(find.text('آية ١ / ١١٠'), findsNothing);

        // 3. Theme dropdown:
        //    (a) Pointer open + pointer select -> dark reading mode ('ليلي مريح')
        await tester.tap(find.byType(AppToolbarDropdown<int>));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(find.text('ليلي مريح').last);
        await _settleReader(tester);
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
          equals(const Color(0xFF141716)),
        );

        //    (b) SemanticsAction.tap open + SemanticsAction.tap select -> sepia ('ورقي مصحفي')
        final themeSemNode1 = _findTappableNode(tester, 'مظهر القراءة');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          themeSemNode1.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final sepiaOptionNode = _findAllTappableNodes(tester, 'ورقي مصحفي').last;
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          sepiaOptionNode.id,
          SemanticsAction.tap,
        );
        await _settleReader(tester);
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
          equals(const Color(0xFFF7F1E3)),
        );

        //    (c) SemanticsAction.tap open + SemanticsAction.tap select -> back to auto ('تلقائي')
        final themeSemNode2 = _findTappableNode(tester, 'مظهر القراءة');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          themeSemNode2.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final autoOptionNode = _findAllTappableNodes(tester, 'تلقائي').last;
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          autoOptionNode.id,
          SemanticsAction.tap,
        );
        await _settleReader(tester);
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
          equals(const Color(0xFFFCFCFA)),
        );

        // 4. Moved compact menu item 1 ('تغيير نمط القراءة'):
        //    (a) Pointer open + containment + menu PNG capture + pointer select -> sepia (0 -> 1)
        await tester.tap(find.byTooltip('المزيد من خيارات القراءة'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        _assertCompactMenuContained(tester, 360);
        await _capturePng(tester, 'repair15_after_360x800_2x_pushed_menu_open.png');

        await tester.tap(find.text('تغيير نمط القراءة'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
          equals(const Color(0xFFF7F1E3)),
        );
        expect(find.text('وضع القراءة: ورقي مصحفي دافئ'), findsOneWidget);

        //    (b) SemanticsAction.tap open + containment + SemanticsAction.tap select -> dark (1 -> 2)
        final menuSemNode1 = _findTappableNode(tester, 'المزيد من خيارات القراءة');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          menuSemNode1.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        _assertCompactMenuContained(tester, 360);
        final cycleThemeNode = _findTappableNode(tester, 'تغيير نمط القراءة');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          cycleThemeNode.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
          equals(const Color(0xFF141716)),
        );
        expect(find.text('وضع القراءة: ليلي مريح للعين'), findsOneWidget);

        // Assert ZERO errors across all SurahReaderScreen header interactions at 360x800 @ 2.0x
        expect(
          errors,
          isEmpty,
          reason:
              'Unexpected FlutterErrors during 360x800 @ 2.0x SurahReaderScreen header control checks: ${errors.map((e) => e.exceptionAsString()).join(" | ")}',
        );

        // 5. Moved compact menu item 2 ('تغيير القارئ للتلاوة') at 360x800 @ 2.0x:
        //    (a) Pointer open + pointer select -> SettingsReciterModal opens (exact baseline 118px out-of-scope multiset)
        const expectedReciter2x = [
          (
            sourceLocation: 'settings_reciter_modal.dart:318:40',
            direction: 'right',
            roundedPixels: 118,
          ),
        ];

        final reciterPointerErrors = <({String message, String fullDump})>[];
        FlutterError.onError = (details) {
          reciterPointerErrors.add((
            message: details.exceptionAsString(),
            fullDump: details.toString(),
          ));
        };
        await tester.tap(find.byTooltip('المزيد من خيارات القراءة'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        _assertCompactMenuContained(tester, 360);
        await tester.tap(find.text('تغيير القارئ للتلاوة'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        expect(find.byType(BottomSheet), findsOneWidget);
        _assertExactOutOfScopeOverflows(
          reciterPointerErrors,
          destinationName: 'SettingsReciterModal(360_2x_pointer)',
          expectedMultiset: expectedReciter2x,
        );
        FlutterError.onError = (d) => errors.add(d);
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        //    (b) SemanticsAction.tap open + SemanticsAction.tap select -> SettingsReciterModal opens
        final reciterSemErrors = <({String message, String fullDump})>[];
        FlutterError.onError = (details) {
          reciterSemErrors.add((
            message: details.exceptionAsString(),
            fullDump: details.toString(),
          ));
        };
        final menuSemNode2 = _findTappableNode(tester, 'المزيد من خيارات القراءة');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          menuSemNode2.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        _assertCompactMenuContained(tester, 360);
        final reciterNode = _findTappableNode(tester, 'تغيير القارئ للتلاوة');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          reciterNode.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        expect(find.byType(BottomSheet), findsOneWidget);
        _assertExactOutOfScopeOverflows(
          reciterSemErrors,
          destinationName: 'SettingsReciterModal(360_2x_semantics)',
          expectedMultiset: expectedReciter2x,
        );
        FlutterError.onError = (d) => errors.add(d);
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(
          errors,
          isEmpty,
          reason:
              'Unexpected FlutterErrors after closing Reciter modal: ${errors.map((e) => e.exceptionAsString()).join(" | ")}',
        );

        // 6. Moved compact menu item 3 ('الانتقال إلى نمط صفحات المصحف (604 صفحات)'):
        //    (a) SemanticsAction.tap open + SemanticsAction.tap select at 360x800 @ 2.0x
        const expectedPageMode2x = <({
          String sourceLocation,
          String direction,
          int roundedPixels,
        })>[
          (
            sourceLocation: 'page_mode_mushaf_screen.dart:206:15',
            direction: 'right',
            roundedPixels: 22,
          ),
        ];

        final pageMode2xSemErrors = <({String message, String fullDump})>[];
        FlutterError.onError = (details) {
          pageMode2xSemErrors.add((
            message: details.exceptionAsString(),
            fullDump: details.toString(),
          ));
        };
        final menuSemNode3 = _findTappableNode(tester, 'المزيد من خيارات القراءة');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          menuSemNode3.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        _assertCompactMenuContained(tester, 360);
        final pageModeSemNode = _findTappableNode(
          tester,
          'الانتقال إلى نمط صفحات المصحف (604 صفحات)',
        );
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          pageModeSemNode.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(PageModeMushafScreen), findsOneWidget);
        expect(
          tester.widget<PageModeMushafScreen>(find.byType(PageModeMushafScreen)).initialPage,
          equals(kahf.pageStart),
        );
        _assertExactOutOfScopeOverflows(
          pageMode2xSemErrors,
          destinationName: 'PageModeMushafScreen(360_2x_semantics)',
          expectedMultiset: expectedPageMode2x,
        );

        //    (b) Pointer open + pointer select at 360x800 @ 2.0x
        FlutterError.onError = (d) => errors.add(d);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpWidget(_buildHost(kahf, scale: 2.0, pushed: true));
        await _settleReader(tester);

        final pageMode2xPtrErrors = <({String message, String fullDump})>[];
        FlutterError.onError = (details) {
          pageMode2xPtrErrors.add((
            message: details.exceptionAsString(),
            fullDump: details.toString(),
          ));
        };
        await tester.tap(find.byTooltip('المزيد من خيارات القراءة'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        _assertCompactMenuContained(tester, 360);
        await tester.tap(find.text('الانتقال إلى نمط صفحات المصحف (604 صفحات)'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(PageModeMushafScreen), findsOneWidget);
        expect(
          tester.widget<PageModeMushafScreen>(find.byType(PageModeMushafScreen)).initialPage,
          equals(kahf.pageStart),
        );
        _assertExactOutOfScopeOverflows(
          pageMode2xPtrErrors,
          destinationName: 'PageModeMushafScreen(360_2x_pointer)',
          expectedMultiset: expectedPageMode2x,
        );

        //    (c) Pointer open + pointer select at 360x800 @ 1.0x (ZERO errors)
        FlutterError.onError = (d) => errors.add(d);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpWidget(_buildHost(kahf, scale: 1.0, pushed: true));
        await _settleReader(tester);

        await tester.tap(find.byTooltip('المزيد من خيارات القراءة'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        _assertCompactMenuContained(tester, 360);
        await tester.tap(find.text('الانتقال إلى نمط صفحات المصحف (604 صفحات)'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(PageModeMushafScreen), findsOneWidget);
        expect(
          tester.widget<PageModeMushafScreen>(find.byType(PageModeMushafScreen)).initialPage,
          equals(kahf.pageStart),
        );
        expect(
          errors,
          isEmpty,
          reason:
              'Unexpected FlutterErrors navigating to PageModeMushafScreen at 360x800 @ 1.0x: ${errors.map((e) => e.exceptionAsString()).join(" | ")}',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 250));
      } finally {
        semanticsHandle.dispose();
        FlutterError.onError = prevOnError;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );
}
