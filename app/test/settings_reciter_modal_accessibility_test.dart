import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/core/audio/ayah_audio_player.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/settings/widgets/settings_reciter_modal.dart';

const bool _kCapturePixels = bool.fromEnvironment(
  'CAPTURE_REPAIR16_PIXELS',
  defaultValue: false,
);
const String _kPixelDir = String.fromEnvironment(
  'REPAIR16_PIXEL_DIR',
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

Widget _buildHost({required double scale, double keyboardHeight = 0.0}) {
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
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showSettingsReciterModal(ctx),
              child: const Text('OPEN_RECITER_MODAL'),
            ),
          ),
        ),
      ),
    ),
  );
}

SemanticsNode _findTappableNode(WidgetTester tester, String substring) {
  final root = tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
  SemanticsNode? match;
  void visit(SemanticsNode node) {
    if (match != null) return;
    final data = node.getSemanticsData();
    final combined = '${data.label} ${data.tooltip} ${data.value}';
    if (combined.contains(substring) && data.hasAction(SemanticsAction.tap)) {
      match = node;
      return;
    }
    node.visitChildren((child) {
      visit(child);
      return match == null;
    });
  }

  visit(root);
  expect(
    match,
    isNotNull,
    reason: 'Expected tappable SemanticsNode matching "$substring"',
  );
  return match!;
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
  final sheetFinder = find.byType(BottomSheet);
  if (sheetFinder.evaluate().isNotEmpty) {
    clip = clip.intersect(tester.getRect(sheetFinder.last));
  }
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
  expect(
    visibleRect.width,
    greaterThan(0),
    reason: '$description visibleRect has non-positive width: $visibleRect',
  );
  expect(
    visibleRect.height,
    greaterThan(0),
    reason: '$description visibleRect has non-positive height: $visibleRect',
  );
  expect(
    rect.width,
    greaterThan(0),
    reason: '$description must have positive width, got $rect',
  );
  expect(
    rect.height,
    greaterThan(0),
    reason: '$description must have positive height, got $rect',
  );
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
    reason:
        '$description clipped on bottom / behind keyboard: $rect vs visibleRect=$visibleRect',
  );
}

Finder _reciterCardFinder(String reciterName) {
  return find.ancestor(
    of: find.text(reciterName),
    matching: find.byType(InkWell),
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
    final margin = (rect.height + 28.0 <= visibleRect.height) ? 12.0 : 0.0;
    if (rect.top >= visibleRect.top + margin - 0.5 &&
        rect.bottom <= visibleRect.bottom - margin + 0.5) {
      return;
    }
    if (rect.bottom > visibleRect.bottom - margin + 0.5) {
      final delta =
          (rect.bottom - (visibleRect.bottom - margin) + 8.0).clamp(24.0, step);
      await tester.drag(scrollFinder, Offset(0, -delta));
    } else if (rect.top < visibleRect.top + margin - 0.5) {
      final delta =
          ((visibleRect.top + margin) - rect.top + 8.0).clamp(24.0, step);
      await tester.drag(scrollFinder, Offset(0, delta));
    }
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _scrollHorizontallyIntoVisibleRect(
  WidgetTester tester,
  Finder targetFinder,
  Finder horizontalScrollFinder,
  Size screenSize, {
  double keyboardHeight = 0.0,
  double step = 140.0,
}) async {
  for (int i = 0; i < 12; i++) {
    final rect = tester.getRect(targetFinder);
    final visibleRect = _visibleClipFor(
      tester,
      targetFinder,
      screenSize,
      keyboardHeight: keyboardHeight,
    ).clip;
    if (rect.left >= visibleRect.left - 0.5 &&
        rect.right <= visibleRect.right + 0.5) {
      return;
    }
    if (rect.left < visibleRect.left - 0.5) {
      // RTL horizontal chip row: dragging right (positive dx) brings left-clipped chips into view
      final delta = (visibleRect.left - rect.left + 16.0).clamp(24.0, step);
      await tester.drag(horizontalScrollFinder, Offset(delta, 0));
    } else if (rect.right > visibleRect.right + 0.5) {
      final delta = (rect.right - visibleRect.right + 16.0).clamp(24.0, step);
      await tester.drag(horizontalScrollFinder, Offset(-delta, 0));
    }
    await tester.pump(const Duration(milliseconds: 150));
  }
}

bool _isNodeSelected(SemanticsNode node) {
  return node.getSemanticsData().flagsCollection.isSelected ==
      ui.Tristate.isTrue;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadRealFonts();
  });

  testWidgets(
    'SettingsReciterModal responsive matrix (360/412, 1x/2x, selected/unselected, keyboard empty) has zero overflow, readable cards, full containment, and scrollable list',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.init();
      tester.view.devicePixelRatio = 1.0;

      const scenarios = <({
        String id,
        Size size,
        double scale,
        double kb,
        String? category,
        String? query,
        String captureName,
      })>[
        (
          id: '360x800_1x',
          size: Size(360, 800),
          scale: 1.0,
          kb: 0.0,
          category: null,
          query: null,
          captureName: 'repair16_after_360x800_1x.png',
        ),
        (
          id: '360x800_2x',
          size: Size(360, 800),
          scale: 2.0,
          kb: 0.0,
          category: null,
          query: null,
          captureName: 'repair16_after_360x800_2x.png',
        ),
        (
          id: '412x915_1x',
          size: Size(412, 915),
          scale: 1.0,
          kb: 0.0,
          category: null,
          query: null,
          captureName: 'repair16_after_412x915_1x.png',
        ),
        (
          id: '412x915_2x',
          size: Size(412, 915),
          scale: 2.0,
          kb: 0.0,
          category: null,
          query: null,
          captureName: 'repair16_after_412x915_2x.png',
        ),
        (
          id: '360x800_2x_khoshua_unselected',
          size: Size(360, 800),
          scale: 2.0,
          kb: 0.0,
          category: 'تلاوة خاشعة',
          query: null,
          captureName: 'repair16_after_360x800_2x_khoshua_unselected.png',
        ),
        (
          id: '360x800_2x_kb_empty',
          size: Size(360, 800),
          scale: 2.0,
          kb: 300.0,
          category: null,
          query: 'غيرموجود',
          captureName: 'repair16_after_360x800_2x_kb_empty.png',
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
              _buildHost(scale: sc.scale, keyboardHeight: sc.kb),
            );
            await tester.pump();
            await tester.tap(find.text('OPEN_RECITER_MODAL'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 450));
            expect(find.byType(BottomSheet), findsOneWidget);

            // Uncapped TextScaler
            final sheetCtx = tester.element(find.byType(BottomSheet));
            expect(
              MediaQuery.textScalerOf(sheetCtx).scale(1.0),
              closeTo(sc.scale, 0.001),
              reason: '${sc.id}: TextScaler must remain uncapped',
            );

            final usesUnifiedScroll = sc.scale >= 1.35 || sc.kb > 0;
            final chipMinViewports = usesUnifiedScroll ? 2 : 1;

            // Full visibleRect containment for header, count badge, search (intersected with ancestor RenderAbstractViewport + sheet + screen + keyboard)
            _assertContainedInVisibleRect(
              tester,
              find.text('اختر القارئ الافتراضي للتلاوة'),
              sc.size,
              keyboardHeight: sc.kb,
              minAncestorViewports: usesUnifiedScroll ? 1 : 0,
              description: '${sc.id} header title',
            );
            _assertContainedInVisibleRect(
              tester,
              find.text('القارئ الحالي: محمد صديق المنشاوي (مرتل)'),
              sc.size,
              keyboardHeight: sc.kb,
              minAncestorViewports: usesUnifiedScroll ? 1 : 0,
              description: '${sc.id} current reciter subtitle',
            );
            _assertContainedInVisibleRect(
              tester,
              find.text('${SettingsService.availableReciters.length} قارئ'),
              sc.size,
              keyboardHeight: sc.kb,
              minAncestorViewports: usesUnifiedScroll ? 1 : 0,
              description: '${sc.id} reciter count badge',
            );
            _assertContainedInVisibleRect(
              tester,
              find.byType(TextField),
              sc.size,
              keyboardHeight: sc.kb,
              minAncestorViewports: usesUnifiedScroll ? 1 : 0,
              description: '${sc.id} search field',
            );
            final scrollFinder =
                find.byKey(const ValueKey('reciter_modal_scroll_view'));
            expect(scrollFinder, findsOneWidget);

            // Scroll "الكل" category chip into actual ancestor scroll visibleRect, then verify full 2D clip containment (including horizontal scroll clip)
            final allChipFinder = find.ancestor(
              of: find.text('الكل').first,
              matching: find.byType(FilterChip),
            );
            final chipsScroll = find.ancestor(
              of: find.text('الكل').first,
              matching: find.byType(SingleChildScrollView),
            );
            await _scrollFullyIntoVisibleRect(
              tester,
              allChipFinder,
              scrollFinder,
              sc.size,
              keyboardHeight: sc.kb,
              step: 60.0,
            );
            await _scrollHorizontallyIntoVisibleRect(
              tester,
              allChipFinder,
              chipsScroll,
              sc.size,
              keyboardHeight: sc.kb,
            );
            _assertContainedInVisibleRect(
              tester,
              allChipFinder,
              sc.size,
              keyboardHeight: sc.kb,
              minAncestorViewports: chipMinViewports,
              description: '${sc.id} "الكل" category chip',
            );

            if (sc.category != null) {
              final targetChipFinder = find.ancestor(
                of: find.text(sc.category!).first,
                matching: find.byType(FilterChip),
              );
              await _scrollHorizontallyIntoVisibleRect(
                tester,
                targetChipFinder,
                chipsScroll,
                sc.size,
                keyboardHeight: sc.kb,
              );
              _assertContainedInVisibleRect(
                tester,
                targetChipFinder,
                sc.size,
                keyboardHeight: sc.kb,
                minAncestorViewports: chipMinViewports,
                description: '${sc.id} "${sc.category}" category chip',
              );
              await tester.tap(find.text(sc.category!).first);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 250));
            }
            if (sc.query != null) {
              final searchFinder = find.byType(TextField);
              await _scrollFullyIntoVisibleRect(
                tester,
                searchFinder,
                scrollFinder,
                sc.size,
                keyboardHeight: sc.kb,
                step: 60.0,
              );
              await tester.enterText(searchFinder, sc.query!);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 250));
              _assertContainedInVisibleRect(
                tester,
                find.byTooltip('إغلاق أو مسح'),
                sc.size,
                keyboardHeight: sc.kb,
                minAncestorViewports: usesUnifiedScroll ? 1 : 0,
                description: '${sc.id} clear search button',
              );
            }

            if (sc.query == null) {
              final listRect = tester.getRect(scrollFinder);
              expect(
                listRect.height,
                greaterThan(180),
                reason: '${sc.id}: reciters scroll view must retain usable height',
              );

              // Capture initial clean BEFORE-vs-AFTER visual state first (all 6 initial captures preserved)
              await _capturePng(tester, sc.captureName);

              if (sc.category == null) {
                // Scroll entire default SELECTED card fully into actual ancestor scroll visibleRect and verify zero clipping!
                final selectedCard =
                    _reciterCardFinder('محمد صديق المنشاوي (مرتل)');
                await _scrollFullyIntoVisibleRect(
                  tester,
                  selectedCard,
                  scrollFinder,
                  sc.size,
                  keyboardHeight: sc.kb,
                );
                _assertContainedInVisibleRect(
                  tester,
                  selectedCard,
                  sc.size,
                  keyboardHeight: sc.kb,
                  minAncestorViewports: 1,
                  description: '${sc.id} entire selected reciter card',
                );
                final selectedNameFinder =
                    find.text('محمد صديق المنشاوي (مرتل)');
                _assertContainedInVisibleRect(
                  tester,
                  selectedNameFinder,
                  sc.size,
                  keyboardHeight: sc.kb,
                  minAncestorViewports: 1,
                  description: '${sc.id} selected reciter name',
                );
                final nameRect = tester.getRect(selectedNameFinder);
                expect(
                  nameRect.width,
                  greaterThan(140),
                  reason:
                      '${sc.id}: selected reciter name must have wide readable column, got $nameRect',
                );
                _assertContainedInVisibleRect(
                  tester,
                  find.text('الافتراضي ⭐'),
                  sc.size,
                  keyboardHeight: sc.kb,
                  minAncestorViewports: 1,
                  description: '${sc.id} default badge',
                );
                _assertContainedInVisibleRect(
                  tester,
                  find.text('محدد 🎧'),
                  sc.size,
                  keyboardHeight: sc.kb,
                  minAncestorViewports: 1,
                  description: '${sc.id} selected badge',
                );
                if (sc.id == '360x800_2x') {
                  await _capturePng(
                    tester,
                    'repair16_after_360x800_2x_scrolled_selected_card.png',
                  );
                }

                // Also scroll an UNSELECTED card ('محمد صديق المنشاوي (مجود)') fully into actual ancestor scroll visibleRect
                final unselectedCard =
                    _reciterCardFinder('محمد صديق المنشاوي (مجود)');
                await _scrollFullyIntoVisibleRect(
                  tester,
                  unselectedCard,
                  scrollFinder,
                  sc.size,
                  keyboardHeight: sc.kb,
                );
                _assertContainedInVisibleRect(
                  tester,
                  unselectedCard,
                  sc.size,
                  keyboardHeight: sc.kb,
                  minAncestorViewports: 1,
                  description: '${sc.id} entire unselected reciter card',
                );
                _assertContainedInVisibleRect(
                  tester,
                  find.text('محمد صديق المنشاوي (مجود)'),
                  sc.size,
                  keyboardHeight: sc.kb,
                  minAncestorViewports: 1,
                  description: '${sc.id} unselected reciter name',
                );
                if (sc.id == '360x800_2x') {
                  await _capturePng(
                    tester,
                    'repair16_after_360x800_2x_scrolled_unselected_card.png',
                  );
                }
              } else {
                // Scroll entire unselected 'تلاوة خاشعة' card fully into actual ancestor scroll visibleRect
                final unselectedCard = _reciterCardFinder('رعد محمد الكردي');
                await _scrollFullyIntoVisibleRect(
                  tester,
                  unselectedCard,
                  scrollFinder,
                  sc.size,
                  keyboardHeight: sc.kb,
                );
                _assertContainedInVisibleRect(
                  tester,
                  unselectedCard,
                  sc.size,
                  keyboardHeight: sc.kb,
                  minAncestorViewports: 1,
                  description: '${sc.id} entire khoshua unselected card',
                );
                _assertContainedInVisibleRect(
                  tester,
                  find.text('رعد محمد الكردي'),
                  sc.size,
                  keyboardHeight: sc.kb,
                  minAncestorViewports: 1,
                  description: '${sc.id} unselected reciter name',
                );
              }

              // Scroll reachability check
              final scrollable = tester.state<ScrollableState>(
                find
                    .descendant(of: scrollFinder, matching: find.byType(Scrollable))
                    .first,
              );
              final beforePx = scrollable.position.pixels;
              await tester.drag(scrollFinder, const Offset(0, -250));
              await tester.pump(const Duration(milliseconds: 200));
              expect(
                scrollable.position.pixels,
                greaterThan(beforePx),
                reason: '${sc.id}: reciters list must scroll cleanly',
              );
            } else {
              // Scroll unified view so empty search state sits fully inside ancestor visibleRect above 300px keyboard
              final emptyFinder =
                  find.text('لم يتم العثور على قارئ يطابق "${sc.query}"');
              await _scrollFullyIntoVisibleRect(
                tester,
                emptyFinder,
                scrollFinder,
                sc.size,
                keyboardHeight: sc.kb,
              );
              _assertContainedInVisibleRect(
                tester,
                emptyFinder,
                sc.size,
                keyboardHeight: sc.kb,
                minAncestorViewports: 1,
                description: '${sc.id} empty search text',
              );
              await _capturePng(tester, sc.captureName);
            }

            // Teardown scenario BEFORE checking errors and restoring FlutterError.onError
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(milliseconds: 100));

            expect(
              errors,
              isEmpty,
              reason:
                  'Scenario ${sc.id} produced unexpected FlutterErrors across full lifecycle (open/filter/scroll/capture/teardown): ${errors.map((e) => e.exceptionAsString()).join(" | ")}',
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
    'SettingsReciterModal supports pointer and SemanticsAction.tap for categories, search/clear, scrolling, Semantics selected flags, and selected/unselected reciter switching at 360x800 @ 2.0x',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.init();
      const viewport = Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = viewport;

      final previewedCacheKeys = <String>[];
      AyahAudioPlayer.instance.stopPlayerRunner = () async {};
      AyahAudioPlayer.instance.playResilientRunner = (
        url, {
        player,
        primaryUrl,
        fallbackUrls = const [],
        localDownloadedPath,
        cacheKey,
        onStopCallback,
      }) async {
        if (cacheKey != null) {
          previewedCacheKeys.add(cacheKey);
        }
        return true;
      };

      final errors = <FlutterErrorDetails>[];
      final prevOnError = FlutterError.onError;
      FlutterError.onError = (d) => errors.add(d);
      final semanticsHandle = tester.ensureSemantics();

      final totalCount = SettingsService.availableReciters.length;
      final mujawwadCount =
          SettingsService.availableReciters.where((r) => r.style == 'مجود').length;
      final khoshuaCount =
          SettingsService.availableReciters.where((r) => r.style == 'تلاوة خاشعة').length;

      try {
        await tester.pumpWidget(_buildHost(scale: 2.0));
        await tester.pump();
        await tester.tap(find.text('OPEN_RECITER_MODAL'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        expect(find.text('$totalCount قارئ'), findsOneWidget);

        // 0. Default Semantics selected flag check: default reciter selected=true
        final initialDefaultNode = _findTappableNode(
          tester,
          'محمد صديق المنشاوي (مرتل)',
        );
        expect(
          _isNodeSelected(initialDefaultNode),
          isTrue,
          reason: 'Default reciter SemanticsNode must report selected=true',
        );

        // 1. Category chips: pointer tap ('مجود'), SemanticsAction.tap ('تلاوة خاشعة'), SemanticsAction.tap ('الكل')
        final chipsScroll = find.ancestor(
          of: find.text('الكل').first,
          matching: find.byType(SingleChildScrollView),
        );
        final mujawwadChip = find.ancestor(
          of: find.text('مجود').first,
          matching: find.byType(FilterChip),
        );
        await _scrollHorizontallyIntoVisibleRect(
          tester,
          mujawwadChip,
          chipsScroll,
          viewport,
        );
        _assertContainedInVisibleRect(
          tester,
          mujawwadChip,
          viewport,
          minAncestorViewports: 2,
          description: '"مجود" category chip',
        );
        await tester.tap(find.text('مجود').first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('$mujawwadCount قارئ'), findsOneWidget);

        final khoshuaChip = find.ancestor(
          of: find.text('تلاوة خاشعة').first,
          matching: find.byType(FilterChip),
        );
        await _scrollHorizontallyIntoVisibleRect(
          tester,
          khoshuaChip,
          chipsScroll,
          viewport,
        );
        _assertContainedInVisibleRect(
          tester,
          khoshuaChip,
          viewport,
          minAncestorViewports: 2,
          description: '"تلاوة خاشعة" category chip',
        );
        final khoshuaChipNode = _findTappableNode(tester, 'تلاوة خاشعة');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          khoshuaChipNode.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('$khoshuaCount قارئ'), findsOneWidget);

        final allChip = find.ancestor(
          of: find.text('الكل').first,
          matching: find.byType(FilterChip),
        );
        await _scrollHorizontallyIntoVisibleRect(
          tester,
          allChip,
          chipsScroll,
          viewport,
        );
        _assertContainedInVisibleRect(
          tester,
          allChip,
          viewport,
          minAncestorViewports: 2,
          description: '"الكل" category chip',
        );
        final allChipNode = _findTappableNode(tester, 'الكل');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          allChipNode.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('$totalCount قارئ'), findsOneWidget);

        // 2. Search filtering + SemanticsAction.tap clear ('إغلاق أو مسح') + pointer clear
        await tester.enterText(find.byType(TextField), 'الحصري');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('محمود خليل الحصري (مرتل)'), findsOneWidget);
        _assertContainedInVisibleRect(
          tester,
          find.byTooltip('إغلاق أو مسح'),
          viewport,
          minAncestorViewports: 1,
          description: 'clear search button',
        );

        final clearSemNode = _findTappableNode(tester, 'إغلاق أو مسح');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          clearSemNode.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('$totalCount قارئ'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'غيرموجود');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('0 قارئ'), findsOneWidget);
        _assertContainedInVisibleRect(
          tester,
          find.byTooltip('إغلاق أو مسح'),
          viewport,
          minAncestorViewports: 1,
          description: 'clear search button on empty state',
        );
        await tester.tap(find.byTooltip('إغلاق أو مسح'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('$totalCount قارئ'), findsOneWidget);

        // 3. Scroll unselected reciter ('محمد صديق المنشاوي (مجود)') fully into actual ancestor visibleRect -> verify selected=false, full 2D clip containment, then pointer select
        final scrollFinder =
            find.byKey(const ValueKey('reciter_modal_scroll_view'));
        final mujawwadCard = _reciterCardFinder('محمد صديق المنشاوي (مجود)');
        await _scrollFullyIntoVisibleRect(
          tester,
          mujawwadCard,
          scrollFinder,
          viewport,
        );
        _assertContainedInVisibleRect(
          tester,
          mujawwadCard,
          viewport,
          minAncestorViewports: 1,
          description: 'unselected mujawwad reciter card before tap',
        );
        final initialMujawwadNode = _findTappableNode(
          tester,
          'محمد صديق المنشاوي (مجود)',
        );
        expect(
          _isNodeSelected(initialMujawwadNode),
          isFalse,
          reason: 'Unselected reciter SemanticsNode must report selected=false',
        );

        await tester.tap(find.text('محمد صديق المنشاوي (مجود)'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        expect(
          SettingsService.instance.selectedReciterId,
          equals('minshawi_mujawwad'),
        );
        expect(previewedCacheKeys, contains('preview_reciter_minshawi_mujawwad'));
        expect(find.byType(BottomSheet), findsNothing);
        expect(
          find.text(
            'تم اعتماد القارئ: محمد صديق المنشاوي (مجود) — جاري سماع صوته الآن 🎧',
          ),
          findsOneWidget,
        );

        // 4. Reopen modal at 360x800 @ 2.0x -> verify switched Semantics selected flags (mujawwad=true, murattal=false), full ancestor visibleRect containment, and SemanticsAction.tap switch back
        await tester.tap(find.text('OPEN_RECITER_MODAL'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(
          find.text('القارئ الحالي: محمد صديق المنشاوي (مجود)'),
          findsOneWidget,
        );

        final reopenedScroll =
            find.byKey(const ValueKey('reciter_modal_scroll_view'));
        final reopenedMurattalCard =
            _reciterCardFinder('محمد صديق المنشاوي (مرتل)');
        await _scrollFullyIntoVisibleRect(
          tester,
          reopenedMurattalCard,
          reopenedScroll,
          viewport,
        );
        _assertContainedInVisibleRect(
          tester,
          reopenedMurattalCard,
          viewport,
          minAncestorViewports: 1,
          description: 'reopened unselected default card',
        );
        _assertContainedInVisibleRect(
          tester,
          find.text('الافتراضي ⭐'),
          viewport,
          minAncestorViewports: 1,
          description: 'reopened default badge',
        );
        final switchedMurattalNode = _findTappableNode(
          tester,
          'محمد صديق المنشاوي (مرتل)',
        );
        expect(
          _isNodeSelected(switchedMurattalNode),
          isFalse,
          reason:
              'Previous default reciter SemanticsNode must report selected=false after switching away',
        );

        final reopenedMujawwadCard =
            _reciterCardFinder('محمد صديق المنشاوي (مجود)');
        await _scrollFullyIntoVisibleRect(
          tester,
          reopenedMujawwadCard,
          reopenedScroll,
          viewport,
        );
        _assertContainedInVisibleRect(
          tester,
          reopenedMujawwadCard,
          viewport,
          minAncestorViewports: 1,
          description: 'reopened newly selected mujawwad card',
        );
        _assertContainedInVisibleRect(
          tester,
          find.text('محدد 🎧'),
          viewport,
          minAncestorViewports: 1,
          description: 'reopened selected badge',
        );
        final switchedMujawwadNode = _findTappableNode(
          tester,
          'محمد صديق المنشاوي (مجود)',
        );
        expect(
          _isNodeSelected(switchedMujawwadNode),
          isTrue,
          reason:
              'Newly selected reciter SemanticsNode must report selected=true',
        );

        // Scroll back to default reciter card and switch back via SemanticsAction.tap
        await _scrollFullyIntoVisibleRect(
          tester,
          reopenedMurattalCard,
          reopenedScroll,
          viewport,
        );
        final defaultReciterNode = _findTappableNode(
          tester,
          'محمد صديق المنشاوي (مرتل)',
        );
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          defaultReciterNode.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        expect(
          SettingsService.instance.selectedReciterId,
          equals('minshawi_murattal'),
        );
        expect(previewedCacheKeys, contains('preview_reciter_minshawi_murattal'));
        expect(find.byType(BottomSheet), findsNothing);

        // 5. Reopen once more to confirm SemanticsAction.tap restored selected=true on default reciter
        await tester.tap(find.text('OPEN_RECITER_MODAL'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        expect(
          _isNodeSelected(
            _findTappableNode(tester, 'محمد صديق المنشاوي (مرتل)'),
          ),
          isTrue,
          reason:
              'SemanticsAction.tap must restore selected=true on default reciter',
        );

        // Teardown BEFORE checking errors and restoring FlutterError.onError
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          errors,
          isEmpty,
          reason:
              'Unexpected FlutterErrors during SettingsReciterModal interactions (including teardown): ${errors.map((e) => e.exceptionAsString()).join(" | ")}',
        );
      } finally {
        AyahAudioPlayer.instance.resetForTesting();
        semanticsHandle.dispose();
        FlutterError.onError = prevOnError;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );
}
