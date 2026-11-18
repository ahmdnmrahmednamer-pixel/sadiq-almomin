import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/core/services/voice_search_service.dart';
import 'package:almomin/core/theme/app_theme.dart' as core_theme;
import 'package:almomin/features/search/widgets/quran_voice_search_sheet.dart';

const bool _kCapturePixels = bool.fromEnvironment(
  'CAPTURE_REPAIR12_PIXELS',
  defaultValue: false,
);
const String _kCaptureOutDir = String.fromEnvironment(
  'CAPTURE_REPAIR12_OUT_DIR',
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

Widget _buildHostApp({
  required double textScale,
  required double keyboardBottom,
  required ValueChanged<String?> onResult,
  ThemeData? theme,
}) {
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
          child: child!,
        );
      },
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              key: const ValueKey('open_voice_sheet_btn'),
              onPressed: () async {
                final res = await QuranVoiceSearchSheet.show(ctx);
                onResult(res);
              },
              child: const Text('OPEN_VOICE_SHEET'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openVoiceSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open_voice_sheet_btn')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  expect(find.byType(QuranVoiceSearchSheet), findsOneWidget);
}

Future<void> _scrollSheetTargetVisible(
  WidgetTester tester,
  Finder target, {
  required double visibleBottomLimit,
}) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  final rect = tester.getRect(target);
  expect(
    rect.top,
    greaterThanOrEqualTo(-0.5),
    reason: 'Target top (${rect.top}) must be visible on screen',
  );
  expect(
    rect.bottom,
    lessThanOrEqualTo(visibleBottomLimit + 1.0),
    reason:
        'Target bottom (${rect.bottom}) must be visible above keyboard/viewport limit ($visibleBottomLimit)',
  );
}

SemanticsNode _findTappableSemanticNode(WidgetTester tester, String target) {
  final matches = <SemanticsNode>[];
  for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
    final data = node.getSemanticsData();
    if ((data.label == target || data.tooltip == target || data.label.contains(target)) &&
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

  setUp(() {
    VoiceSearchService.resetTestMode();
    VoiceSearchService.isTestMode = true;
    VoiceSearchService.testMockRecognizedWords = 'الله لا إله إلا هو الحي القيوم';
  });

  tearDown(() {
    VoiceSearchService.resetTestMode();
  });

  group('Repair 12: QuranVoiceSearchSheet 2.0x, Keyboard, Contrast & Semantics', () {
    testWidgets(
      'Zero overflows, no TextScaler cap, horizontal containment, and primary/label WCAG AA contrast across 360x800 & 412x915 at 1.0x/2.0x + 300px keyboard (light & dark)',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const matrix = <(Size, double, double, bool, String)>[
          (Size(360, 800), 1.0, 0.0, true, '360x800_1x_rec'),
          (Size(360, 800), 2.0, 0.0, true, '360x800_2x_rec'),
          (Size(360, 800), 2.0, 0.0, false, '360x800_2x_examples'),
          (Size(360, 800), 2.0, 300.0, true, '360x800_2x_kb'),
          (Size(412, 915), 1.0, 0.0, true, '412x915_1x_rec'),
          (Size(412, 915), 2.0, 0.0, true, '412x915_2x_rec'),
          (Size(412, 915), 2.0, 300.0, true, '412x915_2x_kb'),
        ];

        for (final (size, scale, kb, recognized, tag) in matrix) {
          tester.view.physicalSize = size;
          VoiceSearchService.testMockRecognizedWords =
              recognized ? 'الله لا إله إلا هو الحي القيوم' : '';

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pumpWidget(
            _buildHostApp(
              textScale: scale,
              keyboardBottom: kb,
              onResult: (_) {},
            ),
          );
          await tester.pump();
          await _openVoiceSheet(tester);

          // Verify un-capped TextScaler
          expect(
            MediaQuery.textScalerOf(
              tester.element(find.byType(QuranVoiceSearchSheet)),
            ).scale(10),
            equals(scale * 10),
            reason: 'No hidden TextScaler cap on QuranVoiceSearchSheet at $tag',
          );

          // Header and recognized label stay within horizontal viewport bounds
          final headerRect = tester.getRect(find.text('البحث الصوتي في القرآن الكريم'));
          expect(headerRect.left, greaterThanOrEqualTo(0.0));
          expect(headerRect.right, lessThanOrEqualTo(size.width + 0.5));

          if (recognized) {
            final labelRect = tester.getRect(find.text('الكلمات التي تم التقاطها:'));
            expect(labelRect.left, greaterThanOrEqualTo(0.0));
            expect(labelRect.right, lessThanOrEqualTo(size.width + 0.5));

            // Primary button text color contrast vs emerald background >= 4.5:1
            final searchText = tester.widget<Text>(find.text('بحث بالآية'));
            final textColor = searchText.style!.color!;
            final ratio = _contrastRatio(textColor, core_theme.AppColors.primaryGreen);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason: 'Primary button contrast ($ratio) must meet WCAG AA >= 4.5 at $tag',
            );

            // Recognized gold label contrast vs white sheet background >= 4.5:1
            final recLabelWidget = tester.widget<Text>(find.text('الكلمات التي تم التقاطها:'));
            final recRatio = _contrastRatio(recLabelWidget.style!.color!, Colors.white);
            expect(
              recRatio,
              greaterThanOrEqualTo(4.5),
              reason: 'Recognized label contrast ($recRatio) must meet WCAG AA >= 4.5 at $tag',
            );
          }

          // Adaptive stacked layout check at 2.0x: primary button sits above retry/close row
          if (scale >= 1.35) {
            final visibleLimit = size.height - kb;
            await _scrollSheetTargetVisible(
              tester,
              find.byKey(const ValueKey('voice_sheet_close_button')),
              visibleBottomLimit: visibleLimit,
            );
            final primaryRect =
                tester.getRect(find.byKey(const ValueKey('voice_sheet_search_button')));
            final retryRect =
                tester.getRect(find.byKey(const ValueKey('voice_sheet_retry_button')));
            final closeRect =
                tester.getRect(find.byKey(const ValueKey('voice_sheet_close_button')));
            expect(
              primaryRect.bottom,
              lessThanOrEqualTo(retryRect.top + 1.0),
              reason: 'Primary button must stack cleanly above retry row at $tag',
            );
            expect(
              retryRect.overlaps(closeRect),
              isFalse,
              reason: 'Retry and close buttons must not overlap at $tag',
            );
          }

          expect(
            tester.takeException(),
            isNull,
            reason: 'Zero layout/runtime exceptions on QuranVoiceSearchSheet at $tag',
          );
        }

        // Also verify dark theme contrast >= 4.5:1
        tester.view.physicalSize = const Size(360, 800);
        VoiceSearchService.testMockRecognizedWords = 'الله لا إله إلا هو الحي القيوم';
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pumpWidget(
          _buildHostApp(
            textScale: 2.0,
            keyboardBottom: 0.0,
            theme: AppTheme.darkTheme,
            onResult: (_) {},
          ),
        );
        await tester.pump();
        await _openVoiceSheet(tester);

        final darkLabel = tester.widget<Text>(find.text('الكلمات التي تم التقاطها:'));
        expect(
          _contrastRatio(darkLabel.style!.color!, const Color(0xFF1B2420)),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'Scroll reachability, SemanticsAction.tap activation, query return, retry, example chip selection, and close at 360x800 @ 2.0x + 300px keyboard',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const keyboardHeight = 300.0;
        const visibleLimit = 800.0 - keyboardHeight;

        String? returnedQuery;
        bool callbackInvoked = false;

        await tester.pumpWidget(
          _buildHostApp(
            textScale: 2.0,
            keyboardBottom: keyboardHeight,
            onResult: (val) {
              callbackInvoked = true;
              returnedQuery = val;
            },
          ),
        );
        await tester.pump();

        // 1. Recognized query -> scroll primary button above keyboard -> SemanticsAction.tap -> returns exact query
        VoiceSearchService.testMockRecognizedWords = 'الله لا إله إلا هو الحي القيوم';
        await _openVoiceSheet(tester);

        await _scrollSheetTargetVisible(
          tester,
          find.byKey(const ValueKey('voice_sheet_search_button')),
          visibleBottomLimit: visibleLimit,
        );
        final searchNode = _findTappableSemanticNode(tester, 'بحث بالآية');
        tester.binding.pipelineOwner.semanticsOwner!
            .performAction(searchNode.id, SemanticsAction.tap);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(callbackInvoked, isTrue);
        expect(returnedQuery, equals('الله لا إله إلا هو الحي القيوم'));
        expect(find.byType(QuranVoiceSearchSheet), findsNothing);

        // 2. Retry (إعادة) via SemanticsAction.tap refreshes recognized text and returns new query
        callbackInvoked = false;
        returnedQuery = null;
        VoiceSearchService.testMockRecognizedWords = 'آية الكرسي';
        await _openVoiceSheet(tester);
        expect(find.text('«آية الكرسي»'), findsOneWidget);

        VoiceSearchService.testMockRecognizedWords = 'سورة الرحمن';
        await _scrollSheetTargetVisible(
          tester,
          find.byKey(const ValueKey('voice_sheet_retry_button')),
          visibleBottomLimit: visibleLimit,
        );
        final retryNode = _findTappableSemanticNode(tester, 'إعادة');
        tester.binding.pipelineOwner.semanticsOwner!
            .performAction(retryNode.id, SemanticsAction.tap);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('«سورة الرحمن»'), findsOneWidget);

        await _scrollSheetTargetVisible(
          tester,
          find.byKey(const ValueKey('voice_sheet_search_button')),
          visibleBottomLimit: visibleLimit,
        );
        final confirmRetryNode = _findTappableSemanticNode(tester, 'بحث بالآية');
        tester.binding.pipelineOwner.semanticsOwner!
            .performAction(confirmRetryNode.id, SemanticsAction.tap);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(callbackInvoked, isTrue);
        expect(returnedQuery, equals('سورة الرحمن'));

        // 3. Example chip selection when empty -> enables search -> returns exact chip text
        callbackInvoked = false;
        returnedQuery = null;
        VoiceSearchService.testMockRecognizedWords = '';
        await _openVoiceSheet(tester);
        await _scrollSheetTargetVisible(
          tester,
          find.text('سورة الملك'),
          visibleBottomLimit: visibleLimit,
        );
        await tester.tap(find.text('سورة الملك'));
        await tester.pump();
        expect(find.text('«سورة الملك»'), findsOneWidget);

        await _scrollSheetTargetVisible(
          tester,
          find.byKey(const ValueKey('voice_sheet_search_button')),
          visibleBottomLimit: visibleLimit,
        );
        final confirmChipNode = _findTappableSemanticNode(tester, 'بحث بالآية');
        tester.binding.pipelineOwner.semanticsOwner!
            .performAction(confirmChipNode.id, SemanticsAction.tap);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(callbackInvoked, isTrue);
        expect(returnedQuery, equals('سورة الملك'));

        // 4. Close (إغلاق) via SemanticsAction.tap dismisses sheet and returns null
        callbackInvoked = false;
        returnedQuery = 'sentinel';
        VoiceSearchService.testMockRecognizedWords = 'آية الكرسي';
        await _openVoiceSheet(tester);
        await _scrollSheetTargetVisible(
          tester,
          find.byKey(const ValueKey('voice_sheet_close_button')),
          visibleBottomLimit: visibleLimit,
        );
        final closeNode = _findTappableSemanticNode(tester, 'إغلاق');
        tester.binding.pipelineOwner.semanticsOwner!
            .performAction(closeNode.id, SemanticsAction.tap);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(callbackInvoked, isTrue);
        expect(returnedQuery, isNull);
        expect(find.byType(QuranVoiceSearchSheet), findsNothing);

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        semantics.dispose();
      },
    );

    testWidgets(
      'Real-font AFTER PNG captures for QuranVoiceSearchSheet at 360x800 and 412x915 (1.0x/2.0x + 300px keyboard + scrolled bottom)',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const scenarios = <(Size, double, double, bool, String, bool)>[
          (Size(360, 800), 1.0, 0.0, true, 'voice_recognized_360x800_1x', false),
          (Size(360, 800), 2.0, 0.0, true, 'voice_recognized_360x800_2x', true),
          (Size(360, 800), 2.0, 0.0, false, 'voice_examples_360x800_2x', false),
          (Size(360, 800), 2.0, 300.0, true, 'voice_recognized_360x800_2x_kb', true),
          (Size(412, 915), 1.0, 0.0, true, 'voice_recognized_412x915_1x', false),
          (Size(412, 915), 2.0, 0.0, true, 'voice_recognized_412x915_2x', false),
          (Size(412, 915), 2.0, 300.0, true, 'voice_recognized_412x915_2x_kb', false),
        ];

        for (final (size, scale, kb, recognized, tag, captureBottom) in scenarios) {
          tester.view.physicalSize = size;
          VoiceSearchService.testMockRecognizedWords =
              recognized ? 'الله لا إله إلا هو الحي القيوم' : '';

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pumpWidget(
            _buildHostApp(
              textScale: scale,
              keyboardBottom: kb,
              onResult: (_) {},
            ),
          );
          await tester.pump();
          await _openVoiceSheet(tester);
          await _capturePng(tester, 'repair12_after_$tag.png');

          if (captureBottom) {
            final scrollFinder = find.byKey(const ValueKey('voice_sheet_scroll_view'));
            final scrollable = find.descendant(
              of: scrollFinder,
              matching: find.byType(Scrollable),
            );
            final pos = tester.state<ScrollableState>(scrollable.first).position;
            pos.jumpTo(pos.maxScrollExtent);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 100));
            await _capturePng(
              tester,
              'repair12_after_${tag.replaceFirst("voice_recognized_", "voice_recognized_bottom_")}.png',
            );
          }

          expect(tester.takeException(), isNull, reason: 'Zero exceptions for capture $tag');
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });
}
