import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/ui/app_dropdown_field.dart';
import 'package:almomin/features/mushaf/page_mode_mushaf_screen.dart';
import 'package:almomin/features/mushaf/surah_reader_screen.dart';

const bool _kCapturePixels = bool.fromEnvironment(
  'CAPTURE_REPAIR17_PIXELS',
  defaultValue: false,
);
const String _kPixelDir = String.fromEnvironment(
  'REPAIR17_PIXEL_DIR',
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
  final int initialPage;
  const _AutoPushHost(this.initialPage);

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
          builder: (_) => PageModeMushafScreen(initialPage: widget.initialPage),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

Widget _buildHost(
  int initialPage, {
  required double scale,
  required bool pushed,
  double keyboardHeight = 0.0,
}) {
  return RepaintBoundary(
    key: _kBoundaryKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboardHeight),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        );
      },
      home: pushed
          ? _AutoPushHost(initialPage)
          : PageModeMushafScreen(initialPage: initialPage),
    ),
  );
}

Future<void> _settlePageMode(WidgetTester tester) async {
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

({Rect clip, int viewportCount}) _visibleClipFor(
  WidgetTester tester,
  Finder targetFinder,
  Size screenSize, {
  double keyboardHeight = 0.0,
}) {
  Rect clip = Rect.fromLTWH(
    0,
    0,
    screenSize.width,
    screenSize.height - keyboardHeight,
  );
  int viewportCount = 0;
  RenderObject? ro = tester.renderObject(targetFinder);
  while (ro != null) {
    final parent = ro.parent;
    if (parent is RenderAbstractViewport && parent is RenderBox) {
      viewportCount++;
      final vpBox = parent as RenderBox;
      final topLeft = vpBox.localToGlobal(Offset.zero);
      clip = clip.intersect(topLeft & vpBox.size);
    }
    ro = parent;
  }
  return (clip: clip, viewportCount: viewportCount);
}

void _assertContainedInVisibleRect(
  WidgetTester tester,
  Finder targetFinder,
  Size screenSize, {
  double keyboardHeight = 0.0,
  int minAncestorViewports = 0,
  required String description,
}) {
  expect(
    targetFinder,
    findsOneWidget,
    reason: '$description must be present to check visible clip containment',
  );
  final rect = tester.getRect(targetFinder);
  final info = _visibleClipFor(
    tester,
    targetFinder,
    screenSize,
    keyboardHeight: keyboardHeight,
  );
  final visibleRect = info.clip;
  expect(
    info.viewportCount,
    greaterThanOrEqualTo(minAncestorViewports),
    reason:
        '$description expected >= $minAncestorViewports ancestor RenderAbstractViewport(s), found ${info.viewportCount}',
  );
  expect(visibleRect.width, greaterThan(0), reason: '$description empty visibleRect width');
  expect(visibleRect.height, greaterThan(0), reason: '$description empty visibleRect height');
  expect(rect.width, greaterThan(0), reason: '$description must have positive width, got $rect');
  expect(rect.height, greaterThan(0), reason: '$description must have positive height, got $rect');
  expect(
    rect.left,
    greaterThanOrEqualTo(visibleRect.left - 0.5),
    reason: '$description clipped on left: $rect vs visibleRect=$visibleRect',
  );
  expect(
    rect.right,
    lessThanOrEqualTo(visibleRect.right + 0.5),
    reason: '$description clipped on right: $rect vs visibleRect=$visibleRect',
  );
  expect(
    rect.top,
    greaterThanOrEqualTo(visibleRect.top - 0.5),
    reason: '$description clipped on top: $rect vs visibleRect=$visibleRect',
  );
  expect(
    rect.bottom,
    lessThanOrEqualTo(visibleRect.bottom + 0.5),
    reason: '$description clipped on bottom / behind keyboard: $rect vs visibleRect=$visibleRect',
  );
}

Future<void> _scrollFullyIntoVisibleRect(
  WidgetTester tester,
  Finder targetFinder,
  Finder scrollFinder,
  Size screenSize, {
  double keyboardHeight = 0.0,
  double step = 120.0,
}) async {
  for (int i = 0; i < 16; i++) {
    if (targetFinder.evaluate().isEmpty) {
      await tester.drag(scrollFinder, Offset(0, -step));
      await tester.pump(const Duration(milliseconds: 150));
      continue;
    }
    final rect = tester.getRect(targetFinder);
    final visibleRect = _visibleClipFor(
      tester,
      targetFinder,
      screenSize,
      keyboardHeight: keyboardHeight,
    ).clip;
    if (rect.top >= visibleRect.top - 0.5 &&
        rect.bottom <= visibleRect.bottom + 0.5) {
      return;
    }
    if (rect.bottom > visibleRect.bottom + 0.5) {
      final delta = (rect.bottom - visibleRect.bottom + 12.0).clamp(24.0, step);
      await tester.drag(scrollFinder, Offset(0, -delta));
    } else if (rect.top < visibleRect.top - 0.5) {
      final delta = (visibleRect.top - rect.top + 12.0).clamp(24.0, step);
      await tester.drag(scrollFinder, Offset(0, delta));
    }
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void _assertCompactMenuContained(WidgetTester tester, Size viewport) {
  for (final label in const [
    'تغيير سمة القراءة',
    'الانتقال إلى نمط السور النصي',
    'حفظ موضع القراءة الحالي',
  ]) {
    _assertContainedInVisibleRect(
      tester,
      find.text(label),
      viewport,
      description: 'compact overflow menu item "$label"',
    );
  }
  _assertContainedInVisibleRect(
    tester,
    find.byType(AppToolbarDropdown<int>),
    viewport,
    description: 'page mode theme dropdown while menu open',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadRealFonts();
  });

  testWidgets(
    'PageModeMushafScreen responsive matrix (360/412, 1x/2x, root/pushed, wide, jump dialog + 300px kb) has zero overflow, non-ellipsized title, full clip containment, and scrollable body',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.init();
      tester.view.devicePixelRatio = 1.0;

      await tester.runAsync(() async {
        await QuranRepository.loadSurahs();
        await QuranRepository.getAyahsForPage(293);
        await QuranRepository.getPageMetadata(293);
      });

      const scenarios = <({
        String id,
        Size size,
        double scale,
        bool pushed,
        double kb,
        bool expectCompact,
        bool openJump,
        String? captureName,
      })>[
        (
          id: '360x800_1x_root',
          size: Size(360, 800),
          scale: 1.0,
          pushed: false,
          kb: 0.0,
          expectCompact: true,
          openJump: false,
          captureName: 'repair17_after_360x800_1x_root.png',
        ),
        (
          id: '360x800_1x_pushed',
          size: Size(360, 800),
          scale: 1.0,
          pushed: true,
          kb: 0.0,
          expectCompact: true,
          openJump: false,
          captureName: 'repair17_after_360x800_1x_pushed.png',
        ),
        (
          id: '360x800_2x_pushed',
          size: Size(360, 800),
          scale: 2.0,
          pushed: true,
          kb: 0.0,
          expectCompact: true,
          openJump: false,
          captureName: 'repair17_after_360x800_2x_pushed.png',
        ),
        (
          id: '412x915_1x_pushed',
          size: Size(412, 915),
          scale: 1.0,
          pushed: true,
          kb: 0.0,
          expectCompact: true,
          openJump: false,
          captureName: 'repair17_after_412x915_1x_pushed.png',
        ),
        (
          id: '412x915_2x_pushed',
          size: Size(412, 915),
          scale: 2.0,
          pushed: true,
          kb: 0.0,
          expectCompact: true,
          openJump: false,
          captureName: 'repair17_after_412x915_2x_pushed.png',
        ),
        (
          id: '600x900_1x_pushed_wide',
          size: Size(600, 900),
          scale: 1.0,
          pushed: true,
          kb: 0.0,
          expectCompact: false,
          openJump: false,
          captureName: null,
        ),
        (
          id: '360x800_2x_kb_jump_dialog',
          size: Size(360, 800),
          scale: 2.0,
          pushed: true,
          kb: 300.0,
          expectCompact: true,
          openJump: true,
          captureName: 'repair17_after_360x800_2x_kb_jump_dialog.png',
        ),
      ];

      final prevOnError = FlutterError.onError;
      try {
        for (final sc in scenarios) {
          final errors = <FlutterErrorDetails>[];
          FlutterError.onError = (d) => errors.add(d);
          try {
            tester.view.physicalSize = sc.size;
            await tester.pumpWidget(
              _buildHost(
                293,
                scale: sc.scale,
                pushed: sc.pushed,
                keyboardHeight: sc.kb,
              ),
            );
            await _settlePageMode(tester);

            // Uncapped TextScaler
            final screenCtx = tester.element(find.byType(PageModeMushafScreen));
            expect(
              MediaQuery.textScalerOf(screenCtx).scale(1.0),
              closeTo(sc.scale, 0.001),
              reason: '${sc.id}: TextScaler must remain uncapped',
            );

            // AppBar & non-ellipsized title containment (was 0px / 3.4px BEFORE!)
            final appBarFinder = find.byType(AppBar);
            expect(appBarFinder, findsOneWidget);
            final appBarRect = tester.getRect(appBarFinder);
            _assertContainedInVisibleRect(
              tester,
              appBarFinder,
              sc.size,
              keyboardHeight: sc.kb,
              description: '${sc.id} AppBar',
            );

            final titleFinder = find.descendant(
              of: appBarFinder,
              matching: find.text('صفحة ٢٩٣ / ٦٠٤'),
            );
            _assertContainedInVisibleRect(
              tester,
              titleFinder,
              sc.size,
              keyboardHeight: sc.kb,
              description: '${sc.id} AppBar title',
            );
            final titleRect = tester.getRect(titleFinder);
            expect(
              titleRect.width,
              greaterThan(60),
              reason: '${sc.id}: AppBar title must not be crushed, got $titleRect',
            );
            expect(titleRect.top, greaterThanOrEqualTo(appBarRect.top - 0.5));
            expect(titleRect.bottom, lessThanOrEqualTo(appBarRect.bottom + 0.5));
            expect(
              tester.renderObject<RenderParagraph>(titleFinder).didExceedMaxLines,
              isFalse,
              reason: '${sc.id}: AppBar title must not ellipsize/truncate',
            );

            // Action buttons containment
            _assertContainedInVisibleRect(
              tester,
              find.byTooltip('الانتقال إلى صفحة...'),
              sc.size,
              keyboardHeight: sc.kb,
              description: '${sc.id} jump-to-page button',
            );
            if (sc.expectCompact) {
              _assertContainedInVisibleRect(
                tester,
                find.byTooltip('المزيد من خيارات المصحف'),
                sc.size,
                keyboardHeight: sc.kb,
                description: '${sc.id} overflow menu button',
              );
            } else {
              for (final tip in const [
                'تغيير سمة القراءة',
                'الانتقال إلى نمط السور النصي',
                'حفظ موضع القراءة الحالي',
              ]) {
                _assertContainedInVisibleRect(
                  tester,
                  find.byTooltip(tip),
                  sc.size,
                  keyboardHeight: sc.kb,
                  description: '${sc.id} wide action "$tip"',
                );
              }
            }

            // Secondary reading controls bar & dropdown containment
            final controlsBar = find.byKey(const ValueKey('page_mode_controls_bar'));
            _assertContainedInVisibleRect(
              tester,
              controlsBar,
              sc.size,
              keyboardHeight: sc.kb,
              description: '${sc.id} controls bar',
            );
            expect(
              tester.getRect(controlsBar).top,
              greaterThanOrEqualTo(appBarRect.bottom - 0.5),
            );
            _assertContainedInVisibleRect(
              tester,
              find.byType(AppToolbarDropdown<int>),
              sc.size,
              keyboardHeight: sc.kb,
              description: '${sc.id} theme dropdown',
            );

            if (sc.openJump) {
              // Open Jump-to-Page dialog with 300px keyboard active -> verify scrollable AlertDialog has zero overflow,
              // full readable non-truncated label + input + actions above keyboard, AND full title reachable via real dialog scroll
              final dialogSemantics = tester.ensureSemantics();
              try {
                await tester.tap(find.byTooltip('الانتقال إلى صفحة...'));
                await tester.pump();
                await tester.pump(const Duration(milliseconds: 350));
                expect(find.byType(AlertDialog), findsOneWidget);
                final dialogSurface = find
                    .descendant(
                      of: find.byType(AlertDialog),
                      matching: find.byType(Material),
                    )
                    .first;
                _assertContainedInVisibleRect(
                  tester,
                  dialogSurface,
                  sc.size,
                  keyboardHeight: sc.kb,
                  description: '${sc.id} AlertDialog surface above keyboard',
                );
                final dialogScroll = find.descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(SingleChildScrollView),
                );
                expect(dialogScroll, findsOneWidget);

                // 1. Scroll down to INPUT section: verify full static label (no truncation), TextField, semantic association, and actions above keyboard
                final inputLabelFinder = find.descendant(
                  of: find.byType(AlertDialog),
                  matching: find.text('رقم الصفحة (1 - 604)'),
                );
                await _scrollFullyIntoVisibleRect(
                  tester,
                  find.byType(TextField),
                  dialogScroll,
                  sc.size,
                  keyboardHeight: sc.kb,
                  step: 80.0,
                );
                _assertContainedInVisibleRect(
                  tester,
                  inputLabelFinder,
                  sc.size,
                  keyboardHeight: sc.kb,
                  minAncestorViewports: 1,
                  description: '${sc.id} jump dialog full static input label',
                );
                expect(
                  tester.renderObject<RenderParagraph>(inputLabelFinder).didExceedMaxLines,
                  isFalse,
                  reason: '${sc.id}: jump dialog input label must not ellipsize/truncate',
                );
                _assertContainedInVisibleRect(
                  tester,
                  find.byType(TextField),
                  sc.size,
                  keyboardHeight: sc.kb,
                  minAncestorViewports: 1,
                  description: '${sc.id} jump dialog page input inside scrollable clip',
                );
                // Verify semantic association between page TextField and 'رقم الصفحة (1 - 604)'
                final tfSemantics = tester.getSemantics(find.byType(TextField));
                bool hasAssociatedLabel = tfSemantics.label.contains('رقم الصفحة (1 - 604)');
                SemanticsNode? anc = tfSemantics.parent;
                while (!hasAssociatedLabel && anc != null) {
                  if (anc.label.contains('رقم الصفحة (1 - 604)')) {
                    hasAssociatedLabel = true;
                  }
                  anc = anc.parent;
                }
                expect(
                  hasAssociatedLabel,
                  isTrue,
                  reason: '${sc.id}: page TextField must retain semantic label "رقم الصفحة (1 - 604)"',
                );
                _assertContainedInVisibleRect(
                  tester,
                  find.text('إلغاء'),
                  sc.size,
                  keyboardHeight: sc.kb,
                  description: '${sc.id} jump dialog cancel button',
                );
                _assertContainedInVisibleRect(
                  tester,
                  find.text('انتقال'),
                  sc.size,
                  keyboardHeight: sc.kb,
                  description: '${sc.id} jump dialog confirm button',
                );
                await _capturePng(tester, sc.captureName!);
                await _capturePng(
                  tester,
                  'repair17_after_360x800_2x_kb_jump_dialog_input.png',
                );

                // 2. Scroll back UP to TOP section via real dialog scroll -> verify full title exposed & non-ellipsized inside actual viewport clip
                final dialogTitleFinder = find.descendant(
                  of: find.byType(AlertDialog),
                  matching: find.text('الانتقال إلى صفحة'),
                );
                await _scrollFullyIntoVisibleRect(
                  tester,
                  dialogTitleFinder,
                  dialogScroll,
                  sc.size,
                  keyboardHeight: sc.kb,
                  step: 80.0,
                );
                _assertContainedInVisibleRect(
                  tester,
                  dialogTitleFinder,
                  sc.size,
                  keyboardHeight: sc.kb,
                  minAncestorViewports: 1,
                  description: '${sc.id} jump dialog full title after scrolling to top',
                );
                expect(
                  tester.renderObject<RenderParagraph>(dialogTitleFinder).didExceedMaxLines,
                  isFalse,
                  reason: '${sc.id}: jump dialog title must not ellipsize/truncate',
                );
                await _capturePng(
                  tester,
                  'repair17_after_360x800_2x_kb_jump_dialog_top.png',
                );

                await tester.tap(find.text('إلغاء'));
                await tester.pump();
                await tester.pump(const Duration(milliseconds: 400));
              } finally {
                dialogSemantics.dispose();
              }
            } else {
              // Bottom nav bar containment & actual shipping corpus scrollability
              _assertContainedInVisibleRect(
                tester,
                find.byTooltip('الصفحة السابقة'),
                sc.size,
                keyboardHeight: sc.kb,
                description: '${sc.id} previous page button',
              );
              _assertContainedInVisibleRect(
                tester,
                find.byTooltip('الصفحة التالية'),
                sc.size,
                keyboardHeight: sc.kb,
                description: '${sc.id} next page button',
              );
              _assertContainedInVisibleRect(
                tester,
                find.text('صفحة ٢٩٣ من ٦٠٤'),
                sc.size,
                keyboardHeight: sc.kb,
                description: '${sc.id} bottom bar page indicator',
              );

              if (sc.captureName != null) {
                await _capturePng(tester, sc.captureName!);
              }

              // Scroll reachability inside page content SingleChildScrollView
              final pageScroll = find.byType(SingleChildScrollView).first;
              final scrollable = tester.state<ScrollableState>(
                find.descendant(of: pageScroll, matching: find.byType(Scrollable)),
              );
              final beforePx = scrollable.position.pixels;
              await tester.drag(pageScroll, const Offset(0, -200));
              await tester.pump(const Duration(milliseconds: 200));
              if (scrollable.position.maxScrollExtent > 0) {
                expect(
                  scrollable.position.pixels,
                  greaterThan(beforePx),
                  reason: '${sc.id}: Mushaf page content must scroll cleanly',
                );
              }
            }

            // Teardown BEFORE checking errors and restoring FlutterError.onError
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(milliseconds: 450));

            expect(
              errors,
              isEmpty,
              reason:
                  'Scenario ${sc.id} produced unexpected FlutterErrors across full lifecycle: ${errors.map((e) => e.exceptionAsString()).join(" | ")}',
            );
          } finally {
            FlutterError.onError = prevOnError;
          }
        }
      } finally {
        FlutterError.onError = prevOnError;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );

  testWidgets(
    'PageModeMushafScreen supports pointer and SemanticsAction.tap for theme dropdown, jump dialog, bottom nav, and all moved compact menu items at 360x800 @ 2.0x',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.init();
      const viewport = Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = viewport;

      late int page293SurahId;
      late int page293StartAyah;
      await tester.runAsync(() async {
        await QuranRepository.loadSurahs();
        await QuranRepository.getAyahsForPage(293);
        await QuranRepository.getAyahsForPage(294);
        await QuranRepository.getAyahsForPage(295);
        final meta = await QuranRepository.getPageMetadata(293);
        page293SurahId = meta!.surahId;
        page293StartAyah = meta.startAyah;
        await QuranRepository.getAyahsForSurah(page293SurahId);
      });

      final errors = <FlutterErrorDetails>[];
      final prevOnError = FlutterError.onError;
      FlutterError.onError = (d) => errors.add(d);
      final semanticsHandle = tester.ensureSemantics();

      try {
        await tester.pumpWidget(_buildHost(293, scale: 2.0, pushed: true));
        await _settlePageMode(tester);

        // 1. Theme dropdown: pointer open/select ('ليلي داكن') + SemanticsAction.tap open/select ('ورقي مصحفي' & 'تلقائي')
        await tester.tap(find.byType(AppToolbarDropdown<int>));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(find.text('ليلي داكن').last);
        await _settlePageMode(tester);
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
          equals(const Color(0xFF141716)),
        );

        final themeDropSem1 = _findTappableNode(tester, 'مظهر صفحة المصحف');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          themeDropSem1.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final sepiaOpt = _findAllTappableNodes(tester, 'ورقي مصحفي').last;
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          sepiaOpt.id,
          SemanticsAction.tap,
        );
        await _settlePageMode(tester);
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
          equals(const Color(0xFFF7F1E3)),
        );

        final themeDropSem2 = _findTappableNode(tester, 'مظهر صفحة المصحف');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          themeDropSem2.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final autoOpt = _findAllTappableNodes(tester, 'تلقائي').last;
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          autoOpt.id,
          SemanticsAction.tap,
        );
        await _settlePageMode(tester);
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
          equals(const Color(0xFFFCFCFA)),
        );

        // 2. Direct jump button: pointer open/jump to 295 + SemanticsAction.tap open/jump back to 293
        await tester.tap(find.byTooltip('الانتقال إلى صفحة...'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.enterText(find.byType(TextField), '295');
        await tester.pump();
        await tester.tap(find.text('انتقال'));
        await _settlePageMode(tester);
        expect(find.text('صفحة ٢٩٥ / ٦٠٤'), findsOneWidget);

        final jumpSemBtn = _findTappableNode(tester, 'الانتقال إلى صفحة...');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          jumpSemBtn.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.enterText(find.byType(TextField), '293');
        await tester.pump();
        final confirmJumpNode = _findTappableNode(tester, 'انتقال');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          confirmJumpNode.id,
          SemanticsAction.tap,
        );
        await _settlePageMode(tester);
        expect(find.text('صفحة ٢٩٣ / ٦٠٤'), findsOneWidget);

        // 3. Bottom overlay navigation: pointer next -> 294, SemanticsAction.tap prev -> 293
        await tester.tap(find.byTooltip('الصفحة التالية'));
        await _settlePageMode(tester);
        expect(find.text('صفحة ٢٩٤ / ٦٠٤'), findsOneWidget);

        final prevPageNode = _findTappableNode(tester, 'الصفحة السابقة');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          prevPageNode.id,
          SemanticsAction.tap,
        );
        await _settlePageMode(tester);
        expect(find.text('صفحة ٢٩٣ / ٦٠٤'), findsOneWidget);

        // 4. Moved compact menu item 1 ('تغيير سمة القراءة'): pointer open + capture PNG + pointer select, then SemanticsAction.tap open + select
        await tester.tap(find.byTooltip('المزيد من خيارات المصحف'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        _assertCompactMenuContained(tester, viewport);
        await _capturePng(tester, 'repair17_after_360x800_2x_pushed_menu_open.png');

        await tester.tap(find.text('تغيير سمة القراءة'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
          equals(const Color(0xFFF7F1E3)),
        );
        expect(find.text('وضع القراءة: ورقي مصحفي'), findsOneWidget);

        final menuSem1 = _findTappableNode(tester, 'المزيد من خيارات المصحف');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          menuSem1.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        _assertCompactMenuContained(tester, viewport);
        final cycleThemeItem = _findTappableNode(tester, 'تغيير سمة القراءة');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          cycleThemeItem.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
          equals(const Color(0xFF141716)),
        );
        expect(find.text('وضع القراءة: ليلي داكن'), findsOneWidget);

        // 5. Moved compact menu item 2 ('حفظ موضع القراءة الحالي'): pointer toggle ON + SemanticsAction.tap toggle OFF
        await tester.tap(find.byTooltip('المزيد من خيارات المصحف'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        _assertCompactMenuContained(tester, viewport);
        await tester.tap(find.text('حفظ موضع القراءة الحالي'));
        await _settlePageMode(tester);
        expect(
          SettingsService.instance.isBookmarked(page293SurahId, page293StartAyah),
          isTrue,
        );

        final menuSem2 = _findTappableNode(tester, 'المزيد من خيارات المصحف');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          menuSem2.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        _assertCompactMenuContained(tester, viewport);
        final bookmarkItem = _findTappableNode(tester, 'حفظ موضع القراءة الحالي');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          bookmarkItem.id,
          SemanticsAction.tap,
        );
        await _settlePageMode(tester);
        expect(
          SettingsService.instance.isBookmarked(page293SurahId, page293StartAyah),
          isFalse,
        );

        // 6. Moved compact menu item 3 ('الانتقال إلى نمط السور النصي'):
        //    (a) SemanticsAction.tap open + select at 360x800 @ 2.0x -> routes to SurahReaderScreen(page293SurahId) with ZERO errors
        final menuSem3 = _findTappableNode(tester, 'المزيد من خيارات المصحف');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          menuSem3.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        _assertCompactMenuContained(tester, viewport);
        final surahModeItem = _findTappableNode(tester, 'الانتقال إلى نمط السور النصي');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          surahModeItem.id,
          SemanticsAction.tap,
        );
        await _settlePageMode(tester);
        expect(find.byType(SurahReaderScreen), findsOneWidget);
        expect(
          tester.widget<SurahReaderScreen>(find.byType(SurahReaderScreen)).surah.id,
          equals(page293SurahId),
        );

        //    (b) Pointer open + select at 360x800 @ 2.0x (fresh host) -> routes to SurahReaderScreen(page293SurahId) with ZERO errors
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpWidget(_buildHost(293, scale: 2.0, pushed: true));
        await _settlePageMode(tester);

        await tester.tap(find.byTooltip('المزيد من خيارات المصحف'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        _assertCompactMenuContained(tester, viewport);
        await tester.tap(find.text('الانتقال إلى نمط السور النصي'));
        await _settlePageMode(tester);
        expect(find.byType(SurahReaderScreen), findsOneWidget);
        expect(
          tester.widget<SurahReaderScreen>(find.byType(SurahReaderScreen)).surah.id,
          equals(page293SurahId),
        );

        // Teardown BEFORE asserting zero errors and restoring FlutterError.onError
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 450));

        expect(
          errors,
          isEmpty,
          reason:
              'Unexpected FlutterErrors during 360x800 @ 2.0x PageModeMushafScreen controls/navigation: ${errors.map((e) => e.exceptionAsString()).join(" | ")}',
        );
      } finally {
        semanticsHandle.dispose();
        FlutterError.onError = prevOnError;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );
}
