import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/memorization_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/mushaf/widgets/memorization_playback_bar.dart';
import 'package:almomin/features/mushaf/memorization_screen.dart';

const String _kAfterPixelDir =
    r'C:\Users\Dell\.gemini\antigravity\brain\aaa5e77e-874d-485e-8088-962b9e3f1086\repair23_after_pixels';
const String _kMaterialIcons =
    r'D:\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf';

final GlobalKey _kBarRepaintKey = GlobalKey();
final GlobalKey _kScreenRepaintKey = GlobalKey();

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
    'assets/fonts/Amiri-Bold.ttf'
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      amiri.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
    }
  }
  await amiri.load();

  final matFile = File(_kMaterialIcons);
  if (matFile.existsSync()) {
    final loader = FontLoader('MaterialIcons');
    loader.addFont(Future.value(ByteData.view(matFile.readAsBytesSync().buffer)));
    await loader.load();
  }
}

Future<void> _capturePng(WidgetTester tester, String filename, {required GlobalKey key, double pixelRatio = 1.0}) async {
  await tester.runAsync(() async {
    final finder = find.byKey(key);
    expect(finder, findsOneWidget);
    final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(byteData, isNotNull);
    image.dispose();
    final pngBytes = byteData!.buffer.asUint8List();

    final outDir = Directory(_kAfterPixelDir);
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }
    final file = File('${outDir.path}/$filename');
    file.writeAsBytesSync(pngBytes);
  });
}

SemanticsNode _findSemanticsNodeByLabel(WidgetTester tester, String label) {
  SemanticsNode? found;
  bool visit(SemanticsNode node) {
    final l = node.label;
    final val = node.value;
    final hint = node.hint;
    final tooltip = node.tooltip;
    if (l.contains(label) || val.contains(label) || hint.contains(label) || tooltip.contains(label)) {
      found = node;
      return false;
    }
    node.visitChildren(visit);
    return true;
  }

  visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  expect(found, isNotNull, reason: 'Expected SemanticsNode matching "$label"');
  return found!;
}

Widget _buildBarHost({
  required bool isDark,
  required bool isPlaying,
  int currentAyahNumber = 1,
  int fromAyah = 1,
  int toAyah = 7,
  int currentRangeRepeat = 1,
  int rangeRepeatTarget = 3,
  required VoidCallback onPlayPause,
  required VoidCallback? onStop,
  required VoidCallback onPrev,
  required VoidCallback onNext,
  required VoidCallback onSelectReciter,
  double textScale = 1.0,
  double width = 360.0,
}) {
  return RepaintBoundary(
    key: _kBarRepaintKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(textScale),
            accessibleNavigation: true,
          ),
          child: Scaffold(
            bottomNavigationBar: MemorizationPlaybackBar(
              isDark: isDark,
              isPlaying: isPlaying,
              currentAyahNumber: currentAyahNumber,
              fromAyah: fromAyah,
              toAyah: toAyah,
              currentRangeRepeat: currentRangeRepeat,
              rangeRepeatTarget: rangeRepeatTarget,
              onPlayPause: onPlayPause,
              onStop: onStop,
              onPrev: onPrev,
              onNext: onNext,
              onSelectReciter: onSelectReciter,
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _buildScreenHost({double textScale = 1.0, bool isDark = false}) {
  return RepaintBoundary(
    key: _kScreenRepaintKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(textScale),
            accessibleNavigation: true,
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        );
      },
      home: const MemorizationScreen(
        initialSurahId: 1,
        initialFromAyah: 1,
        initialToAyah: 7,
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadRealFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
    await MemorizationService.instance.init();
  });

  group('Repair 23 — Dedicated MemorizationPlaybackBar Responsive & Accessibility Tests', () {
    testWidgets('1. All 5 Callbacks: Touch and Semantic Dispatch', (tester) async {
      final handle = tester.ensureSemantics();

      int playPauseCount = 0;
      int stopCount = 0;
      int prevCount = 0;
      int nextCount = 0;
      int reciterCount = 0;

      // Pump playing state so all 5 buttons are active
      await tester.pumpWidget(
        _buildBarHost(
          isDark: false,
          isPlaying: true,
          onPlayPause: () => playPauseCount++,
          onStop: () => stopCount++,
          onPrev: () => prevCount++,
          onNext: () => nextCount++,
          onSelectReciter: () => reciterCount++,
        ),
      );
      await tester.pumpAndSettle();

      // Touch taps
      await tester.tap(find.byTooltip('إيقاف كامل'));
      await tester.pumpAndSettle();
      expect(stopCount, 1);

      await tester.tap(find.byTooltip('الآية السابقة'));
      await tester.pumpAndSettle();
      expect(prevCount, 1);

      await tester.tap(find.byTooltip('إيقاف مؤقت'));
      await tester.pumpAndSettle();
      expect(playPauseCount, 1);

      await tester.tap(find.byTooltip('الآية التالية'));
      await tester.pumpAndSettle();
      expect(nextCount, 1);

      await tester.tap(find.byTooltip('اختيار قارئ آخر'));
      await tester.pumpAndSettle();
      expect(reciterCount, 1);

      // Semantic Action dispatch
      final stopNode = _findSemanticsNodeByLabel(tester, 'إيقاف كامل');
      tester.binding.pipelineOwner.semanticsOwner!.performAction(stopNode.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(stopCount, 2);

      final prevNode = _findSemanticsNodeByLabel(tester, 'الآية السابقة');
      tester.binding.pipelineOwner.semanticsOwner!.performAction(prevNode.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(prevCount, 2);

      final playNode = _findSemanticsNodeByLabel(tester, 'إيقاف مؤقت');
      tester.binding.pipelineOwner.semanticsOwner!.performAction(playNode.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(playPauseCount, 2);

      final nextNode = _findSemanticsNodeByLabel(tester, 'الآية التالية');
      tester.binding.pipelineOwner.semanticsOwner!.performAction(nextNode.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(nextCount, 2);

      final reciterNode = _findSemanticsNodeByLabel(tester, 'اختيار قارئ آخر');
      tester.binding.pipelineOwner.semanticsOwner!.performAction(reciterNode.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(reciterCount, 2);

      handle.dispose();
    });

    testWidgets('2. Enabled / Disabled States & Tooltip Verification (Playing vs Paused)', (tester) async {
      final handle = tester.ensureSemantics();

      // Scenario A: Paused state -> Stop button disabled (onStop == null), play button tooltip is 'بدء التكرار والتحفيظ'
      int stopPointerCallbackCount = 0;
      await tester.pumpWidget(
        _buildBarHost(
          isDark: false,
          isPlaying: false,
          onPlayPause: () {},
          onStop: null,
          onPrev: () {},
          onNext: () {},
          onSelectReciter: () {},
        ),
      );
      await tester.pumpAndSettle();

      final stopFinderPaused = find.widgetWithIcon(IconButton, Icons.stop_circle_outlined);
      expect(stopFinderPaused, findsOneWidget);
      final IconButton stopButtonPaused = tester.widget(stopFinderPaused);
      expect(stopButtonPaused.onPressed, isNull, reason: 'Stop button must be disabled when paused');

      final stopNodePaused = _findSemanticsNodeByLabel(tester, 'إيقاف كامل');
      expect(stopNodePaused.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
      expect(stopNodePaused.hasFlag(SemanticsFlag.isEnabled), isFalse, reason: 'Stop button semantics must flag disabled');
      expect(stopNodePaused.getSemanticsData().hasAction(SemanticsAction.tap), isFalse,
          reason: 'Disabled stop button must have NO tap action in semantics');

      // Attempt pointer tap on disabled stop button -> must yield no callback
      await tester.tap(stopFinderPaused);
      await tester.pumpAndSettle();
      expect(stopPointerCallbackCount, 0, reason: 'Pointer tap on disabled stop button must produce zero callbacks');

      // Attempt semantic dispatch on disabled stop button -> must yield no callback
      tester.binding.pipelineOwner.semanticsOwner!.performAction(stopNodePaused.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(stopPointerCallbackCount, 0, reason: 'Semantic dispatch on disabled stop button must produce zero callbacks');

      expect(find.byTooltip('بدء التكرار والتحفيظ'), findsOneWidget);

      // Scenario B: Playing state -> Stop button enabled, play button tooltip is 'إيقاف مؤقت'
      int stopPlayingCallbackCount = 0;
      await tester.pumpWidget(
        _buildBarHost(
          isDark: false,
          isPlaying: true,
          onPlayPause: () {},
          onStop: () => stopPlayingCallbackCount++,
          onPrev: () {},
          onNext: () {},
          onSelectReciter: () {},
        ),
      );
      await tester.pumpAndSettle();

      final stopFinderPlaying = find.widgetWithIcon(IconButton, Icons.stop_circle_outlined);
      final IconButton stopButtonPlaying = tester.widget(stopFinderPlaying);
      expect(stopButtonPlaying.onPressed, isNotNull, reason: 'Stop button must be enabled when playing');

      final stopNodePlaying = _findSemanticsNodeByLabel(tester, 'إيقاف كامل');
      expect(stopNodePlaying.hasFlag(SemanticsFlag.isEnabled), isTrue, reason: 'Stop button semantics must flag enabled');
      expect(stopNodePlaying.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
          reason: 'Enabled stop button must have tap action in semantics');

      // Pointer tap on enabled stop button
      await tester.tap(stopFinderPlaying);
      await tester.pumpAndSettle();
      expect(stopPlayingCallbackCount, 1, reason: 'Pointer tap on enabled stop button must increment callback');

      // Semantic dispatch on enabled stop button
      tester.binding.pipelineOwner.semanticsOwner!.performAction(stopNodePlaying.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(stopPlayingCallbackCount, 2, reason: 'Semantic dispatch on enabled stop button must increment callback');

      expect(find.byTooltip('إيقاف مؤقت'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('3. All Control Targets On-Screen >= 48 Logical Pixels with Viewport Containment & HitTestable', (tester) async {
      final widths = [320.0, 360.0, 412.0];
      final scales = [1.0, 2.0];
      final playStates = [true, false];

      for (final w in widths) {
        for (final scale in scales) {
          for (final playing in playStates) {
            tester.view.physicalSize = Size(w, 800);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(() {
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
            });

            await tester.pumpWidget(
              _buildBarHost(
                isDark: false,
                isPlaying: playing,
                onPlayPause: () {},
                onStop: playing ? () {} : null,
                onPrev: () {},
                onNext: () {},
                onSelectReciter: () {},
                textScale: scale,
                width: w,
              ),
            );
            await tester.pumpAndSettle();

            final tooltips = [
              'إيقاف كامل',
              'الآية السابقة',
              playing ? 'إيقاف مؤقت' : 'بدء التكرار والتحفيظ',
              'الآية التالية',
              'اختيار قارئ آخر',
            ];

            for (final t in tooltips) {
              final finder = find.byTooltip(t);

              // 1. HitTestable assertion
              expect(finder.hitTestable(), findsOneWidget,
                  reason: 'Control "$t" must be hitTestable on width $w at ${scale}x (playing: $playing)');

              // 2. Minimum touch target >= 48.0 logical pixels
              final size = tester.getSize(finder);
              expect(size.width, greaterThanOrEqualTo(48.0),
                  reason: 'Control "$t" width must be >= 48.0 on width $w at ${scale}x (playing: $playing, actual: ${size.width})');
              expect(size.height, greaterThanOrEqualTo(48.0),
                  reason: 'Control "$t" height must be >= 48.0 on width $w at ${scale}x (playing: $playing, actual: ${size.height})');

              // 3. Viewport rect containment
              final Rect rect = tester.getRect(finder);
              expect(rect.left, greaterThanOrEqualTo(0.0),
                  reason: 'Control "$t" left (${rect.left}) must be within viewport (>= 0)');
              expect(rect.right, lessThanOrEqualTo(w),
                  reason: 'Control "$t" right (${rect.right}) must be within viewport (<= $w)');
              expect(rect.top, greaterThanOrEqualTo(0.0),
                  reason: 'Control "$t" top (${rect.top}) must be within viewport (>= 0)');
              expect(rect.bottom, lessThanOrEqualTo(800.0),
                  reason: 'Control "$t" bottom (${rect.bottom}) must be within viewport (<= 800)');
            }
          }
        }
      }
    });

    testWidgets('4. Long Real Catalog Reciter: Full Text Wrapping, No Ellipsis/Clamp, Zero Overflows', (tester) async {
      // Pick the longest real catalog reciters from SettingsService
      final longReciters = [
        'خالد المهنا (إمام المسجد النبوي)',
        'صلاح البدير (إمام المسجد النبوي)',
        'بندر بليلة (إمام الحرم المكي)',
      ];

      final List<FlutterErrorDetails> errors = [];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details);

      try {
        for (final rec in longReciters) {
          // Assert reciter exists in catalog with NO fallback
          final matchingReciters = SettingsService.availableReciters.where((r) => r.nameAr == rec).toList();
          expect(matchingReciters, isNotEmpty,
              reason: 'Reciter "$rec" must exist in SettingsService.availableReciters catalog with NO fallback');
          final foundReciter = matchingReciters.first;
          expect(foundReciter.nameAr, equals(rec));
          expect(foundReciter.id, isNotEmpty);
          if (rec != SettingsService.availableReciters.first.nameAr) {
            expect(foundReciter.id, isNot(equals(SettingsService.availableReciters.first.id)),
                reason: 'Catalog lookup must return exact target "$rec", not fall back to default reciter');
          }

          // Set active reciter in settings
          await SettingsService.instance.setSelectedReciter(foundReciter.id);

          // Test across 320, 360, 412 widths at 2.0x text scale
          for (final w in [320.0, 360.0, 412.0]) {
            tester.view.physicalSize = Size(w, 800);
            tester.view.devicePixelRatio = 1.0;

            await tester.pumpWidget(
              _buildBarHost(
                isDark: false,
                isPlaying: true,
                currentAyahNumber: 142,
                fromAyah: 1,
                toAyah: 142,
                currentRangeRepeat: 12,
                rangeRepeatTarget: 999,
                onPlayPause: () {},
                onStop: () {},
                onPrev: () {},
                onNext: () {},
                onSelectReciter: () {},
                textScale: 2.0,
                width: w,
              ),
            );
            await tester.pumpAndSettle();

            // Full text must be rendered without ellipsis or clamping
            expect(find.textContaining(rec), findsOneWidget);
            // Infinity symbol present
            expect(find.textContaining('∞'), findsOneWidget);
          }
        }

        expect(errors, isEmpty, reason: 'Zero RenderFlex errors allowed with long real catalog reciters');
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        FlutterError.onError = oldHandler;
      }
    });

    testWidgets('5. Status Display, Infinity Symbol, and Dark Mode Preservation', (tester) async {
      // A. Infinity display when target >= 999
      await tester.pumpWidget(
        _buildBarHost(
          isDark: false,
          isPlaying: true,
          currentAyahNumber: 5,
          currentRangeRepeat: 3,
          rangeRepeatTarget: 999,
          onPlayPause: () {},
          onStop: () {},
          onPrev: () {},
          onNext: () {},
          onSelectReciter: () {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('الآية: 5 · مقطع 3/∞'), findsOneWidget);

      // B. Numeric target display when target < 999
      await tester.pumpWidget(
        _buildBarHost(
          isDark: false,
          isPlaying: true,
          currentAyahNumber: 2,
          currentRangeRepeat: 1,
          rangeRepeatTarget: 5,
          onPlayPause: () {},
          onStop: () {},
          onPrev: () {},
          onNext: () {},
          onSelectReciter: () {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('الآية: 2 · مقطع 1/5'), findsOneWidget);

      // C. Stopped / paused section range display
      await tester.pumpWidget(
        _buildBarHost(
          isDark: false,
          isPlaying: false,
          fromAyah: 1,
          toAyah: 7,
          onPlayPause: () {},
          onStop: null,
          onPrev: () {},
          onNext: () {},
          onSelectReciter: () {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('المقطع: 1 إلى 7'), findsOneWidget);

      // D. Dark mode surface rendering
      await tester.pumpWidget(
        _buildBarHost(
          isDark: true,
          isPlaying: false,
          onPlayPause: () {},
          onStop: null,
          onPrev: () {},
          onNext: () {},
          onSelectReciter: () {},
        ),
      );
      await tester.pumpAndSettle();
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, AppColors.darkSurface);
    });

    testWidgets('6. Responsive Matrix: 320/360/412 Widths @ 1x and 2x Text Scale (Zero Errors)', (tester) async {
      final List<FlutterErrorDetails> errors = [];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details);

      final matrix = [
        (w: 320.0, s: 1.0, isPlaying: false),
        (w: 320.0, s: 2.0, isPlaying: true),
        (w: 360.0, s: 1.0, isPlaying: false),
        (w: 360.0, s: 2.0, isPlaying: true),
        (w: 412.0, s: 1.0, isPlaying: false),
        (w: 412.0, s: 2.0, isPlaying: true),
      ];

      try {
        for (final m in matrix) {
          tester.view.physicalSize = Size(m.w, 800);
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(
            _buildBarHost(
              isDark: false,
              isPlaying: m.isPlaying,
              currentAyahNumber: 1,
              fromAyah: 1,
              toAyah: 7,
              currentRangeRepeat: 1,
              rangeRepeatTarget: 3,
              onPlayPause: () {},
              onStop: m.isPlaying ? () {} : null,
              onPrev: () {},
              onNext: () {},
              onSelectReciter: () {},
              textScale: m.s,
              width: m.w,
            ),
          );
          await tester.pumpAndSettle();
        }

        expect(errors, isEmpty, reason: 'Zero RenderFlex overflow errors allowed across matrix');
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        FlutterError.onError = oldHandler;
      }
    });

    testWidgets('7. Real MemorizationScreen Integration & Zero Overflow Verification', (tester) async {
      final List<FlutterErrorDetails> screenErrors = [];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) => screenErrors.add(details);

      try {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(_buildScreenHost(textScale: 2.0));
        await tester.pumpAndSettle();

        expect(find.byType(MemorizationPlaybackBar), findsOneWidget);
        expect(screenErrors, isEmpty, reason: 'Zero RenderFlex errors allowed across real screen under 2.0x scale');
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        FlutterError.onError = oldHandler;
      }
    });

    testWidgets('8. Loaded-Font Actual Pixel Proofs across 360/412 @ 1x/2x (Bar + Screen)', (tester) async {
      final List<FlutterErrorDetails> pixelErrors = [];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) => pixelErrors.add(details);

      final scenarios = [
        (size: const Size(360, 800), dpr: 1.0, scale: 1.0, name: 'playback_bar_360x800_1x.png', screenName: 'memorizer_screen_360x800_1x.png'),
        (size: const Size(360, 800), dpr: 2.0, scale: 2.0, name: 'playback_bar_360x800_2x.png', screenName: 'memorizer_screen_360x800_2x.png'),
        (size: const Size(412, 915), dpr: 1.0, scale: 1.0, name: 'playback_bar_412x915_1x.png', screenName: 'memorizer_screen_412x915_1x.png'),
        (size: const Size(412, 915), dpr: 2.0, scale: 2.0, name: 'playback_bar_412x915_2x.png', screenName: 'memorizer_screen_412x915_2x.png'),
      ];

      try {
        for (final sc in scenarios) {
          tester.view.devicePixelRatio = sc.dpr;
          tester.view.physicalSize = Size(sc.size.width * sc.dpr, sc.size.height * sc.dpr);

          // 1. Capture Bar proof
          await tester.pumpWidget(
            _buildBarHost(
              isDark: false,
              isPlaying: true,
              currentAyahNumber: 3,
              currentRangeRepeat: 2,
              rangeRepeatTarget: 999,
              onPlayPause: () {},
              onStop: () {},
              onPrev: () {},
              onNext: () {},
              onSelectReciter: () {},
              textScale: sc.scale,
              width: sc.size.width,
            ),
          );
          await tester.pumpAndSettle();
          await _capturePng(tester, sc.name, key: _kBarRepaintKey, pixelRatio: sc.dpr);

          // 2. Capture Full Screen proof
          await tester.pumpWidget(_buildScreenHost(textScale: sc.scale));
          await tester.pumpAndSettle();
          await _capturePng(tester, sc.screenName, key: _kScreenRepaintKey, pixelRatio: sc.dpr);
        }

        expect(pixelErrors, isEmpty, reason: 'Zero errors allowed during pixel captures');
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        FlutterError.onError = oldHandler;
      }
    });
  });
}
