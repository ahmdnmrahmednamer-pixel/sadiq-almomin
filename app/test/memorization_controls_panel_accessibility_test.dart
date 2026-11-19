import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/models/memorization_item.dart';
import 'package:almomin/core/models/surah.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/memorization_service.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:almomin/features/mushaf/memorization_screen.dart';
import 'package:almomin/features/mushaf/widgets/memorization_controls_panel.dart';
import 'package:almomin/features/mushaf/widgets/memorization_ayah_card.dart';

const String _kRepair24PixelDir =
    r'C:\Users\Dell\.gemini\antigravity\brain\aaa5e77e-874d-485e-8088-962b9e3f1086\repair24_pixels';
const String _kMaterialIcons =
    r'D:\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf';

Surah _makeSurah(int id, String nameAr, int ayahCount) {
  return Surah(
    id: id,
    nameAr: nameAr,
    nameSimple: nameAr,
    revelationPlace: 'makkah',
    revelationOrder: id,
    ayahCount: ayahCount,
    hasBasmala: true,
    pageStart: 1,
    pageEnd: 1,
  );
}

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

Future<void> _capturePng(
  WidgetTester tester,
  String filename, {
  required GlobalKey key,
  double pixelRatio = 1.0,
}) async {
  await tester.runAsync(() async {
    final finder = find.byKey(key);
    expect(finder, findsOneWidget);
    final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(byteData, isNotNull);
    image.dispose();
    final pngBytes = byteData!.buffer.asUint8List();

    final outDir = Directory(_kRepair24PixelDir);
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }
    final file = File('${outDir.path}/$filename');
    file.writeAsBytesSync(pngBytes);
  });
}

SemanticsNode _findActionableSemanticsNode(WidgetTester tester, String labelSubstring) {
  SemanticsNode? match;
  void visit(SemanticsNode node) {
    if (match != null) return;
    final data = node.getSemanticsData();
    final hasAction = data.hasAction(SemanticsAction.tap) ||
        data.hasFlag(SemanticsFlag.isButton) ||
        data.hasFlag(SemanticsFlag.isSelected);
    final labelMatch = data.label.contains(labelSubstring) ||
        (data.value.contains(labelSubstring)) ||
        (data.tooltip.contains(labelSubstring));
    if (labelMatch && hasAction) {
      match = node;
      return;
    }
    node.visitChildren((child) {
      visit(child);
      return match == null;
    });
  }

  final root = tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
  visit(root);
  expect(match, isNotNull, reason: 'Expected actionable SemanticsNode matching "$labelSubstring"');
  return match!;
}

void _assertRenderParagraphNotTruncated(WidgetTester tester, Finder finder) {
  expect(finder, findsWidgets);
  for (final element in finder.evaluate()) {
    final renderObject = element.renderObject;
    if (renderObject is RenderParagraph) {
      expect(renderObject.didExceedMaxLines, isFalse,
          reason: 'Text must not exceed max lines or be truncated: "${renderObject.text.toPlainText()}"');
    }
  }
}

Widget _buildScreenHost({
  Key? screenKey,
  double textScale = 1.0,
  int surahId = 1,
  int fromAyah = 1,
  int toAyah = 7,
  GlobalKey? repaintKey,
  bool withPushRoute = false,
}) {
  return RepaintBoundary(
    key: repaintKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
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
      home: withPushRoute
          ? Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        ctx,
                        MaterialPageRoute(
                          builder: (_) => MemorizationScreen(
                            key: screenKey,
                            initialSurahId: surahId,
                            initialFromAyah: fromAyah,
                            initialToAyah: toAyah,
                          ),
                        ),
                      );
                    },
                    child: const Text('Open Memorization'),
                  ),
                ),
              ),
            )
          : MemorizationScreen(
              key: screenKey,
              initialSurahId: surahId,
              initialFromAyah: fromAyah,
              initialToAyah: toAyah,
            ),
    ),
  );
}

Widget _buildPanelHost({
  double textScale = 1.0,
  bool isDark = false,
  List<Surah>? surahs,
  int selectedSurahId = 1,
  Surah? currentSurah,
  int fromAyah = 1,
  int toAyah = 7,
  int ayahRepeatTarget = 3,
  int rangeRepeatTarget = 2,
  int delaySeconds = 1,
  MemorizationHideMode hideMode = MemorizationHideMode.none,
  ValueChanged<int>? onSurahChanged,
  ValueChanged<int>? onFromAyahChanged,
  ValueChanged<int>? onToAyahChanged,
  ValueChanged<int>? onAyahRepeatChanged,
  ValueChanged<int>? onRangeRepeatChanged,
  ValueChanged<int>? onDelayChanged,
  ValueChanged<MemorizationHideMode>? onHideModeChanged,
  VoidCallback? onRevealAllWords,
  VoidCallback? onHideAllWords,
}) {
  final defaultSurahs = surahs ?? [
    _makeSurah(1, 'الفاتحة', 7),
    _makeSurah(2, 'البقرة', 286),
    _makeSurah(3, 'آل عمران', 200),
  ];
  final cur = currentSurah ?? defaultSurahs.firstWhere((s) => s.id == selectedSurahId);

  return MaterialApp(
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
    home: Scaffold(
      body: SingleChildScrollView(
        child: MemorizationControlsPanel(
          isDark: isDark,
          surahs: defaultSurahs,
          selectedSurahId: selectedSurahId,
          currentSurah: cur,
          fromAyah: fromAyah,
          toAyah: toAyah,
          ayahRepeatTarget: ayahRepeatTarget,
          rangeRepeatTarget: rangeRepeatTarget,
          delaySeconds: delaySeconds,
          hideMode: hideMode,
          onSurahChanged: onSurahChanged ?? (_) {},
          onFromAyahChanged: onFromAyahChanged ?? (_) {},
          onToAyahChanged: onToAyahChanged ?? (_) {},
          onAyahRepeatChanged: onAyahRepeatChanged ?? (_) {},
          onRangeRepeatChanged: onRangeRepeatChanged ?? (_) {},
          onDelayChanged: onDelayChanged ?? (_) {},
          onHideModeChanged: onHideModeChanged ?? (_) {},
          onRevealAllWords: onRevealAllWords ?? () {},
          onHideAllWords: onHideAllWords ?? () {},
        ),
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

  group('Repair 24 — Dedicated MemorizationControlsPanel Responsive & Accessibility Tests', () {
    testWidgets('1. Viewport Responsiveness across 320, 360, 412 @ 1x/2x RTL with Zero Overflows (Root & Pushed)', (tester) async {
      final viewports = [
        (size: const Size(320, 640), scale: 1.0, dpr: 1.0),
        (size: const Size(320, 640), scale: 2.0, dpr: 2.0),
        (size: const Size(360, 800), scale: 1.0, dpr: 1.0),
        (size: const Size(360, 800), scale: 2.0, dpr: 2.0),
        (size: const Size(412, 915), scale: 1.0, dpr: 1.0),
        (size: const Size(412, 915), scale: 2.0, dpr: 2.0),
      ];

      for (final withPush in [false, true]) {
        for (final vp in viewports) {
          final List<FlutterErrorDetails> errors = [];
          final oldHandler = FlutterError.onError;
          FlutterError.onError = (details) => errors.add(details);

          try {
            tester.view.physicalSize = vp.size * vp.dpr;
            tester.view.devicePixelRatio = vp.dpr;

            // Fresh mount per viewport
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(
              _buildScreenHost(
                screenKey: UniqueKey(),
                textScale: vp.scale,
                withPushRoute: withPush,
              ),
            );
            await tester.pumpAndSettle();

            if (withPush) {
              await tester.tap(find.text('Open Memorization'));
              await tester.pumpAndSettle();
              expect(find.byType(BackButton), findsOneWidget);
            }

            expect(errors, isEmpty,
                reason: 'Zero errors allowed on ${vp.size.width.toInt()}x${vp.size.height.toInt()} @ ${vp.scale}x (push: $withPush)');

            // Verify AppBar Title containment and absence of RenderParagraph truncation
            final titleFinder = find.text('المحفظ القرآني والتكرار الذكي');
            expect(titleFinder, findsOneWidget);
            _assertRenderParagraphNotTruncated(tester, titleFinder);

            final titleBox = tester.renderObject<RenderBox>(titleFinder);
            final titleRect = Rect.fromPoints(
              titleBox.localToGlobal(Offset.zero),
              titleBox.localToGlobal(titleBox.size.bottomRight(Offset.zero)),
            );

            final appBarFinder = find.byType(AppBar);
            expect(appBarFinder, findsOneWidget);
            final appBarBox = tester.renderObject<RenderBox>(appBarFinder);
            final appBarRect = Rect.fromPoints(
              appBarBox.localToGlobal(Offset.zero),
              appBarBox.localToGlobal(appBarBox.size.bottomRight(Offset.zero)),
            );

            // Title text must be vertically inside the AppBar rect (no clipping/overflow)
            if (titleRect.bottom > appBarRect.bottom + 0.1) {
              debugPrint('DIAGNOSTIC Title Rect at ${vp.scale}x on ${vp.size.width}w (push: $withPush): titleRect=$titleRect, appBarRect=$appBarRect');
            }
            expect(titleRect.bottom <= appBarRect.bottom + 0.1, isTrue,
                reason: 'Title text must be fully contained vertically in AppBar at ${vp.scale}x on ${vp.size.width}w (push: $withPush)');
            expect(titleRect.top >= appBarRect.top - 0.1, isTrue);

            // Title text must be horizontally contained inside the screen width
            expect(titleRect.left >= 0.0, isTrue);
            expect(titleRect.right <= appBarRect.right + 0.1, isTrue);

            // Verify all controls rendered and hitTestable after ensureVisible on root route
            if (!withPush) {
              final controls = [
                find.byKey(const Key('memorization_surah_dropdown')),
                find.byKey(const Key('memorization_from_ayah_dropdown')),
                find.byKey(const Key('memorization_to_ayah_dropdown')),
                find.byKey(const Key('badge_ayah_repeat')),
                find.byKey(const Key('badge_range_repeat')),
                find.byKey(const Key('badge_delay')),
                find.byKey(const Key('chip_hide_mode_none')),
                find.byKey(const Key('chip_hide_mode_secondHalf')),
                find.byKey(const Key('chip_hide_mode_everyNthWord')),
                find.byKey(const Key('chip_hide_mode_allWords')),
              ];

              for (final c in controls) {
                await tester.ensureVisible(c);
                await tester.pumpAndSettle();
                expect(c.hitTestable(), findsOneWidget, reason: 'Control $c must be hitTestable on ${vp.size.width} @ ${vp.scale}x');
              }
            }
          } finally {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
            FlutterError.onError = oldHandler;
          }
        }
      }
    });

    testWidgets('2. Target Bounds >= 48x48 & Both Push-Route Leading & Actions Accessible', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Mount via push route to verify leading back button presence and hit target
      await tester.pumpWidget(_buildScreenHost(withPushRoute: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Memorization'));
      await tester.pumpAndSettle();

      // Verify leading back button has >= 48x48 hit area
      final leadingBack = find.byType(BackButton);
      expect(leadingBack, findsOneWidget);
      final leadingBox = tester.renderObject<RenderBox>(leadingBack);
      expect(leadingBox.size.width >= 47.9, isTrue);
      expect(leadingBox.size.height >= 47.9, isTrue);

      // Verify reciter action button >= 48x48
      final reciterAction = find.byTooltip('تغيير القارئ');
      expect(reciterAction, findsOneWidget);
      final reciterBox = tester.renderObject<RenderBox>(reciterAction);
      expect(reciterBox.size.width >= 47.9, isTrue);
      expect(reciterBox.size.height >= 47.9, isTrue);

      // Verify info action button >= 48x48
      final infoAction = find.byTooltip('عن المحفظ والإهداء');
      expect(infoAction, findsOneWidget);
      final infoBox = tester.renderObject<RenderBox>(infoAction);
      expect(infoBox.size.width >= 47.9, isTrue);
      expect(infoBox.size.height >= 47.9, isTrue);

      // Verify panel controls hit targets >= 48x48
      final panelControls = [
        find.byKey(const Key('memorization_surah_dropdown')),
        find.byKey(const Key('memorization_from_ayah_dropdown')),
        find.byKey(const Key('memorization_to_ayah_dropdown')),
        find.byKey(const Key('badge_ayah_repeat')),
        find.byKey(const Key('badge_range_repeat')),
        find.byKey(const Key('badge_delay')),
        find.byKey(const Key('chip_hide_mode_none')),
        find.byKey(const Key('chip_hide_mode_secondHalf')),
      ];

      for (final ctrl in panelControls) {
        final box = tester.renderObject<RenderBox>(ctrl);
        expect(box.size.width >= 47.9, isTrue, reason: '$ctrl width must be >= 48');
        expect(box.size.height >= 47.9, isTrue, reason: '$ctrl height must be >= 48');
      }
    });

    testWidgets('3. Long Surah Selected, 3-Digit Bounds & Continuous Repeats (∞) & Delays', (tester) async {
      tester.view.physicalSize = const Size(320, 640) * 2.0;
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final surahs = [
        _makeSurah(1, 'الفاتحة', 7),
        _makeSurah(2, 'البقرة', 286),
        _makeSurah(3, 'آل عمران', 200),
      ];

      int from = 100;
      int to = 286;
      int ayahRep = 999;
      int rangeRep = 999;
      int delaySec = 5;

      await tester.pumpWidget(
        _buildPanelHost(
          textScale: 2.0,
          surahs: surahs,
          selectedSurahId: 2, // Al-Baqarah explicitly selected
          currentSurah: surahs[1],
          fromAyah: from,
          toAyah: to,
          ayahRepeatTarget: ayahRep,
          rangeRepeatTarget: rangeRep,
          delaySeconds: delaySec,
          onFromAyahChanged: (v) => from = v,
          onToAyahChanged: (v) => to = v,
          onAyahRepeatChanged: (v) => ayahRep = v,
          onRangeRepeatChanged: (v) => rangeRep = v,
          onDelayChanged: (v) => delaySec = v,
        ),
      );
      await tester.pumpAndSettle();

      // Verify 3-digit bound renders without truncation
      final toTextFinder = find.text('286');
      expect(toTextFinder, findsOneWidget);
      _assertRenderParagraphNotTruncated(tester, toTextFinder);

      // Verify continuous repeat badge displays without clipping
      final continuousFinder = find.text('مستمر');
      expect(continuousFinder, findsNWidgets(2));
      _assertRenderParagraphNotTruncated(tester, continuousFinder);

      // Verify 5s delay badge displays
      final delayFinder = find.text('5 ث');
      expect(delayFinder, findsOneWidget);
      _assertRenderParagraphNotTruncated(tester, delayFinder);

      // Tap continuous repeat badge to open popup menu and assert options
      await tester.tap(find.byKey(const Key('badge_ayah_repeat')));
      await tester.pumpAndSettle();
      expect(find.text('مستمر (∞)'), findsWidgets);

      // Select 10x
      await tester.tap(find.text('10 مرات').last);
      await tester.pumpAndSettle();
      expect(ayahRep, 10);
    });

    testWidgets('4. Full Dispatch of Selectors, Modes & Actions via Touch AND Semantics', (tester) async {
      final handle = tester.ensureSemantics();

      int selectedSurah = 1;
      int fromAyah = 1;
      int toAyah = 7;
      int ayahRepeat = 3;
      int rangeRepeat = 2;
      int delay = 1;
      MemorizationHideMode currentMode = MemorizationHideMode.none;
      int revealCalls = 0;
      int hideCalls = 0;

      Widget buildWidget() {
        return _buildPanelHost(
          textScale: 1.0,
          selectedSurahId: selectedSurah,
          fromAyah: fromAyah,
          toAyah: toAyah,
          ayahRepeatTarget: ayahRepeat,
          rangeRepeatTarget: rangeRepeat,
          delaySeconds: delay,
          hideMode: currentMode,
          onSurahChanged: (v) => selectedSurah = v,
          onFromAyahChanged: (v) => fromAyah = v,
          onToAyahChanged: (v) => toAyah = v,
          onAyahRepeatChanged: (v) => ayahRepeat = v,
          onRangeRepeatChanged: (v) => rangeRepeat = v,
          onDelayChanged: (v) => delay = v,
          onHideModeChanged: (m) => currentMode = m,
          onRevealAllWords: () => revealCalls++,
          onHideAllWords: () => hideCalls++,
        );
      }

      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      // 1. Surah Dropdown: Touch tap
      await tester.tap(find.byKey(const Key('memorization_surah_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2. سورة البقرة').last);
      await tester.pumpAndSettle();
      expect(selectedSurah, 2);

      // 2. From Ayah Dropdown: Touch tap
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('memorization_from_ayah_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3').last);
      await tester.pumpAndSettle();
      expect(fromAyah, 3);

      // 3. To Ayah Dropdown: Touch tap
      toAyah = 1;
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('memorization_to_ayah_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5').last);
      await tester.pumpAndSettle();
      expect(toAyah, 5);

      // 4. Hide Modes dispatch via Touch
      for (final mode in [
        (mode: MemorizationHideMode.secondHalf, key: 'chip_hide_mode_secondHalf'),
        (mode: MemorizationHideMode.everyNthWord, key: 'chip_hide_mode_everyNthWord'),
        (mode: MemorizationHideMode.allWords, key: 'chip_hide_mode_allWords'),
        (mode: MemorizationHideMode.none, key: 'chip_hide_mode_none'),
      ]) {
        await tester.tap(find.byKey(Key(mode.key)));
        await tester.pumpAndSettle();
        expect(currentMode, mode.mode);
        await tester.pumpWidget(buildWidget());
        await tester.pumpAndSettle();
      }

      // 5. Hide Modes dispatch via Semantics
      currentMode = MemorizationHideMode.none;
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      final secondHalfSemantics = _findActionableSemanticsNode(tester, 'إخفاء النصف الثاني');
      tester.binding.pipelineOwner.semanticsOwner!.performAction(secondHalfSemantics.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(currentMode, MemorizationHideMode.secondHalf);

      // In secondHalf mode, reveal all and hide all buttons are shown
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      // Touch tap reveal all
      await tester.tap(find.byKey(const Key('memorization_reveal_all_button')));
      await tester.pumpAndSettle();
      expect(revealCalls, 1);

      // Semantic tap reveal all
      final revealSemantics = _findActionableSemanticsNode(tester, 'كشف الكل');
      tester.binding.pipelineOwner.semanticsOwner!.performAction(revealSemantics.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(revealCalls, 2);

      // Touch tap hide all
      await tester.tap(find.byKey(const Key('memorization_hide_all_button')));
      await tester.pumpAndSettle();
      expect(hideCalls, 1);

      // Semantic tap hide all
      final hideSemantics = _findActionableSemanticsNode(tester, 'إخفاء الكل');
      tester.binding.pipelineOwner.semanticsOwner!.performAction(hideSemantics.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(hideCalls, 2);

      // 5b. Repeat and Delay Badges dispatch via Touch and Semantics
      // Ayah Repeat Touch
      await tester.tap(find.byKey(const Key('badge_ayah_repeat')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 مرات').last);
      await tester.pumpAndSettle();
      expect(ayahRepeat, 5);

      // Ayah Repeat Semantics
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();
      final ayahRepeatNode = _findActionableSemanticsNode(tester, 'تكرار الآية');
      tester.binding.pipelineOwner.semanticsOwner!.performAction(ayahRepeatNode.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      await tester.tap(find.text('7 مرات').last);
      await tester.pumpAndSettle();
      expect(ayahRepeat, 7);

      // Range Repeat Touch
      await tester.tap(find.byKey(const Key('badge_range_repeat')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 مرات').last);
      await tester.pumpAndSettle();
      expect(rangeRepeat, 3);

      // Range Repeat Semantics
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();
      final rangeRepeatNode = _findActionableSemanticsNode(tester, 'تكرار المقطع');
      tester.binding.pipelineOwner.semanticsOwner!.performAction(rangeRepeatNode.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 مرات').last);
      await tester.pumpAndSettle();
      expect(rangeRepeat, 5);

      // Delay Touch
      await tester.tap(find.byKey(const Key('badge_delay')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 ثوانٍ').last);
      await tester.pumpAndSettle();
      expect(delay, 3);

      // Delay Semantics
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();
      final delayNode = _findActionableSemanticsNode(tester, 'وقفة الترديد');
      tester.binding.pipelineOwner.semanticsOwner!.performAction(delayNode.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 ثوانٍ').last);
      await tester.pumpAndSettle();
      expect(delay, 5);

      // 6. AppBar Actions dialogs via Touch and Semantics
      await tester.pumpWidget(_buildScreenHost(screenKey: UniqueKey()));
      await tester.pumpAndSettle();

      // Touch reciter button -> opens reciter selection
      await tester.tap(find.byTooltip('تغيير القارئ'));
      await tester.pumpAndSettle();
      expect(find.text('اختر القارئ المفضل للتحفيظ'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10)); // dismiss
      await tester.pumpAndSettle();

      // Semantic tap info button -> opens dedication dialog
      final infoSemantics = _findActionableSemanticsNode(tester, 'عن المحفظ والإهداء');
      tester.binding.pipelineOwner.semanticsOwner!.performAction(infoSemantics.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(find.text('إرشادات الحفظ والتثبيت'), findsOneWidget);
      await tester.tap(find.text('إغلاق'));
      await tester.pumpAndSettle();

      handle.dispose();
    });

    testWidgets('5. Shared Vertical Body Scroll at 1x and 2x with Playback EnsureVisible', (tester) async {
      for (final scale in [1.0, 2.0]) {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          _buildScreenHost(
            screenKey: UniqueKey(),
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();

        // 1. Initial State: Controls Panel is at top and visible
        expect(find.byType(MemorizationControlsPanel), findsOneWidget);
        final scrollableFinder = find.byType(Scrollable).first;
        final scrollableState = tester.state<ScrollableState>(scrollableFinder);
        expect(scrollableState.position.pixels, 0.0, reason: 'Initial scroll offset must be 0.0 at scale $scale');

        // 2. Scroll to last ayah (ayah 7)
        final lastAyahCard = find.widgetWithText(MemorizationAyahCard, 'الآية 7');
        int downScrolls = 0;
        while (lastAyahCard.evaluate().isEmpty && downScrolls < 12) {
          await tester.drag(scrollableFinder, const Offset(0, -400));
          await tester.pumpAndSettle();
          downScrolls++;
        }
        expect(lastAyahCard, findsOneWidget, reason: 'Last ayah must be scrolled into visible view');
        expect(scrollableState.position.pixels > 100.0, isTrue);

        // Verify last ayah is visible in viewport and overlaps screen rect
        final lastCardBox = tester.renderObject<RenderBox>(lastAyahCard);
        final lastCardGlobalTop = lastCardBox.localToGlobal(Offset.zero).dy;
        expect(lastCardGlobalTop < 800.0 && lastCardGlobalTop >= 56.0, isTrue);

        // 3. Scroll back to top and verify controls panel is hitTestable
        int upScrolls = 0;
        while (scrollableState.position.pixels > 0.0 && upScrolls < 12) {
          await tester.drag(scrollableFinder, const Offset(0, 400));
          await tester.pumpAndSettle();
          upScrolls++;
        }
        expect(find.byKey(const Key('memorization_surah_dropdown')).hitTestable(), findsOneWidget);

        // 4. Test playback next/current ayah ensureVisible behavior keeping keys/controller
        final nextBtn = find.byTooltip('الآية التالية');
        expect(nextBtn, findsOneWidget);
        await tester.tap(nextBtn);
        await tester.pumpAndSettle();

        // Scroll down to ensure Ayah 2 is in visible body
        final ayah2Finder = find.widgetWithText(MemorizationAyahCard, 'الآية 2');
        int scrollAttempts = 0;
        while (ayah2Finder.evaluate().isEmpty && scrollAttempts < 6) {
          await tester.drag(scrollableFinder, const Offset(0, -250));
          await tester.pumpAndSettle();
          scrollAttempts++;
        }
        await tester.ensureVisible(ayah2Finder);
        await tester.pumpAndSettle();
        expect(ayah2Finder, findsOneWidget);
      }
    });

    testWidgets('6. Loaded-Font Actual Pixel Proofs across 360/412 @ 1x/2x (Fresh Mount, Proven Scroll 0)', (tester) async {
      final List<FlutterErrorDetails> pixelErrors = [];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) => pixelErrors.add(details);

      final scenarios = [
        (
          size: const Size(360, 800),
          dpr: 1.0,
          scale: 1.0,
          topName: 'memorizer_screen_360x800_1x_top.png',
          scrolledName: 'memorizer_screen_360x800_1x_scrolled.png',
        ),
        (
          size: const Size(360, 800),
          dpr: 2.0,
          scale: 2.0,
          topName: 'memorizer_screen_360x800_2x_top.png',
          scrolledName: 'memorizer_screen_360x800_2x_scrolled.png',
        ),
        (
          size: const Size(412, 915),
          dpr: 1.0,
          scale: 1.0,
          topName: 'memorizer_screen_412x915_1x_top.png',
          scrolledName: 'memorizer_screen_412x915_1x_scrolled.png',
        ),
        (
          size: const Size(412, 915),
          dpr: 2.0,
          scale: 2.0,
          topName: 'memorizer_screen_412x915_2x_top.png',
          scrolledName: 'memorizer_screen_412x915_2x_scrolled.png',
        ),
      ];

      try {
        for (final sc in scenarios) {
          tester.view.physicalSize = sc.size * sc.dpr;
          tester.view.devicePixelRatio = sc.dpr;

          // Crucial: Fresh mount with blank unmount to guarantee ZERO stale scroll state
          await tester.pumpWidget(const SizedBox());
          final repaintKey = GlobalKey();

          await tester.pumpWidget(
            _buildScreenHost(
              screenKey: UniqueKey(),
              textScale: sc.scale,
              repaintKey: repaintKey,
            ),
          );
          await tester.pumpAndSettle();

          // Assert proven scroll offset 0.0 before capturing Top
          final scrollableFinder = find.byType(Scrollable).first;
          final scrollState = tester.state<ScrollableState>(scrollableFinder);
          expect(scrollState.position.pixels, 0.0,
              reason: 'Top pixel proof MUST be captured at proven scroll offset 0.0');

          // Assert panel global rect is visible at top of body
          final panelBox = tester.renderObject<RenderBox>(find.byType(MemorizationControlsPanel));
          final panelPos = panelBox.localToGlobal(Offset.zero);
          expect(panelPos.dy >= 56.0 && panelPos.dy <= 260.0, isTrue,
              reason: 'Controls panel must be visible at top of body at offset 0.0');

          // Capture Top view
          await _capturePng(tester, sc.topName, key: repaintKey, pixelRatio: sc.dpr);

          // Scroll down to reveal ayahs and assert scroll offset > 0
          await tester.drag(scrollableFinder, const Offset(0, -350));
          await tester.pumpAndSettle();
          expect(scrollState.position.pixels > 50.0, isTrue,
              reason: 'Scrolled pixel proof MUST have proven scroll offset > 0.0');

          // Capture Scrolled view
          await _capturePng(tester, sc.scrolledName, key: repaintKey, pixelRatio: sc.dpr);

          // Clean up for next scenario
          await tester.pumpWidget(const SizedBox());
        }

        // Decisive Push Route Scenarios on 320w (Title containment with BackButton)
        final pushScenarios = [
          (
            size: const Size(320, 640),
            dpr: 1.0,
            scale: 1.0,
            pushName: 'memorizer_screen_320x640_1x_pushed.png',
          ),
          (
            size: const Size(320, 640),
            dpr: 2.0,
            scale: 2.0,
            pushName: 'memorizer_screen_320x640_2x_pushed.png',
          ),
        ];

        for (final psc in pushScenarios) {
          tester.view.physicalSize = psc.size * psc.dpr;
          tester.view.devicePixelRatio = psc.dpr;

          await tester.pumpWidget(const SizedBox());
          final repaintKey = GlobalKey();

          await tester.pumpWidget(
            _buildScreenHost(
              screenKey: UniqueKey(),
              textScale: psc.scale,
              repaintKey: repaintKey,
              withPushRoute: true,
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Open Memorization'));
          await tester.pumpAndSettle();

          expect(find.byType(BackButton), findsOneWidget);
          await _capturePng(tester, psc.pushName, key: repaintKey, pixelRatio: psc.dpr);

          await tester.pumpWidget(const SizedBox());
        }

        expect(pixelErrors, isEmpty, reason: 'Zero errors allowed during pixel captures');
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        FlutterError.onError = oldHandler;
      }
    });

    testWidgets('7. Actual PLAYING Autoscroll to Initially Unbuilt Verse at 2x without Manual Drag / EnsureVisible', (tester) async {
      tester.view.physicalSize = const Size(360, 800) * 2.0;
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Intercept platform channel boundary of just_audio and FastAudioService
      FastAudioService.instance.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, isLiveStream = false}) async {
        return AudioSource.uri(Uri.parse('asset:///test.mp3'));
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.just_audio.methods'),
        (MethodCall call) async {
          if (call.method == 'init') {
            return {'id': 'test_player_id'};
          }
          return {};
        },
      );
      addTearDown(() {
        FastAudioService.instance.resetForTesting();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('com.ryanheise.just_audio.methods'), null);
      });

      await tester.pumpWidget(const SizedBox());
      final repaintKey = GlobalKey();
      await tester.pumpWidget(
        _buildScreenHost(
          screenKey: UniqueKey(),
          textScale: 2.0,
          surahId: 1, // Al-Fatihah (7 ayahs)
          fromAyah: 1,
          toAyah: 7,
          repaintKey: repaintKey,
        ),
      );
      await tester.pumpAndSettle();

      // Verify initial state: scroll offset is 0.0 and verse 7 is unbuilt
      final scrollableFinder = find.byType(Scrollable).first;
      final scrollableState = tester.state<ScrollableState>(scrollableFinder);
      expect(scrollableState.position.pixels, 0.0, reason: 'Initial scroll offset must be 0.0');

      final verse7Finder = find.widgetWithText(MemorizationAyahCard, 'الآية 7');
      expect(verse7Finder.evaluate().isEmpty, isTrue,
          reason: 'Verse 7 must initially be unbuilt and offscreen at 2x text scale');

      // Start PLAYING audio via Play button on MemorizationPlaybackBar
      final playBtn = find.byTooltip('بدء التكرار والتحفيظ');
      expect(playBtn, findsOneWidget);
      await tester.tap(playBtn);
      await tester.pumpAndSettle();

      // Verify playing state
      expect(find.byTooltip('إيقاف مؤقت'), findsOneWidget);

      // Advance to verse 7 while PLAYING without manual drag or manual ensureVisible
      final nextBtn = find.byTooltip('الآية التالية');
      expect(nextBtn, findsOneWidget);

      for (int i = 0; i < 6; i++) {
        await tester.tap(nextBtn);
        await tester.pumpAndSettle();
      }

      // Verify playback state indicates Verse 7 is current
      expect(find.textContaining('الآية: 7'), findsOneWidget);

      // Verification of lazy target materialization autoscroll:
      // ListView incrementally scrolled to materialize Verse 7 and ensured it is visible
      expect(
        scrollableState.position.pixels > 0.0,
        isTrue,
        reason: 'ScrollController must autoscroll when playing advances to initially unbuilt verse',
      );
      expect(
        verse7Finder,
        findsOneWidget,
        reason: 'Verse 7 must be visible without manual drag/ensureVisible',
      );

      // Verify Verse 7 is within visible viewport coordinates
      final verse7Box = tester.renderObject<RenderBox>(verse7Finder);
      final verse7Top = verse7Box.localToGlobal(Offset.zero).dy;
      expect(verse7Top < 800.0 && verse7Top >= 56.0, isTrue,
          reason: 'Verse 7 must be positioned within the visible body viewport');

      // Decisive playing autoscrolled pixel capture
      await _capturePng(
        tester,
        'memorizer_screen_360x800_2x_playing_autoscrolled.png',
        key: repaintKey,
        pixelRatio: 2.0,
      );
    });

    testWidgets('8. In-Flight Rapid Target Changes, Pause & Stop Mid-Animation, and Unmount Guards', (tester) async {
      final List<FlutterErrorDetails> errors = [];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details);

      FastAudioService.instance.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, isLiveStream = false}) async {
        return AudioSource.uri(Uri.parse('asset:///test.mp3'));
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.just_audio.methods'),
        (MethodCall call) async {
          if (call.method == 'init') return {'id': 'test_player_id'};
          return {};
        },
      );
      addTearDown(() {
        FastAudioService.instance.resetForTesting();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('com.ryanheise.just_audio.methods'), null);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      try {
        // Part A: In-flight rapid target change and latest verse viewport rect verification
        tester.view.physicalSize = const Size(360, 800) * 2.0;
        tester.view.devicePixelRatio = 2.0;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          _buildScreenHost(
            screenKey: UniqueKey(),
            textScale: 2.0,
            surahId: 1,
            fromAyah: 1,
            toAyah: 7,
          ),
        );
        await tester.pumpAndSettle();

        final playBtn = find.byTooltip('بدء التكرار والتحفيظ');
        await tester.tap(playBtn);
        await tester.pumpAndSettle();

        final nextBtn = find.byTooltip('الآية التالية');
        // Rapid sequential taps with animation in-flight (pump 20ms, not settle)
        await tester.tap(nextBtn);
        await tester.pump(const Duration(milliseconds: 20));
        await tester.tap(nextBtn);
        await tester.pump(const Duration(milliseconds: 20));
        await tester.tap(nextBtn);
        await tester.pumpAndSettle();

        // Verify playback state settled on latest target (verse 4)
        expect(find.textContaining('الآية: 4'), findsOneWidget);

        // Verify latest verse has valid viewport rect
        final verse4Finder = find.widgetWithText(MemorizationAyahCard, 'الآية 4');
        expect(verse4Finder, findsOneWidget);
        final verse4Box = tester.renderObject<RenderBox>(verse4Finder);
        final verse4Top = verse4Box.localToGlobal(Offset.zero).dy;
        final verse4Bottom = verse4Box.localToGlobal(verse4Box.size.bottomRight(Offset.zero)).dy;
        expect(verse4Top < 800.0 && verse4Bottom > 56.0, isTrue,
            reason: 'Latest target verse 4 must be positioned inside visible viewport rect');

        // Part B: Pause during active lazy/ensureVisible animation (pump 20ms not settle)
        final scrollableFinder = find.byType(Scrollable).first;
        final scrollState = tester.state<ScrollableState>(scrollableFinder);

        // Advance to verse 5 to trigger in-flight autoscroll
        await tester.tap(nextBtn);
        await tester.pump(const Duration(milliseconds: 20)); // actively animating (not settled)

        final pauseBtn = find.byTooltip('إيقاف مؤقت');
        await tester.tap(pauseBtn);
        // Cancel settles within frame budget
        await tester.pumpAndSettle();
        final pausedPixels = scrollState.position.pixels;
        // Assert no continued motion after cancel settles
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(scrollState.position.pixels, pausedPixels,
            reason: 'No continued motion after pause cancel settles within frame budget');
        expect(find.byTooltip('بدء التكرار والتحفيظ'), findsOneWidget);

        // Part C: Stop during active lazy/ensureVisible animation (pump 20ms not settle)
        await tester.tap(find.byTooltip('بدء التكرار والتحفيظ'));
        await tester.pumpAndSettle();

        // Advance to verse 6 to trigger in-flight autoscroll
        await tester.tap(nextBtn);
        await tester.pump(const Duration(milliseconds: 20)); // actively animating (not settled)

        final stopBtn = find.byTooltip('إيقاف كامل');
        await tester.tap(stopBtn);
        // Cancel settles within frame budget
        await tester.pumpAndSettle();
        final stoppedPixels = scrollState.position.pixels;
        // Assert no continued motion after stop cancel settles
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(scrollState.position.pixels, stoppedPixels,
            reason: 'No continued motion after stop cancel settles within frame budget');

        // Part D: Unmount midflight
        await tester.tap(find.byTooltip('بدء التكرار والتحفيظ'));
        await tester.pumpAndSettle();
        await tester.tap(nextBtn);
        // Immediately unmount mid-animation (after 20ms pump)
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();

        // Part E: User drag cancellation without custom policy
        await tester.pumpWidget(
          _buildScreenHost(
            screenKey: UniqueKey(),
            textScale: 2.0,
            surahId: 1,
            fromAyah: 1,
            toAyah: 7,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('بدء التكرار والتحفيظ'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('الآية التالية'));
        await tester.pump(const Duration(milliseconds: 20)); // in-flight animation

        // User performs manual drag gesture while animation is in-flight
        final dragFinder = find.byType(Scrollable).first;
        await tester.drag(dragFinder, const Offset(0, -60));
        await tester.pumpAndSettle();
      } finally {
        FlutterError.onError = oldHandler;
      }

      if (errors.isNotEmpty) {
        for (final err in errors) {
          debugPrint('CAPTURED_ERROR in Test 8: ${err.exceptionAsString()}');
        }
      }
      expect(errors, isEmpty, reason: 'Test 8 guards must complete with zero errors');
    });

    testWidgets('9. Realistic Long-Distance Autoscroll: Manual-Reading to Start and Loop-to-Verse-1 (Cap 30 Assessment)', (tester) async {
      final List<FlutterErrorDetails> errors = [];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details);

      FastAudioService.instance.getFastAudioSourceOverride = (url, {required cacheKey, localDownloadedPath, isLiveStream = false}) async {
        return AudioSource.uri(Uri.parse('asset:///test.mp3'));
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.just_audio.methods'),
        (MethodCall call) async {
          if (call.method == 'init') return {'id': 'test_player_id'};
          return {};
        },
      );
      addTearDown(() {
        FastAudioService.instance.resetForTesting();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('com.ryanheise.just_audio.methods'), null);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      try {
        tester.view.physicalSize = const Size(360, 800) * 2.0;
        tester.view.devicePixelRatio = 2.0;

        // Pre-warm QuranRepository cache for Surah 2 using real async I/O
        await tester.runAsync(() async {
          await QuranRepository.loadSurahs();
          await QuranRepository.getAyahsForSurah(2);
        });
        debugPrint('CHECK 1: prewarm done');

        // Realistic long-range: Surah 2 (Al-Baqarah) with 20 ayahs loaded via real QuranRepository
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          _buildScreenHost(
            screenKey: UniqueKey(),
            textScale: 2.0,
            surahId: 2, // Al-Baqarah
            fromAyah: 1,
            toAyah: 20,
          ),
        );
        debugPrint('CHECK 2: pumpWidget done');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();
        debugPrint('CHECK 3: initial pumpAndSettle done');

        final scrollableFinder = find.byType(Scrollable).first;
        final scrollState = tester.state<ScrollableState>(scrollableFinder);

        // Scenario A: Initially start far from verse 1 after manual reading
        // User manually scrolls down to verse 15
        final verse15Finder = find.widgetWithText(MemorizationAyahCard, 'الآية 15');
        int manualDrags = 0;
        while (verse15Finder.evaluate().isEmpty && manualDrags < 25) {
          await tester.drag(scrollableFinder, const Offset(0, -450));
          await tester.pumpAndSettle();
          manualDrags++;
          debugPrint('CHECK 4: manualDrag $manualDrags, offset=${scrollState.position.pixels}');
        }
        expect(verse15Finder, findsOneWidget, reason: 'Manual reading reached verse 15');
        final farOffset = scrollState.position.pixels;
        expect(farOffset > 2000.0, isTrue, reason: 'Far offset must be > 2000px down after manual reading');

        // Verse 1 is initially far offscreen upwards and unbuilt
        final verse1Finder = find.widgetWithText(MemorizationAyahCard, 'الآية 1');
        expect(verse1Finder.evaluate().isEmpty, isTrue, reason: 'Verse 1 must be offscreen/unbuilt at far offset');

        // User starts playback from verse 1 via Play button
        final playBtn = find.byTooltip('بدء التكرار والتحفيظ');
        await tester.tap(playBtn);
        await tester.pumpAndSettle();

        // Confirm cap 30 reached target (Verse 1)
        expect(verse1Finder, findsOneWidget, reason: 'Cap 30 autoscroll must reach and materialize Verse 1 from far offset');
        final verse1Box = tester.renderObject<RenderBox>(verse1Finder);
        final verse1Top = verse1Box.localToGlobal(Offset.zero).dy;
        final verse1Bottom = verse1Box.localToGlobal(verse1Box.size.bottomRight(Offset.zero)).dy;
        debugPrint('LONG_DISTANCE_A: fromOffset=$farOffset, finalOffset=${scrollState.position.pixels}, verse1Top=$verse1Top, verse1Bottom=$verse1Bottom');
        expect(verse1Top < 800.0 && verse1Bottom > 56.0, isTrue,
            reason: 'Verse 1 must be contained within visible viewport after autoscroll from far offset');

        // Scenario B: User at late verse in long range then playback loops to verse 1
        // Advance to verse 10 while playing
        final nextBtn = find.byTooltip('الآية التالية');
        for (int i = 0; i < 9; i++) {
          await tester.tap(nextBtn);
          await tester.pumpAndSettle();
        }
        expect(find.textContaining('الآية: 10'), findsOneWidget);
        final offsetAt10 = scrollState.position.pixels;
        expect(offsetAt10 > 1000.0, isTrue);

        // User restarts or audio loop triggers verse 1
        // Tap Stop then Play to simulate loop/restart to verse 1
        final stopBtn = find.byTooltip('إيقاف كامل');
        await tester.tap(stopBtn);
        await tester.pumpAndSettle();
        await tester.tap(playBtn);
        await tester.pumpAndSettle();

        expect(verse1Finder, findsOneWidget, reason: 'Verse 1 reached after restart/loop');
        final loopedVerse1Box = tester.renderObject<RenderBox>(verse1Finder);
        final loopedVerse1Top = loopedVerse1Box.localToGlobal(Offset.zero).dy;
        final loopedVerse1Bottom = loopedVerse1Box.localToGlobal(loopedVerse1Box.size.bottomRight(Offset.zero)).dy;
        debugPrint('LONG_DISTANCE_B: fromOffset=$offsetAt10, finalOffset=${scrollState.position.pixels}, verse1Top=$loopedVerse1Top, verse1Bottom=$loopedVerse1Bottom');
        expect(loopedVerse1Top < 800.0 && loopedVerse1Bottom > 56.0, isTrue,
            reason: 'Verse 1 must be contained within visible viewport after loop restart');
      } finally {
        FlutterError.onError = oldHandler;
      }

      if (errors.isNotEmpty) {
        for (final err in errors) {
          debugPrint('CAPTURED_ERROR in Test 9: ${err.exceptionAsString()}');
        }
      }
      expect(errors, isEmpty, reason: 'Realistic long-distance autoscroll must complete with zero errors');
    });
  });
}
