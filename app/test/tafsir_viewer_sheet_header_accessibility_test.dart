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
import 'package:almomin/core/services/tafsir_service.dart';
import 'package:almomin/features/mushaf/widgets/tafsir_viewer_sheet.dart';

const bool _kCapturePixels = bool.fromEnvironment(
  'CAPTURE_REPAIR18_PIXELS',
  defaultValue: false,
);
const String _kCaptureOutDir = String.fromEnvironment(
  'CAPTURE_REPAIR18_OUT_DIR',
  defaultValue: '',
);
const String _kMaterialIconsFontPath = String.fromEnvironment(
  'MATERIAL_ICONS_FONT',
  defaultValue: '',
);

final GlobalKey _kBoundaryKey = GlobalKey();

typedef _ExpectedUnresolvedFooterOverflow = ({
  String sourceLocation,
  String direction,
  int roundedPixels,
});

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
              child: const Text('OPEN_TAFSIR_SHEET'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openTafsirSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.tap(find.text('OPEN_TAFSIR_SHEET'));
  await _waitForTafsirLoaded(tester);
  expect(find.byType(TafsirViewerSheet), findsOneWidget);
}

Rect _actualVisibleClipRect(
  WidgetTester tester,
  Finder target,
  Size viewportSize,
  double keyboardBottom, {
  bool intersectKeyboard = true,
}) {
  final screenVisible = Rect.fromLTWH(
    0,
    0,
    viewportSize.width,
    intersectKeyboard
        ? (viewportSize.height - keyboardBottom).clamp(0.0, viewportSize.height)
        : viewportSize.height,
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
  double keyboardBottom,
  String label, {
  bool intersectKeyboard = true,
}) {
  expect(target, findsOneWidget, reason: '[$label] widget must exist');
  final rect = tester.getRect(target);
  final clip = _actualVisibleClipRect(
    tester,
    target,
    viewportSize,
    keyboardBottom,
    intersectKeyboard: intersectKeyboard,
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
    reason: '[$label] bottom ${rect.bottom} clipped by ${clip.bottom}',
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
  final paragraph = renderObject as RenderParagraph;
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '[$label] text must not truncate/exceed maxLines',
  );
}

Future<void> _scrollListTargetIntoActualClip(
  WidgetTester tester,
  Finder target,
  Size viewportSize,
  double keyboardBottom,
  String label,
) async {
  final listFinder = find.descendant(
    of: find.byType(TafsirViewerSheet),
    matching: find.byType(ListView),
  );
  expect(listFinder, findsOneWidget, reason: '[$label] ListView must exist');
  final scrollableFinder = find.descendant(
    of: listFinder,
    matching: find.byType(Scrollable),
  );
  final scrollableState = tester.state<ScrollableState>(scrollableFinder);

  for (int step = 0; step < 30; step++) {
    if (target.evaluate().isNotEmpty) {
      final rect = tester.getRect(target);
      final clip = _actualVisibleClipRect(
        tester,
        target,
        viewportSize,
        keyboardBottom,
        intersectKeyboard: true,
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

void _assertOnlyExactKnownFooterOverflows(
  List<_CapturedError> errors, {
  required String scenarioLabel,
  required List<_ExpectedUnresolvedFooterOverflow> expectedFooterMultiset,
}) {
  final overflowPattern = RegExp(
    r'A RenderFlex overflowed by ([0-9]+(?:\.[0-9]+)?) pixels on the (right|left|top|bottom)\.',
  );
  final locationPattern = RegExp(r'([a-zA-Z0-9_]+\.dart:\d+:\d+)');

  final actualSignatures = <String>[];
  for (final err in errors) {
    final full = err.fullDetails;
    final msg = err.message;
    final ov = overflowPattern.firstMatch(msg);
    final loc = locationPattern.firstMatch(full);
    if (ov == null || loc == null) {
      fail(
        '[$scenarioLabel] Unexpected non-RenderFlex or unlocated FlutterError: $msg\n$full',
      );
    }
    final srcLoc = loc.group(1)!;
    // Header line (136:22 or any line < 340) must NEVER overflow!
    final lineNum = int.parse(srcLoc.split(':')[1]);
    if (srcLoc.startsWith('tafsir_viewer_sheet.dart:') && lineNum < 340) {
      fail(
        '[$scenarioLabel] TafsirViewerSheet header/body error must be ZERO, got $msg at $srcLoc',
      );
    }
    final roundedPx = double.parse(ov.group(1)!).round();
    final dir = ov.group(2)!;
    actualSignatures.add('RenderFlex|$dir|$roundedPx|$srcLoc');
  }

  final expectedSignatures = expectedFooterMultiset
      .map((e) => 'RenderFlex|${e.direction}|${e.roundedPixels}|${e.sourceLocation}')
      .toList()
    ..sort();
  final sortedActual = List<String>.from(actualSignatures)..sort();

  expect(
    sortedActual,
    equals(expectedSignatures),
    reason:
        '[$scenarioLabel] Error multiset mismatch. Expected $expectedSignatures, got $sortedActual',
  );
}

SemanticsNode _findSemanticControl(WidgetTester tester, String targetLabel) {
  final matches = <SemanticsNode>[];
  for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
    final data = node.getSemanticsData();
    if ((data.label == targetLabel ||
            data.tooltip == targetLabel ||
            data.label.contains(targetLabel)) &&
        data.hasAction(SemanticsAction.tap)) {
      matches.add(node);
    }
  }
  expect(
    matches,
    isNotEmpty,
    reason: 'Expected tappable semantic control "$targetLabel"',
  );
  return matches.first;
}

void _verifyHeaderGeometryAndControls(
  WidgetTester tester, {
  required String expectedTitle,
  required Size viewportSize,
  required double keyboardBottom,
  required String scenarioLabel,
}) {
  final titleFinder = find.text(expectedTitle);
  _expectFullyContainedInActualClip(
    tester,
    titleFinder,
    viewportSize,
    keyboardBottom,
    '$scenarioLabel/title',
    intersectKeyboard: true,
  );
  _expectTextNotTruncated(tester, titleFinder, '$scenarioLabel/title');

  // Verify semantic header flag on title
  final titleSemantics = tester.getSemantics(titleFinder).getSemanticsData();
  expect(
    titleSemantics.flagsCollection.isHeader,
    isTrue,
    reason: '[$scenarioLabel] sheet title must carry header semantics',
  );

  final tooltips = <String>[
    'تغيير حجم خط التفسير',
    'نسخ التفسير',
    'مشاركة التفسير',
    'إغلاق',
  ];
  final controlRects = <String, Rect>{};
  for (final tip in tooltips) {
    final btnFinder = find.ancestor(
      of: find.byTooltip(tip),
      matching: find.byType(IconButton),
    );
    _expectFullyContainedInActualClip(
      tester,
      btnFinder,
      viewportSize,
      keyboardBottom,
      '$scenarioLabel/$tip',
      intersectKeyboard: true,
    );
    final rect = tester.getRect(btnFinder);
    expect(
      rect.width,
      greaterThanOrEqualTo(48.0 - 0.5),
      reason: '[$scenarioLabel/$tip] width ${rect.width} < 48',
    );
    expect(
      rect.height,
      greaterThanOrEqualTo(48.0 - 0.5),
      reason: '[$scenarioLabel/$tip] height ${rect.height} < 48',
    );
    controlRects[tip] = rect;
  }

  // Ensure none of the 4 header controls overlap each other or the title text
  final titleRect = tester.getRect(titleFinder);
  for (final entry in controlRects.entries) {
    final overlapWithTitle = titleRect.intersect(entry.value);
    expect(
      overlapWithTitle.width > 1.0 && overlapWithTitle.height > 1.0,
      isFalse,
      reason:
          '[$scenarioLabel] control "${entry.key}" (${entry.value}) overlaps title ($titleRect)',
    );
  }
  final entries = controlRects.entries.toList();
  for (int i = 0; i < entries.length; i++) {
    for (int j = i + 1; j < entries.length; j++) {
      final inter = entries[i].value.intersect(entries[j].value);
      expect(
        inter.width > 1.0 && inter.height > 1.0,
        isFalse,
        reason:
            '[$scenarioLabel] controls "${entries[i].key}" and "${entries[j].key}" overlap',
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

  group('Repair 18 — TafsirViewerSheet Header Layout & Accessibility', () {
    testWidgets(
      'Header has zero overflow, full containment, no truncation, and scroll reachability across 360/412 (1x/2x + 300px kb), wide, long title, and dark mode while preserving exact unresolved line-355 footer overflow',
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
          List<_ExpectedUnresolvedFooterOverflow> expectedFooterOverflows,
        })>[
          (
            label: '360x800_1x_kb',
            size: const Size(360, 800),
            scale: 1.0,
            kb: 300,
            surah: fatiha,
            ayah: fatihaAyah2,
            isDark: false,
            captureName: 'repair18_after_360x800_1x_kb.png',
            expectedFooterOverflows: const [],
          ),
          (
            label: '360x800_2x_kb',
            size: const Size(360, 800),
            scale: 2.0,
            kb: 300,
            surah: fatiha,
            ayah: fatihaAyah2,
            isDark: false,
            captureName: 'repair18_after_360x800_2x_kb.png',
            expectedFooterOverflows: const [],
          ),
          (
            label: '412x915_1x_kb',
            size: const Size(412, 915),
            scale: 1.0,
            kb: 300,
            surah: fatiha,
            ayah: fatihaAyah2,
            isDark: false,
            captureName: 'repair18_after_412x915_1x_kb.png',
            expectedFooterOverflows: const [],
          ),
          (
            label: '412x915_2x_kb',
            size: const Size(412, 915),
            scale: 2.0,
            kb: 300,
            surah: fatiha,
            ayah: fatihaAyah2,
            isDark: false,
            captureName: 'repair18_after_412x915_2x_kb.png',
            expectedFooterOverflows: const [],
          ),
          (
            label: '360x800_2x_nokb',
            size: const Size(360, 800),
            scale: 2.0,
            kb: 0,
            surah: fatiha,
            ayah: fatihaAyah2,
            isDark: false,
            captureName: 'repair18_after_360x800_2x_nokb.png',
            expectedFooterOverflows: const [],
          ),
          (
            label: '360x800_2x_kb_long_title',
            size: const Size(360, 800),
            scale: 2.0,
            kb: 300,
            surah: alImran,
            ayah: alImranAyah200,
            isDark: false,
            captureName: 'repair18_after_360x800_2x_kb_long_title.png',
            expectedFooterOverflows: const [],
          ),
          (
            label: '640x800_1x_wide',
            size: const Size(640, 800),
            scale: 1.0,
            kb: 0,
            surah: fatiha,
            ayah: fatihaAyah2,
            isDark: false,
            captureName: 'repair18_after_640x800_1x_wide.png',
            expectedFooterOverflows: const [],
          ),
          (
            label: '360x800_2x_dark',
            size: const Size(360, 800),
            scale: 2.0,
            kb: 0,
            surah: fatiha,
            ayah: fatihaAyah2,
            isDark: true,
            captureName: 'repair18_after_360x800_2x_dark.png',
            expectedFooterOverflows: const [],
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

              final expectedTitle =
                  'سورة ${sc.surah.nameAr} — الآية ${sc.ayah.ayahNumber}';
              _verifyHeaderGeometryAndControls(
                tester,
                expectedTitle: expectedTitle,
                viewportSize: sc.size,
                keyboardBottom: sc.kb,
                scenarioLabel: sc.label,
              );

              // Capture crisp real-font AFTER image BEFORE scrolling body
              await _capturePng(tester, sc.captureName);

              // Verify real ListView scroll reachability inside actual ancestor RenderAbstractViewport clip
              final listenBtn = find.ancestor(
                of: find.text('استمع للآية'),
                matching: find.byType(TextButton),
              );
              await _scrollListTargetIntoActualClip(
                tester,
                listenBtn,
                sc.size,
                sc.kb,
                '${sc.label}/listenBtn',
              );
              _expectFullyContainedInActualClip(
                tester,
                listenBtn,
                sc.size,
                sc.kb,
                '${sc.label}/listenBtn',
                intersectKeyboard: true,
              );

              final editionHeader = find
                  .descendant(
                    of: find.byType(ListView),
                    matching: find.text(TafsirService.availableEditions.first.nameAr),
                  )
                  .last;
              await _scrollListTargetIntoActualClip(
                tester,
                editionHeader,
                sc.size,
                sc.kb,
                '${sc.label}/editionHeader',
              );
              _expectFullyContainedInActualClip(
                tester,
                editionHeader,
                sc.size,
                sc.kb,
                '${sc.label}/editionHeader',
                intersectKeyboard: true,
              );

              // Scroll back to top and re-verify header remains intact and unclipped
              final listScrollable = tester.state<ScrollableState>(
                find.descendant(
                  of: find.descendant(
                    of: find.byType(TafsirViewerSheet),
                    matching: find.byType(ListView),
                  ),
                  matching: find.byType(Scrollable),
                ),
              );
              listScrollable.position.jumpTo(0);
              await tester.pump();
              _verifyHeaderGeometryAndControls(
                tester,
                expectedTitle: expectedTitle,
                viewportSize: sc.size,
                keyboardBottom: sc.kb,
                scenarioLabel: '${sc.label}/postScrollTop',
              );

              // Teardown inside error collection window
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump(const Duration(milliseconds: 250));
            } finally {
              FlutterError.onError = prevOnError;
            }

            _assertOnlyExactKnownFooterOverflows(
              errors,
              scenarioLabel: sc.label,
              expectedFooterMultiset: sc.expectedFooterOverflows,
            );
          }
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'Pointer and SemanticsAction.tap activation of all 4 header controls + dynamic Ayah title update at 360x800 @ 2.0x + 300px keyboard',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(360, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final clipboardCaptures = <String>[];
        final shareCaptures = <String>[];
        const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<dynamic, dynamic>;
            clipboardCaptures.add(args['text'] as String);
          }
          return null;
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(shareChannel, (call) async {
          if (call.method == 'share' || call.method == 'shareWithResult') {
            final args = call.arguments as Map<dynamic, dynamic>;
            shareCaptures.add((args['text'] ?? '').toString());
            return 'success';
          }
          return null;
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(shareChannel, null);
        });

        final semantics = tester.ensureSemantics();
        final errors = <_CapturedError>[];
        final prevOnError = FlutterError.onError;
        FlutterError.onError = (d) => errors.add((
              message: d.exceptionAsString(),
              fullDetails: d.toString(),
            ));

        try {
          await tester.pumpWidget(
            _buildHost(
              surah: fatiha,
              ayah: fatihaAyah2,
              textScale: 2.0,
              keyboardBottom: 300,
            ),
          );
          await _openTafsirSheet(tester);

          // Scroll ListView so tafsir body text is built inside the viewport
          final tafsirSemanticsFinder = find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                (w.properties.label?.startsWith('شرح التفسير:') ?? false),
          );
          await _scrollListTargetIntoActualClip(
            tester,
            tafsirSemanticsFinder,
            const Size(360, 800),
            300,
            '360_2x_kb/tafsirBody',
          );

          // Helper to read current tafsir body fontSize directly from rendered Text widget
          double readTafsirBodyFontSize() {
            final tafsirTextWidget = tester.widget<Text>(
              find.descendant(
                of: tafsirSemanticsFinder,
                matching: find.byType(Text),
              ),
            );
            return tafsirTextWidget.style!.fontSize!;
          }

          final initialFontSize = readTafsirBodyFontSize();

          // 1. Font size button — pointer tap
          await tester.tap(find.byTooltip('تغيير حجم خط التفسير'));
          await tester.pump();
          final afterPointerFontSize = readTafsirBodyFontSize();
          final expectedAfterPointer =
              initialFontSize >= 24.0 ? 14.0 : initialFontSize + 2.0;
          expect(afterPointerFontSize, equals(expectedAfterPointer));

          // 1b. Font size button — SemanticsAction.tap
          final fontNode = _findSemanticControl(tester, 'تغيير حجم خط التفسير');
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            fontNode.id,
            SemanticsAction.tap,
          );
          await tester.pump();
          final afterSemanticFontSize = readTafsirBodyFontSize();
          final expectedAfterSemantic =
              afterPointerFontSize >= 24.0 ? 14.0 : afterPointerFontSize + 2.0;
          expect(afterSemanticFontSize, equals(expectedAfterSemantic));

          // 2. Copy button — pointer tap
          await tester.tap(find.byTooltip('نسخ التفسير'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(clipboardCaptures, hasLength(1));
          expect(clipboardCaptures.last, contains('سورة الفاتحة — الآية 2'));
          expect(clipboardCaptures.last, contains('التفسير الميسر'));
          expect(
            find.text('تم نسخ نص الآية والتفسير المعتمد إلى الحافظة'),
            findsOneWidget,
          );

          // 2b. Copy button — SemanticsAction.tap
          final copyNode = _findSemanticControl(tester, 'نسخ التفسير');
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            copyNode.id,
            SemanticsAction.tap,
          );
          await tester.pump();
          expect(clipboardCaptures, hasLength(2));
          expect(clipboardCaptures.last, contains('سورة الفاتحة — الآية 2'));

          // 3. Share button — pointer tap & SemanticsAction.tap deliver exact share payload
          await tester.tap(find.byTooltip('مشاركة التفسير'));
          await tester.pump();
          expect(shareCaptures, hasLength(1));
          expect(shareCaptures.last, contains('سورة الفاتحة — الآية 2'));
          expect(shareCaptures.last, contains('التفسير الميسر'));

          final shareNode = _findSemanticControl(tester, 'مشاركة التفسير');
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            shareNode.id,
            SemanticsAction.tap,
          );
          await tester.pump();
          expect(shareCaptures, hasLength(2));
          expect(shareCaptures.last, contains('سورة الفاتحة — الآية 2'));

          // 4. Close button — pointer tap dismisses sheet
          await tester.tap(find.byTooltip('إغلاق'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          expect(find.byType(TafsirViewerSheet), findsNothing);

          // Re-open sheet and verify SemanticsAction.tap on Close dismisses sheet
          await _openTafsirSheet(tester);
          final closeNode = _findSemanticControl(tester, 'إغلاق');
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            closeNode.id,
            SemanticsAction.tap,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          expect(find.byType(TafsirViewerSheet), findsNothing);

          // Teardown inside error window
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 250));
        } finally {
          semantics.dispose();
          FlutterError.onError = prevOnError;
        }

        // Only exact unresolved line-355 footer overflows (two sheet opens at 360x800 @ 2.0x)
        // ZERO header overflows!
        _assertOnlyExactKnownFooterOverflows(
          errors,
          scenarioLabel: '360_2x_kb_header_actions',
          expectedFooterMultiset: const [],
        );
      },
    );

    testWidgets(
      'Dynamic Ayah change updates header title cleanly with zero errors at 360x800 @ 1.0x + 300px keyboard',
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
          await tester.pumpWidget(
            _buildHost(
              surah: fatiha,
              ayah: fatihaAyah2,
              textScale: 1.0,
              keyboardBottom: 300,
            ),
          );
          await _openTafsirSheet(tester);

          expect(find.text('سورة الفاتحة — الآية 2'), findsOneWidget);

          // Open Ayah selector dropdown and select آية 7
          await tester.tap(find.text('آية 2'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.text('آية 7').last);
          await _waitForTafsirLoaded(tester);

          _verifyHeaderGeometryAndControls(
            tester,
            expectedTitle: 'سورة الفاتحة — الآية 7',
            viewportSize: const Size(360, 800),
            keyboardBottom: 300,
            scenarioLabel: '360_1x_kb_dynamic_ayah7',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 250));
        } finally {
          semantics.dispose();
          FlutterError.onError = prevOnError;
        }

        _assertOnlyExactKnownFooterOverflows(
          errors,
          scenarioLabel: '360_1x_kb_dynamic_ayah7',
          expectedFooterMultiset: const [],
        );
      },
    );
  });
}
