import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/core/models/ayah.dart';
import 'package:almomin/core/models/surah.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/mushaf/widgets/tafsir_viewer_sheet.dart';

const bool _kCapturePixels = bool.fromEnvironment(
  'CAPTURE_REPAIR19_PIXELS',
  defaultValue: false,
);
const String _kCaptureOutDir = String.fromEnvironment(
  'CAPTURE_REPAIR19_OUT_DIR',
  defaultValue: '',
);
const String _kMaterialIconsFontPath = String.fromEnvironment(
  'MATERIAL_ICONS_FONT',
  defaultValue: '',
);

final GlobalKey _kBoundaryKey = GlobalKey();

typedef _CapturedError = ({
  String message,
  String fullDetails,
});

Future<void> _loadRealFonts() async {
  final cairo = File('assets/fonts/Cairo-Regular.ttf');
  if (cairo.existsSync()) {
    final bytes = cairo.readAsBytesSync();
    for (final family in ['Cairo', 'Roboto']) {
      final loader = FontLoader(family);
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  }
  final amiri = FontLoader('Amiri');
  for (final path in [
    'assets/fonts/Amiri-Regular.ttf',
    'assets/fonts/Amiri-Bold.ttf',
  ]) {
    final f = File(path);
    if (f.existsSync()) {
      amiri.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
    }
  }
  await amiri.load();
  for (final path in [
    if (_kMaterialIconsFontPath.isNotEmpty) _kMaterialIconsFontPath,
    'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
    'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]) {
    final f = File(path);
    if (f.existsSync()) {
      final loader = FontLoader('MaterialIcons');
      loader.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
      await loader.load();
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
    Directory(_kCaptureOutDir).createSync(recursive: true);
    File('$_kCaptureOutDir/$fileName').writeAsBytesSync(
      byteData!.buffer.asUint8List(),
    );
  });
}

Future<void> _waitForTafsirLoaded(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  for (int i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pump(const Duration(milliseconds: 150));
}

Widget _buildHost({
  required Surah surah,
  required Ayah ayah,
  required double textScale,
  double keyboardBottom = 0,
  bool isDark = false,
}) {
  return RepaintBoundary(
    key: _kBoundaryKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
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
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () =>
                  TafsirViewerSheet.show(ctx, surah: surah, ayah: ayah),
              child: const Text('OPEN_TAFSIR_FOOTER'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openTafsirSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.tap(find.text('OPEN_TAFSIR_FOOTER'));
  await _waitForTafsirLoaded(tester);
  expect(find.byType(TafsirViewerSheet), findsOneWidget);
}

Rect _actualVisibleClipRect(
  WidgetTester tester,
  Finder target,
  Size viewportSize, {
  required double keyboardBottom,
}) {
  final screenVisible = Rect.fromLTWH(
    0,
    0,
    viewportSize.width,
    (viewportSize.height - keyboardBottom).clamp(0.0, viewportSize.height),
  );
  final sheetRect = tester.getRect(find.byType(TafsirViewerSheet));
  Rect clip = screenVisible.intersect(sheetRect);

  final element = tester.element(target);
  RenderObject? ro = element.renderObject;
  while (ro != null) {
    if (ro is RenderAbstractViewport && ro is RenderBox) {
      final box = ro as RenderBox;
      final topLeft = box.localToGlobal(Offset.zero);
      final vpRect = topLeft & box.size;
      clip = clip.intersect(vpRect);
    }
    ro = ro.parent;
  }
  return clip;
}

void _expectFullyContainedInActualClip(
  WidgetTester tester,
  Finder target,
  Size viewportSize,
  String label, {
  required double keyboardBottom,
}) {
  expect(target, findsOneWidget, reason: '[$label] target must exist');
  final rect = tester.getRect(target);
  final clip = _actualVisibleClipRect(
    tester,
    target,
    viewportSize,
    keyboardBottom: keyboardBottom,
  );
  expect(
    clip.isEmpty,
    isFalse,
    reason: '[$label] actual visible clip rect must be non-empty: $clip',
  );
  expect(
    rect.left,
    greaterThanOrEqualTo(clip.left - 0.5),
    reason: '[$label] left ${rect.left} clipped by ${clip.left}',
  );
  expect(
    rect.right,
    lessThanOrEqualTo(clip.right + 0.5),
    reason: '[$label] right ${rect.right} clipped by ${clip.right}',
  );
  expect(
    rect.top,
    greaterThanOrEqualTo(clip.top - 0.5),
    reason: '[$label] top ${rect.top} clipped by ${clip.top}',
  );
  expect(
    rect.bottom,
    lessThanOrEqualTo(clip.bottom + 0.5),
    reason: '[$label] bottom ${rect.bottom} clipped by ${clip.bottom} (keyboardBottom=$keyboardBottom)',
  );
}

void _expectTextNotTruncated(
  WidgetTester tester,
  Finder textFinder,
  String label,
) {
  expect(textFinder, findsOneWidget, reason: '[$label] text must exist');
  final renderObject = tester.renderObject(textFinder);
  expect(
    renderObject,
    isA<RenderParagraph>(),
    reason: '[$label] expected RenderParagraph',
  );
  expect(
    (renderObject as RenderParagraph).didExceedMaxLines,
    isFalse,
    reason: '[$label] text must not truncate/exceed maxLines',
  );
}

Future<void> _scrollListTargetIntoActualClip(
  WidgetTester tester,
  Finder target,
  Size viewportSize,
  String label, {
  required double keyboardBottom,
}) async {
  final listFinder = find.descendant(
    of: find.byType(TafsirViewerSheet),
    matching: find.byType(ListView),
  );
  expect(listFinder, findsOneWidget, reason: '[$label] ListView must exist');
  final scrollableState = tester.state<ScrollableState>(
    find.descendant(of: listFinder, matching: find.byType(Scrollable)),
  );

  for (int step = 0; step < 30; step++) {
    if (target.evaluate().isNotEmpty) {
      final rect = tester.getRect(target);
      final clip = _actualVisibleClipRect(
        tester,
        target,
        viewportSize,
        keyboardBottom: keyboardBottom,
      );
      if (rect.top >= clip.top - 0.5 && rect.bottom <= clip.bottom + 0.5) {
        return;
      }
      final pos = scrollableState.position;
      if (rect.bottom > clip.bottom) {
        final delta = (rect.bottom - clip.bottom + 16).clamp(16.0, 96.0);
        final next = (pos.pixels + delta).clamp(
          pos.minScrollExtent,
          pos.maxScrollExtent,
        );
        if ((next - pos.pixels).abs() < 0.5) break;
        pos.jumpTo(next);
      } else if (rect.top < clip.top) {
        final delta = (clip.top - rect.top + 16).clamp(16.0, 96.0);
        final next = (pos.pixels - delta).clamp(
          pos.minScrollExtent,
          pos.maxScrollExtent,
        );
        if ((next - pos.pixels).abs() < 0.5) break;
        pos.jumpTo(next);
      }
      await tester.pump();
    } else {
      final pos = scrollableState.position;
      final next = (pos.pixels + 80).clamp(
        pos.minScrollExtent,
        pos.maxScrollExtent,
      );
      if ((next - pos.pixels).abs() < 0.5) break;
      pos.jumpTo(next);
      await tester.pump();
    }
  }
}

Finder _footerButtonFinder(String labelText) {
  return find.ancestor(
    of: find.text(labelText),
    matching: find.byType(TextButton),
  );
}

SemanticsNode _findFooterButtonSemantics(
  WidgetTester tester,
  String labelText,
) {
  return tester.getSemantics(_footerButtonFinder(labelText));
}

void _verifyFooterAndHeaderContainment(
  WidgetTester tester, {
  required Surah surah,
  required int ayahNumber,
  required Size viewportSize,
  required double keyboardBottom,
  required String scenarioLabel,
}) {
  final headerTitle = find.text('سورة ${surah.nameAr} — الآية $ayahNumber');
  _expectFullyContainedInActualClip(
    tester,
    headerTitle,
    viewportSize,
    '$scenarioLabel/headerTitle',
    keyboardBottom: keyboardBottom,
  );
  _expectTextNotTruncated(tester, headerTitle, '$scenarioLabel/headerTitle');

  // Verify all 4 header controls remain intact and above keyboard
  for (final tip in const [
    'تغيير حجم خط التفسير',
    'نسخ التفسير',
    'مشاركة التفسير',
    'إغلاق',
  ]) {
    final hdrBtn = find.ancestor(
      of: find.byTooltip(tip),
      matching: find.byType(IconButton),
    );
    _expectFullyContainedInActualClip(
      tester,
      hdrBtn,
      viewportSize,
      '$scenarioLabel/header/$tip',
      keyboardBottom: keyboardBottom,
    );
  }

  final counterText = find.text('الآية $ayahNumber من ${surah.ayahCount}');
  final prevLabel = find.text('الآية السابقة');
  final nextLabel = find.text('الآية التالية');
  final prevBtn = _footerButtonFinder('الآية السابقة');
  final nextBtn = _footerButtonFinder('الآية التالية');

  _expectFullyContainedInActualClip(
    tester,
    counterText,
    viewportSize,
    '$scenarioLabel/footerCounter',
    keyboardBottom: keyboardBottom,
  );
  _expectTextNotTruncated(tester, counterText, '$scenarioLabel/footerCounter');

  _expectFullyContainedInActualClip(
    tester,
    prevBtn,
    viewportSize,
    '$scenarioLabel/prevBtn',
    keyboardBottom: keyboardBottom,
  );
  _expectTextNotTruncated(tester, prevLabel, '$scenarioLabel/prevLabel');
  expect(
    tester.getRect(prevBtn).height,
    greaterThanOrEqualTo(48.0 - 0.5),
    reason: '[$scenarioLabel/prevBtn] height must be >= 48',
  );

  _expectFullyContainedInActualClip(
    tester,
    nextBtn,
    viewportSize,
    '$scenarioLabel/nextBtn',
    keyboardBottom: keyboardBottom,
  );
  _expectTextNotTruncated(tester, nextLabel, '$scenarioLabel/nextLabel');
  expect(
    tester.getRect(nextBtn).height,
    greaterThanOrEqualTo(48.0 - 0.5),
    reason: '[$scenarioLabel/nextBtn] height must be >= 48',
  );

  // Explicit check that entire footer sits strictly above keyboard fold
  final visibleFoldY = viewportSize.height - keyboardBottom;
  expect(
    tester.getRect(counterText).bottom,
    lessThanOrEqualTo(visibleFoldY + 0.5),
    reason: '[$scenarioLabel] footer counter must be above keyboard fold $visibleFoldY',
  );
  expect(
    tester.getRect(prevBtn).bottom,
    lessThanOrEqualTo(visibleFoldY + 0.5),
    reason: '[$scenarioLabel] prev button must be above keyboard fold $visibleFoldY',
  );
  expect(
    tester.getRect(nextBtn).bottom,
    lessThanOrEqualTo(visibleFoldY + 0.5),
    reason: '[$scenarioLabel] next button must be above keyboard fold $visibleFoldY',
  );

  // Zero overlap between counter, prev button, and next button
  final rects = <(String, Rect)>[
    ('counter', tester.getRect(counterText)),
    ('prevBtn', tester.getRect(prevBtn)),
    ('nextBtn', tester.getRect(nextBtn)),
  ];
  for (int i = 0; i < rects.length; i++) {
    for (int j = i + 1; j < rects.length; j++) {
      final inter = rects[i].$2.intersect(rects[j].$2);
      expect(
        inter.width > 1.0 && inter.height > 1.0,
        isFalse,
        reason:
            '[$scenarioLabel] footer elements ${rects[i].$1} (${rects[i].$2}) and ${rects[j].$1} (${rects[j].$2}) overlap',
      );
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Surah fatiha;
  late Ayah fatihaAyah2;
  late Surah alImran;
  late Ayah alImranAyah200;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
    await _loadRealFonts();
    final surahs = await QuranRepository.loadSurahs();
    fatiha = surahs.firstWhere((s) => s.id == 1);
    fatihaAyah2 = (await QuranRepository.getAyah(1, 2))!;
    alImran = surahs.firstWhere((s) => s.id == 3);
    alImranAyah200 = (await QuranRepository.getAyah(3, 200))!;
  });

  group('Repair 19 — TafsirViewerSheet Footer Layout, Boundaries & Accessibility', () {
    testWidgets(
      'Zero errors post-teardown, full footer/header containment, non-truncation, and scroll reachability across 360/412 (1x/2x kb & nokb), long title, wide, and dark mode',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final scenarios = <({
          String label,
          Size size,
          double scale,
          double kb,
          Surah surah,
          Ayah ayah,
          bool isDark,
          String captureName,
        })>[
          (
            label: '360x800_1x_kb',
            size: const Size(360, 800),
            scale: 1.0,
            kb: 300,
            surah: fatiha,
            ayah: fatihaAyah2,
            isDark: false,
            captureName: 'repair19_after_360x800_1x_kb.png',
          ),
          (
            label: '360x800_2x_kb',
            size: const Size(360, 800),
            scale: 2.0,
            kb: 300,
            surah: fatiha,
            ayah: fatihaAyah2,
            isDark: false,
            captureName: 'repair19_after_360x800_2x_kb.png',
          ),
          (
            label: '360x800_2x_nokb',
            size: const Size(360, 800),
            scale: 2.0,
            kb: 0,
            surah: fatiha,
            ayah: fatihaAyah2,
            isDark: false,
            captureName: 'repair19_after_360x800_2x_nokb.png',
          ),
          (
            label: '412x915_1x_kb',
            size: const Size(412, 915),
            scale: 1.0,
            kb: 300,
            surah: fatiha,
            ayah: fatihaAyah2,
            isDark: false,
            captureName: 'repair19_after_412x915_1x_kb.png',
          ),
          (
            label: '412x915_2x_kb',
            size: const Size(412, 915),
            scale: 2.0,
            kb: 300,
            surah: fatiha,
            ayah: fatihaAyah2,
            isDark: false,
            captureName: 'repair19_after_412x915_2x_kb.png',
          ),
          (
            label: '412x915_2x_nokb',
            size: const Size(412, 915),
            scale: 2.0,
            kb: 0,
            surah: fatiha,
            ayah: fatihaAyah2,
            isDark: false,
            captureName: 'repair19_after_412x915_2x_nokb.png',
          ),
          (
            label: '360x800_2x_kb_long_title',
            size: const Size(360, 800),
            scale: 2.0,
            kb: 300,
            surah: alImran,
            ayah: alImranAyah200,
            isDark: false,
            captureName: 'repair19_after_360x800_2x_kb_long_title.png',
          ),
          (
            label: '640x800_1x_wide',
            size: const Size(640, 800),
            scale: 1.0,
            kb: 0,
            surah: fatiha,
            ayah: fatihaAyah2,
            isDark: false,
            captureName: 'repair19_after_640x800_1x_wide.png',
          ),
          (
            label: '360x800_2x_dark',
            size: const Size(360, 800),
            scale: 2.0,
            kb: 0,
            surah: fatiha,
            ayah: fatihaAyah2,
            isDark: true,
            captureName: 'repair19_after_360x800_2x_dark.png',
          ),
        ];

        final semantics = tester.ensureSemantics();
        try {
          for (final sc in scenarios) {
            final errors = <_CapturedError>[];
            final prevOnError = FlutterError.onError;
            FlutterError.onError = (d) => errors.add((
                  message: d.exceptionAsString(),
                  fullDetails: d.toString(),
                ));
            try {
              tester.view.physicalSize = sc.size;
              await tester.pumpWidget(
                _buildHost(
                  surah: sc.surah,
                  ayah: sc.ayah,
                  textScale: sc.scale,
                  keyboardBottom: sc.kb,
                  isDark: sc.isDark,
                ),
              );
              await _openTafsirSheet(tester);

              _verifyFooterAndHeaderContainment(
                tester,
                surah: sc.surah,
                ayahNumber: sc.ayah.ayahNumber,
                viewportSize: sc.size,
                keyboardBottom: sc.kb,
                scenarioLabel: sc.label,
              );

              await _capturePng(tester, sc.captureName);

              // Verify ListView body still scrolls cleanly inside actual ancestor RenderAbstractViewport clip above keyboard
              final listenBtn = find.ancestor(
                of: find.text('استمع للآية'),
                matching: find.byType(TextButton),
              );
              await _scrollListTargetIntoActualClip(
                tester,
                listenBtn,
                sc.size,
                '${sc.label}/listenBtn',
                keyboardBottom: sc.kb,
              );
              _expectFullyContainedInActualClip(
                tester,
                listenBtn,
                sc.size,
                '${sc.label}/listenBtn',
                keyboardBottom: sc.kb,
              );

              // Footer & header remain intact above keyboard after body scrolling
              _verifyFooterAndHeaderContainment(
                tester,
                surah: sc.surah,
                ayahNumber: sc.ayah.ayahNumber,
                viewportSize: sc.size,
                keyboardBottom: sc.kb,
                scenarioLabel: '${sc.label}/postScroll',
              );

              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump(const Duration(milliseconds: 250));
            } finally {
              FlutterError.onError = prevOnError;
            }

            expect(
              errors,
              isEmpty,
              reason:
                  '[${sc.label}] Expected ZERO FlutterErrors post-teardown, got: ${errors.map((e) => e.message).join(" | ")}',
            );
          }
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'Pointer and SemanticsAction.tap prev/next Ayah state updates and first/last Surah boundaries at 360x800 @ 2.0x + 300px keyboard with zero errors',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(360, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final semantics = tester.ensureSemantics();
        final errors = <_CapturedError>[];
        final prevOnError = FlutterError.onError;
        FlutterError.onError = (d) => errors.add((
              message: d.exceptionAsString(),
              fullDetails: d.toString(),
            ));

        try {
          // --- Part A: Al-Fatihah Ayah 2 -> Next (pointer) -> Prev (semantic) -> Prev to Ayah 1 first boundary -> Next (semantic) ---
          await tester.pumpWidget(
            _buildHost(
              surah: fatiha,
              ayah: fatihaAyah2,
              textScale: 2.0,
              keyboardBottom: 300,
            ),
          );
          await _openTafsirSheet(tester);

          _verifyFooterAndHeaderContainment(
            tester,
            surah: fatiha,
            ayahNumber: 2,
            viewportSize: const Size(360, 800),
            keyboardBottom: 300,
            scenarioLabel: '360_2x_kb_fatiha_ayah2_initial',
          );
          expect(
            tester.widget<TextButton>(_footerButtonFinder('الآية السابقة')).onPressed,
            isNotNull,
          );
          expect(
            tester.widget<TextButton>(_footerButtonFinder('الآية التالية')).onPressed,
            isNotNull,
          );

          // 1. Pointer tap Next -> Ayah 3 (tapping above 500px keyboard fold)
          await tester.tap(_footerButtonFinder('الآية التالية'));
          await _waitForTafsirLoaded(tester);
          _verifyFooterAndHeaderContainment(
            tester,
            surah: fatiha,
            ayahNumber: 3,
            viewportSize: const Size(360, 800),
            keyboardBottom: 300,
            scenarioLabel: '360_2x_kb_fatiha_ayah3',
          );

          // 2. SemanticsAction.tap Prev -> Ayah 2
          final prevNodeAt3 = _findFooterButtonSemantics(tester, 'الآية السابقة');
          expect(
            prevNodeAt3.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            prevNodeAt3.id,
            SemanticsAction.tap,
          );
          await _waitForTafsirLoaded(tester);
          _verifyFooterAndHeaderContainment(
            tester,
            surah: fatiha,
            ayahNumber: 2,
            viewportSize: const Size(360, 800),
            keyboardBottom: 300,
            scenarioLabel: '360_2x_kb_fatiha_ayah2_after_semantic_prev',
          );

          // 3. Pointer tap Prev -> Ayah 1 (first boundary: Prev disabled, Next enabled)
          await tester.tap(_footerButtonFinder('الآية السابقة'));
          await _waitForTafsirLoaded(tester);
          _verifyFooterAndHeaderContainment(
            tester,
            surah: fatiha,
            ayahNumber: 1,
            viewportSize: const Size(360, 800),
            keyboardBottom: 300,
            scenarioLabel: '360_2x_kb_fatiha_ayah1_boundary',
          );
          expect(
            tester.widget<TextButton>(_footerButtonFinder('الآية السابقة')).onPressed,
            isNull,
            reason: 'Prev button must be disabled at Ayah 1 boundary',
          );
          expect(
            _findFooterButtonSemantics(tester, 'الآية السابقة')
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse,
            reason: 'Prev button must not expose tap action at Ayah 1 boundary',
          );
          expect(
            tester.widget<TextButton>(_footerButtonFinder('الآية التالية')).onPressed,
            isNotNull,
          );

          // 4. SemanticsAction.tap Next from Ayah 1 -> Ayah 2 (Prev re-enabled)
          final nextNodeAt1 = _findFooterButtonSemantics(tester, 'الآية التالية');
          expect(
            nextNodeAt1.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            nextNodeAt1.id,
            SemanticsAction.tap,
          );
          await _waitForTafsirLoaded(tester);
          _verifyFooterAndHeaderContainment(
            tester,
            surah: fatiha,
            ayahNumber: 2,
            viewportSize: const Size(360, 800),
            keyboardBottom: 300,
            scenarioLabel: '360_2x_kb_fatiha_ayah2_after_semantic_next',
          );
          expect(
            tester.widget<TextButton>(_footerButtonFinder('الآية السابقة')).onPressed,
            isNotNull,
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 250));

          // --- Part B: Al-Imran Ayah 200 (last boundary: Next disabled, Prev enabled) -> Prev (semantic) -> Next (pointer) ---
          await tester.pumpWidget(
            _buildHost(
              surah: alImran,
              ayah: alImranAyah200,
              textScale: 2.0,
              keyboardBottom: 300,
            ),
          );
          await _openTafsirSheet(tester);

          _verifyFooterAndHeaderContainment(
            tester,
            surah: alImran,
            ayahNumber: 200,
            viewportSize: const Size(360, 800),
            keyboardBottom: 300,
            scenarioLabel: '360_2x_kb_alimran_ayah200_boundary',
          );
          expect(
            tester.widget<TextButton>(_footerButtonFinder('الآية التالية')).onPressed,
            isNull,
            reason: 'Next button must be disabled at final Ayah 200 boundary',
          );
          expect(
            _findFooterButtonSemantics(tester, 'الآية التالية')
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse,
            reason: 'Next button must not expose tap action at final Ayah 200 boundary',
          );
          expect(
            tester.widget<TextButton>(_footerButtonFinder('الآية السابقة')).onPressed,
            isNotNull,
          );

          // SemanticsAction.tap Prev -> Ayah 199 (Next re-enabled)
          final prevNodeAt200 = _findFooterButtonSemantics(tester, 'الآية السابقة');
          expect(
            prevNodeAt200.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            prevNodeAt200.id,
            SemanticsAction.tap,
          );
          await _waitForTafsirLoaded(tester);
          _verifyFooterAndHeaderContainment(
            tester,
            surah: alImran,
            ayahNumber: 199,
            viewportSize: const Size(360, 800),
            keyboardBottom: 300,
            scenarioLabel: '360_2x_kb_alimran_ayah199',
          );
          expect(
            tester.widget<TextButton>(_footerButtonFinder('الآية التالية')).onPressed,
            isNotNull,
          );

          // Pointer tap Next -> back to Ayah 200 (Next disabled again)
          await tester.tap(_footerButtonFinder('الآية التالية'));
          await _waitForTafsirLoaded(tester);
          _verifyFooterAndHeaderContainment(
            tester,
            surah: alImran,
            ayahNumber: 200,
            viewportSize: const Size(360, 800),
            keyboardBottom: 300,
            scenarioLabel: '360_2x_kb_alimran_ayah200_return',
          );
          expect(
            tester.widget<TextButton>(_footerButtonFinder('الآية التالية')).onPressed,
            isNull,
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 250));
        } finally {
          semantics.dispose();
          FlutterError.onError = prevOnError;
        }

        expect(
          errors,
          isEmpty,
          reason:
              '[360_2x_kb_boundaries] Expected ZERO FlutterErrors post-teardown, got: ${errors.map((e) => e.message).join(" | ")}',
        );
      },
    );

    testWidgets(
      'Real reading viewport clip height, real pointer drag scroll past dropdowns to Ayah & Tafsir text, complete rendered lines, full end-of-text reachability, and scrolled reading captures at 360/412 @ 2.0x + 300px keyboard & long title',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        List<({double top, double bottom})> extractGlobalLineBands(
          RenderParagraph paragraph,
        ) {
          final plain = paragraph.text.toPlainText();
          if (plain.isEmpty) return const [];
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: plain.length),
          );
          final bands = <({double top, double bottom})>[];
          for (final box in boxes) {
            if (box.bottom - box.top < 1.0) continue;
            final gTop = paragraph.localToGlobal(Offset(0, box.top)).dy;
            final gBottom = paragraph.localToGlobal(Offset(0, box.bottom)).dy;
            var merged = false;
            for (int i = 0; i < bands.length; i++) {
              final b = bands[i];
              if ((gTop - b.top).abs() < 4.0 || (gBottom - b.bottom).abs() < 4.0) {
                bands[i] = (
                  top: gTop < b.top ? gTop : b.top,
                  bottom: gBottom > b.bottom ? gBottom : b.bottom,
                );
                merged = true;
                break;
              }
            }
            if (!merged) {
              bands.add((top: gTop, bottom: gBottom));
            }
          }
          bands.sort((a, b) => a.top.compareTo(b.top));
          return bands;
        }

        int countCompleteLinesInClip(
          RenderParagraph paragraph,
          Rect clipRect,
        ) {
          final bands = extractGlobalLineBands(paragraph);
          int count = 0;
          for (final band in bands) {
            if (band.top >= clipRect.top - 1.5 &&
                band.bottom <= clipRect.bottom + 1.5) {
              count++;
            }
          }
          return count;
        }

        final readingScenarios = <({
          String label,
          Size size,
          Surah surah,
          Ayah ayah,
        })>[
          (
            label: '360x800_2x_kb',
            size: const Size(360, 800),
            surah: fatiha,
            ayah: fatihaAyah2,
          ),
          (
            label: '412x915_2x_kb',
            size: const Size(412, 915),
            surah: fatiha,
            ayah: fatihaAyah2,
          ),
          (
            label: '360x800_2x_kb_long_title',
            size: const Size(360, 800),
            surah: alImran,
            ayah: alImranAyah200,
          ),
        ];

        final semantics = tester.ensureSemantics();
        try {
          for (final sc in readingScenarios) {
            final errors = <_CapturedError>[];
            final prevOnError = FlutterError.onError;
            FlutterError.onError = (d) => errors.add((
                  message: d.exceptionAsString(),
                  fullDetails: d.toString(),
                ));
            try {
              tester.view.physicalSize = sc.size;
              await tester.pumpWidget(
                _buildHost(
                  surah: sc.surah,
                  ayah: sc.ayah,
                  textScale: 2.0,
                  keyboardBottom: 300,
                ),
              );
              await _openTafsirSheet(tester);

              final listFinder = find.descendant(
                of: find.byType(TafsirViewerSheet),
                matching: find.byType(ListView),
              );
              expect(listFinder, findsOneWidget);
              final scrollableState = tester.state<ScrollableState>(
                find.descendant(of: listFinder, matching: find.byType(Scrollable)),
              );

              // Measure actual ListView clip rect above 300px keyboard
              final screenVisible = Rect.fromLTWH(
                0,
                0,
                sc.size.width,
                sc.size.height - 300,
              );
              final sheetRect = tester.getRect(find.byType(TafsirViewerSheet));
              final listRect = tester.getRect(listFinder);
              final listClipRect = screenVisible
                  .intersect(sheetRect)
                  .intersect(listRect);

              expect(
                listClipRect.height,
                greaterThanOrEqualTo(180.0),
                reason:
                    '[${sc.label}] ListView reading viewport height (${listClipRect.height}) must be usable (>= 180px) above 300px keyboard',
              );

              final ayahTextFinder = find
                  .descendant(
                    of: find.byWidgetPredicate(
                      (w) =>
                          w is Semantics &&
                          (w.properties.label?.startsWith('نص الآية رقم') ??
                              false),
                    ),
                    matching: find.byType(Text),
                  )
                  .first;
              final tafsirTextFinder = find
                  .descendant(
                    of: find.byWidgetPredicate(
                      (w) =>
                          w is Semantics &&
                          (w.properties.label?.startsWith('شرح التفسير:') ??
                              false),
                    ),
                    matching: find.byType(Text),
                  )
                  .first;

              // 1. Real pointer drag scroll past dropdowns onto real Ayah text
              final initialPixels = scrollableState.position.pixels;
              expect(initialPixels, closeTo(0.0, 0.5));
              for (int step = 0; step < 20; step++) {
                if (scrollableState.position.pixels > initialPixels + 20.0 &&
                    ayahTextFinder.evaluate().isNotEmpty) {
                  final ayahPara =
                      tester.renderObject<RenderParagraph>(ayahTextFinder);
                  final ayahLines = extractGlobalLineBands(ayahPara);
                  final visibleAyahLines =
                      countCompleteLinesInClip(ayahPara, listClipRect);
                  if (ayahLines.isNotEmpty &&
                      ayahLines.first.top >= listClipRect.top - 1.5 &&
                      visibleAyahLines >= 2) {
                    break;
                  }
                }
                await tester.drag(listFinder, const Offset(0, -45));
                await tester.pump();
              }

              final afterAyahDragPixels = scrollableState.position.pixels;
              expect(
                afterAyahDragPixels,
                greaterThan(initialPixels + 20.0),
                reason:
                    '[${sc.label}] Real pointer drag must scroll past dropdowns to Ayah text',
              );
              final ayahPara =
                  tester.renderObject<RenderParagraph>(ayahTextFinder);
              final ayahAllBands = extractGlobalLineBands(ayahPara);
              final visibleAyahLines =
                  countCompleteLinesInClip(ayahPara, listClipRect);
              expect(
                visibleAyahLines,
                greaterThanOrEqualTo(2),
                reason:
                    '[${sc.label}] Expected >= 2 complete rendered Ayah lines inside ListView clip ($listClipRect), got $visibleAyahLines (total=${ayahAllBands.length})',
              );
              _verifyFooterAndHeaderContainment(
                tester,
                surah: sc.surah,
                ayahNumber: sc.ayah.ayahNumber,
                viewportSize: sc.size,
                keyboardBottom: 300,
                scenarioLabel: '${sc.label}/scrolledAyah',
              );
              await _capturePng(
                tester,
                'repair19_after_${sc.label}_scrolled_ayah.png',
              );

              // 2. Continue real pointer drag scroll onto real Tafsir exegesis text
              int visibleTafsirLines = 0;
              for (int step = 0; step < 40; step++) {
                if (tafsirTextFinder.evaluate().isNotEmpty) {
                  final tafsirPara =
                      tester.renderObject<RenderParagraph>(tafsirTextFinder);
                  visibleTafsirLines =
                      countCompleteLinesInClip(tafsirPara, listClipRect);
                  final tafsirTop = tester.getRect(tafsirTextFinder).top;
                  if (visibleTafsirLines >= 3 &&
                      tafsirTop <= listClipRect.top + 40.0) {
                    break;
                  }
                }
                final beforeDrag = scrollableState.position.pixels;
                await tester.drag(listFinder, const Offset(0, -60));
                await tester.pump();
                if ((scrollableState.position.pixels - beforeDrag).abs() < 0.5) {
                  break;
                }
              }

              final afterTafsirDragPixels = scrollableState.position.pixels;
              expect(
                afterTafsirDragPixels,
                greaterThan(afterAyahDragPixels + 20.0),
                reason:
                    '[${sc.label}] Real pointer drag must advance further into Tafsir exegesis text',
              );
              final tafsirPara =
                  tester.renderObject<RenderParagraph>(tafsirTextFinder);
              final tafsirAllBands = extractGlobalLineBands(tafsirPara);
              visibleTafsirLines =
                  countCompleteLinesInClip(tafsirPara, listClipRect);
              final minExpectedTafsirLines =
                  tafsirAllBands.length >= 3 ? 3 : tafsirAllBands.length;
              expect(
                visibleTafsirLines,
                greaterThanOrEqualTo(minExpectedTafsirLines),
                reason:
                    '[${sc.label}] Expected >= $minExpectedTafsirLines complete rendered Tafsir lines inside ListView clip ($listClipRect), got $visibleTafsirLines (total=${tafsirAllBands.length})',
              );
              _verifyFooterAndHeaderContainment(
                tester,
                surah: sc.surah,
                ayahNumber: sc.ayah.ayahNumber,
                viewportSize: sc.size,
                keyboardBottom: 300,
                scenarioLabel: '${sc.label}/scrolledTafsir',
              );
              await _capturePng(
                tester,
                'repair19_after_${sc.label}_scrolled_tafsir.png',
              );

              // 3. Continue dragging to bottom and verify very last rendered Tafsir line is fully reachable
              for (int step = 0; step < 40; step++) {
                final pos = scrollableState.position;
                if (pos.pixels >= pos.maxScrollExtent - 1.0) break;
                await tester.drag(listFinder, const Offset(0, -90));
                await tester.pump();
              }
              final finalTafsirPara =
                  tester.renderObject<RenderParagraph>(tafsirTextFinder);
              final finalBands = extractGlobalLineBands(finalTafsirPara);
              expect(finalBands, isNotEmpty);
              final lastBand = finalBands.last;
              expect(
                lastBand.bottom,
                lessThanOrEqualTo(listClipRect.bottom + 1.5),
                reason:
                    '[${sc.label}] Final Tafsir line bottom (${lastBand.bottom}) must be reachable inside ListView clip bottom (${listClipRect.bottom})',
              );
              expect(
                lastBand.top,
                greaterThanOrEqualTo(listClipRect.top - 1.5),
                reason:
                    '[${sc.label}] Final Tafsir line top (${lastBand.top}) must be visible inside ListView clip top (${listClipRect.top})',
              );

              debugPrint(
                'READING_VIEWPORT[${sc.label}]: listClipHeight=${listClipRect.height.toStringAsFixed(1)}px '
                'clip=(${listClipRect.top.toStringAsFixed(1)}..${listClipRect.bottom.toStringAsFixed(1)}) '
                'ayahVisibleLines=$visibleAyahLines/${ayahAllBands.length} '
                'tafsirVisibleLines=$visibleTafsirLines/${tafsirAllBands.length} '
                'dragPixels=${afterAyahDragPixels.toStringAsFixed(1)}->${afterTafsirDragPixels.toStringAsFixed(1)}->${scrollableState.position.pixels.toStringAsFixed(1)} '
                'lastLine=(${lastBand.top.toStringAsFixed(1)}..${lastBand.bottom.toStringAsFixed(1)})',
              );

              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump(const Duration(milliseconds: 250));
            } finally {
              FlutterError.onError = prevOnError;
            }

            expect(
              errors,
              isEmpty,
              reason:
                  '[${sc.label}/reading] Expected ZERO FlutterErrors post-teardown, got: ${errors.map((e) => e.message).join(" | ")}',
            );
          }
        } finally {
          semantics.dispose();
        }
      },
    );
  });
}
