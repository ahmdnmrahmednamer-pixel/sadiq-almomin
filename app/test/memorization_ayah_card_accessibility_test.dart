import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/models/ayah.dart';
import 'package:almomin/core/models/memorization_item.dart';
import 'package:almomin/core/services/memorization_service.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/mushaf/memorization_screen.dart';
import 'package:almomin/features/mushaf/widgets/memorization_ayah_card.dart';

const String _kAfterPixelDir =
    r'C:\Users\Dell\.gemini\antigravity\brain\aaa5e77e-874d-485e-8088-962b9e3f1086\repair22_after_pixels';
const String _kMaterialIcons =
    r'D:\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf';

final GlobalKey _kRepaintKey = GlobalKey();

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

Future<void> _capturePng(WidgetTester tester, String fileName, {double pixelRatio = 1.0}) async {
  await tester.runAsync(() async {
    final boundary =
        _kRepaintKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    Directory(_kAfterPixelDir).createSync(recursive: true);
    File('$_kAfterPixelDir/$fileName').writeAsBytesSync(byteData!.buffer.asUint8List());
  });
}

SemanticsNode _findTappableNode(WidgetTester tester, String labelSubstring) {
  SemanticsNode? found;
  void visit(SemanticsNode n) {
    final d = n.getSemanticsData();
    if (d.label.contains(labelSubstring) && d.hasAction(SemanticsAction.tap)) {
      found = n;
      return;
    }
    n.visitChildren((c) {
      visit(c);
      return found == null;
    });
  }

  visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  expect(
    found,
    isNotNull,
    reason: 'Expected tappable SemanticsNode containing "$labelSubstring"',
  );
  return found!;
}

Widget _buildCardHost({
  required Ayah ayah,
  required MemorizationHideMode hideMode,
  Set<String> revealedWords = const {},
  void Function(int, int)? onToggle,
  void Function(Ayah, MemorizationRating)? onRate,
  double textScale = 1.0,
}) {
  return RepaintBoundary(
    key: _kRepaintKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(textScale),
              accessibleNavigation: true,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: MemorizationAyahCard(
                  ayah: ayah,
                  surahId: ayah.surahId,
                  isCurrentPlaying: false,
                  isDelaying: false,
                  remainingDelaySeconds: 0,
                  currentAyahRepeat: 1,
                  ayahRepeatTarget: 3,
                  hideMode: hideMode,
                  revealedWords: revealedWords,
                  isDark: false,
                  onToggleWordReveal: onToggle ?? (_, __) {},
                  onRateAyah: onRate ?? (_, __) {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _buildScreenHost({
  required double scale,
  bool isDark = false,
}) {
  return RepaintBoundary(
    key: _kRepaintKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(scale),
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

const Ayah _kSampleAyah1 = Ayah(
  id: 1,
  surahId: 1,
  ayahNumber: 1,
  juz: 1,
  hizb: 1,
  rub: 1,
  page: 1,
  sajdah: 0,
  textUthmani: 'بِسۡمِ ٱللَّهِ ٱلرَّحۡمَـٰنِ ٱلرَّحِیمِ',
  textImlaei: 'بسم الله الرحمن الرحيم',
  textSearch: 'بسم الله الرحمن الرحيم',
);

/// Strips all Arabic harakat / diacritics and Quranic marks for deep privacy comparison
String _stripArabicTashkeel(String input) {
  return input.replaceAll(RegExp(r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED]'), '');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
    await MemorizationService.instance.init();
    await _loadRealFonts();
  });

  group('Repair 22 — Dedicated MemorizationAyahCard Accessibility Tests', () {
    testWidgets('1. No-Mask Mode (hideMode.none): Whole verse + number is ONE non-button node, 0 word noops', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _buildCardHost(
          ayah: _kSampleAyah1,
          hideMode: MemorizationHideMode.none,
        ),
      );
      await tester.pumpAndSettle();

      // Exactly 3 InkWells should exist in the card (the 3 rating buttons). ZERO word InkWells.
      final inkWells = find.byType(InkWell);
      expect(inkWells, findsNWidgets(3));

      // Inspect Semantics tree of the card
      final cardFinder = find.byType(MemorizationAyahCard);
      expect(cardFinder, findsOneWidget);

      final renderObject = tester.renderObject(cardFinder);
      final List<String> nodeLabels = [];
      final List<String> buttonLabels = [];

      void inspectNode(SemanticsNode node) {
        final data = node.getSemanticsData();
        if (data.label.isNotEmpty) {
          nodeLabels.add(data.label);
          if (data.hasAction(SemanticsAction.tap)) {
            buttonLabels.add(data.label);
          }
        }
        node.visitChildren((child) {
          inspectNode(child);
          return true;
        });
      }

      inspectNode(renderObject.debugSemantics!);

      // The whole verse text and number should exist as ONE single node
      final formattedNumber = SettingsService.instance.formatAyahNumber(_kSampleAyah1.ayahNumber);
      final expectedVerseText = '${_kSampleAyah1.cleanTextUthmani} ﴿$formattedNumber﴾';
      expect(nodeLabels.contains(expectedVerseText), isTrue);

      // Verify that this verse text node is NOT a button and has NO tap action
      void verifyNonButton(SemanticsNode node) {
        final data = node.getSemanticsData();
        if (data.label == expectedVerseText) {
          expect(data.hasAction(SemanticsAction.tap), isFalse);
          expect(data.hasFlag(SemanticsFlag.isButton), isFalse);
        }
        node.visitChildren((child) {
          verifyNonButton(child);
          return true;
        });
      }
      verifyNonButton(renderObject.debugSemantics!);

      // Buttons in card must ONLY be the 3 rating actions
      expect(buttonLabels, containsAll(['متقن', 'تثبيت', 'نسيت']));
      expect(buttonLabels.length, equals(3));

      handle.dispose();
    });

    testWidgets('2. Active Mask Mode: secondHalf renders first-half as plainText and second-half as indexed masked pills', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _buildCardHost(
          ayah: _kSampleAyah1,
          hideMode: MemorizationHideMode.secondHalf,
        ),
      );
      await tester.pumpAndSettle();

      // Words in Ayah 1 (4 words): indices 0,1 are naturally visible; indices 2,3 are masked.
      // Masked pills must have clear indexed labels: 'الكلمة 3 مخفية، انقر للإظهار', 'الكلمة 4 مخفية، انقر للإظهار'
      expect(find.bySemanticsLabel('الكلمة 3 مخفية، انقر للإظهار'), findsOneWidget);
      expect(find.bySemanticsLabel('الكلمة 4 مخفية، انقر للإظهار'), findsOneWidget);

      // Naturally visible words must be plainText without tap actions
      final cardFinder = find.byType(MemorizationAyahCard);
      final renderObject = tester.renderObject(cardFinder);

      void checkNaturallyVisible(SemanticsNode node) {
        final data = node.getSemanticsData();
        if (data.label == 'بِسۡمِ' || data.label == 'ٱللَّهِ') {
          expect(data.hasAction(SemanticsAction.tap), isFalse);
          expect(data.hasFlag(SemanticsFlag.isButton), isFalse);
        }
        node.visitChildren((child) {
          checkNaturallyVisible(child);
          return true;
        });
      }
      checkNaturallyVisible(renderObject.debugSemantics!);

      handle.dispose();
    });

    testWidgets('3. Active Mask Mode: everyNthWord masks odd words and keeps even words plainText', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _buildCardHost(
          ayah: _kSampleAyah1,
          hideMode: MemorizationHideMode.everyNthWord,
        ),
      );
      await tester.pumpAndSettle();

      // Indices 1 and 3 are masked
      expect(find.bySemanticsLabel('الكلمة 2 مخفية، انقر للإظهار'), findsOneWidget);
      expect(find.bySemanticsLabel('الكلمة 4 مخفية، انقر للإظهار'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('4. Active Mask Mode: allWords masks all words with clear indexed labels and zero word leakage', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _buildCardHost(
          ayah: _kSampleAyah1,
          hideMode: MemorizationHideMode.allWords,
        ),
      );
      await tester.pumpAndSettle();

      // All 4 words are masked pills
      expect(find.bySemanticsLabel('الكلمة 1 مخفية، انقر للإظهار'), findsOneWidget);
      expect(find.bySemanticsLabel('الكلمة 2 مخفية، انقر للإظهار'), findsOneWidget);
      expect(find.bySemanticsLabel('الكلمة 3 مخفية، انقر للإظهار'), findsOneWidget);
      expect(find.bySemanticsLabel('الكلمة 4 مخفية، انقر للإظهار'), findsOneWidget);

      // Zero hidden word leakage across entire semantics subtree, allfields, and TextSpans
      final renderObject = tester.renderObject(find.byType(MemorizationAyahCard));
      void verifyNoLeakage(SemanticsNode node) {
        final data = node.getSemanticsData();
        for (final text in [
          data.label,
          data.attributedLabel.string,
          data.value,
          data.attributedValue.string,
          data.hint,
          data.attributedHint.string,
          data.tooltip,
        ]) {
          if (text.isNotEmpty) {
            expect(text.contains('بِسۡمِ'), isFalse);
            expect(text.contains('ٱللَّهِ'), isFalse);
            expect(text.contains('ٱلرَّحۡمَـٰنِ'), isFalse);
            expect(text.contains('ٱلرَّحِیمِ'), isFalse);
          }
        }
        node.visitChildren((child) {
          verifyNoLeakage(child);
          return true;
        });
      }
      verifyNoLeakage(renderObject.debugSemantics!);

      // Verify all widget TextSpans under masked pills
      for (int i = 1; i <= 4; i++) {
        final pillFinder = find.bySemanticsLabel('الكلمة $i مخفية، انقر للإظهار');
        final richTexts = tester.widgetList<RichText>(
          find.descendant(of: pillFinder, matching: find.byType(RichText)),
        );
        for (final rt in richTexts) {
          final spanText = rt.text.toPlainText();
          for (final word in ['بِسۡمِ', 'ٱللَّهِ', 'ٱلرَّحۡمَـٰنِ', 'ٱلرَّحِیمِ']) {
            expect(spanText.contains(word), isFalse);
          }
        }
      }

      handle.dispose();
    });

    testWidgets('5. Tap-to-Reveal and Tap-to-Rehide dispatch and state transitions: Semantic dispatch on eligible words in each mode', (tester) async {
      final handle = tester.ensureSemantics();

      // Test semantic dispatch across each active mask mode
      final modeConfigs = [
        (mode: MemorizationHideMode.allWords, eligibleWordIndex: 0, wordText: 'بِسۡمِ'),
        (mode: MemorizationHideMode.secondHalf, eligibleWordIndex: 2, wordText: 'ٱلرَّحۡمَـٰنِ'),
        (mode: MemorizationHideMode.everyNthWord, eligibleWordIndex: 1, wordText: 'ٱللَّهِ'),
      ];

      for (final config in modeConfigs) {
        int toggledAyah = -1;
        int toggledWordIdx = -1;

        // Step 1: Pump initial state with masked words
        await tester.pumpWidget(
          _buildCardHost(
            ayah: _kSampleAyah1,
            hideMode: config.mode,
            revealedWords: {},
            onToggle: (ayahNum, wordIdx) {
              toggledAyah = ayahNum;
              toggledWordIdx = wordIdx;
            },
          ),
        );
        await tester.pumpAndSettle();

        // Step 2: Locate masked pill SemanticsNode for eligible word
        final maskedLabel = 'الكلمة ${config.eligibleWordIndex + 1} مخفية، انقر للإظهار';
        final maskedNode = _findTappableNode(tester, maskedLabel);
        final maskedData = maskedNode.getSemanticsData();

        // Assert button via hasFlag and tap action
        expect(maskedData.hasFlag(SemanticsFlag.isButton), isTrue);
        expect(maskedData.hasAction(SemanticsAction.tap), isTrue);

        // Step 3: Dispatch SemanticsAction.tap
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          maskedNode.id,
          SemanticsAction.tap,
        );
        await tester.pumpAndSettle();

        // Verify callback index and state
        expect(toggledAyah, equals(_kSampleAyah1.ayahNumber));
        expect(toggledWordIdx, equals(config.eligibleWordIndex));

        // Step 4: Pump updated state with the word revealed
        final revealedKey = '${_kSampleAyah1.ayahNumber}:${config.eligibleWordIndex}';
        int rehideAyah = -1;
        int rehideWordIdx = -1;
        await tester.pumpWidget(
          _buildCardHost(
            ayah: _kSampleAyah1,
            hideMode: config.mode,
            revealedWords: {revealedKey},
            onToggle: (ayahNum, wordIdx) {
              rehideAyah = ayahNum;
              rehideWordIdx = wordIdx;
            },
          ),
        );
        await tester.pumpAndSettle();

        // Step 5: Locate revealed word SemanticsNode
        final revealedLabel = 'الكلمة ${config.eligibleWordIndex + 1}: ${config.wordText}، مظهرة، انقر للإخفاء';
        final revealedNode = _findTappableNode(tester, revealedLabel);
        final revealedData = revealedNode.getSemanticsData();

        // Assert button via hasFlag and tap action
        expect(revealedData.hasFlag(SemanticsFlag.isButton), isTrue);
        expect(revealedData.hasAction(SemanticsAction.tap), isTrue);

        // Step 6: Dispatch SemanticsAction.tap to re-hide
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          revealedNode.id,
          SemanticsAction.tap,
        );
        await tester.pumpAndSettle();

        // Verify re-hide callback index
        expect(rehideAyah, equals(_kSampleAyah1.ayahNumber));
        expect(rehideWordIdx, equals(config.eligibleWordIndex));
      }

      handle.dispose();
    });

    testWidgets('6. Rating Callbacks dispatch with correct rating enum values', (tester) async {
      MemorizationRating? recordedRating;

      await tester.pumpWidget(
        _buildCardHost(
          ayah: _kSampleAyah1,
          hideMode: MemorizationHideMode.none,
          onRate: (_, rating) {
            recordedRating = rating;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('متقن'));
      expect(recordedRating, equals(MemorizationRating.easy));

      await tester.tap(find.text('تثبيت'));
      expect(recordedRating, equals(MemorizationRating.hard));

      await tester.tap(find.text('نسيت'));
      expect(recordedRating, equals(MemorizationRating.forgot));
    });

    testWidgets('7. Rating Row Responsive Layout: 3.6px overflow fixed via Wrap on 360 width @ 2.0x text scale', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Pump card under 2.0x text scale
      await tester.pumpWidget(
        _buildCardHost(
          ayah: _kSampleAyah1,
          hideMode: MemorizationHideMode.none,
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      // Zero RenderFlex overflow within MemorizationAyahCard
      expect(tester.takeException(), isNull);
    });

    testWidgets('8. Real Screen Verse Flow & Zero RenderFlex Overflows Across Entire Screen', (tester) async {
      final List<FlutterErrorDetails> capturedErrors = [];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        capturedErrors.add(details);
        oldHandler?.call(details);
      };

      try {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(_buildScreenHost(scale: 2.0));
        await tester.pumpAndSettle();

        // Switch modes and verify smooth state change
        final secondHalf = find.text('إخفاء النصف الثاني');
        await tester.ensureVisible(secondHalf);
        await tester.tap(secondHalf);
        await tester.pumpAndSettle();

        expect(find.text('••••••'), findsWidgets);

        // Verification: Zero errors allowed across entire screen (including responsive playback bar and cards)
        expect(capturedErrors, isEmpty, reason: 'Zero RenderFlex errors or card/playback-bar overflows allowed');
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        FlutterError.onError = oldHandler;
      }
    });

    testWidgets('9. True Loaded-Font Pixel Proofs Across 360/412 @ 1x/2x + Scrolled Card', (tester) async {
      final List<FlutterErrorDetails> unexpectedErrors = [];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        unexpectedErrors.add(details);
        oldHandler?.call(details);
      };

      final scenarios = [
        (size: const Size(360, 800), dpr: 1.0, scale: 1.0, name: 'memorizer_card_360x800_1x.png'),
        (size: const Size(360, 800), dpr: 2.0, scale: 2.0, name: 'memorizer_card_360x800_2x.png'),
        (size: const Size(412, 915), dpr: 1.0, scale: 1.0, name: 'memorizer_card_412x915_1x.png'),
        (size: const Size(412, 915), dpr: 2.0, scale: 2.0, name: 'memorizer_card_412x915_2x.png'),
      ];

      try {
        for (final sc in scenarios) {
          tester.view.devicePixelRatio = sc.dpr;
          tester.view.physicalSize = Size(sc.size.width * sc.dpr, sc.size.height * sc.dpr);

          await tester.pumpWidget(_buildScreenHost(scale: sc.scale));
          await tester.pumpAndSettle();

          await _capturePng(tester, sc.name, pixelRatio: sc.dpr);
        }

        // Scrolled card proof: scroll down to reveal later cards
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = const Size(360 * 2.0, 800 * 2.0);
        await tester.pumpWidget(_buildScreenHost(scale: 2.0));
        await tester.pumpAndSettle();

        await tester.drag(find.byType(ListView).first, const Offset(0, -300));
        await tester.pumpAndSettle();

        await _capturePng(tester, 'memorizer_card_scrolled_360x800_2x.png', pixelRatio: 2.0);

        expect(unexpectedErrors, isEmpty, reason: 'Zero non-playback-bar errors allowed in pixel tests');
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        FlutterError.onError = oldHandler;
      }
    });

    testWidgets('10. Corpus-Derived Exact Privacy Audit: Zero hidden-word text, spans, or stems leak across all Ayahs & mask modes', (tester) async {
      final handle = tester.ensureSemantics();

      final fatihahAyahs = await QuranRepository.getAyahsForSurah(1);
      final ikhlasAyahs = await QuranRepository.getAyahsForSurah(112);
      final corpusAyahs = [...fatihahAyahs, ...ikhlasAyahs];

      const modesToTest = [
        MemorizationHideMode.allWords,
        MemorizationHideMode.secondHalf,
        MemorizationHideMode.everyNthWord,
      ];

      for (final ayah in corpusAyahs) {
        final words = MemorizationMaskHelper.splitAyahWords(ayah.cleanTextUthmani);

        for (final mode in modesToTest) {
          await tester.pumpWidget(
            _buildCardHost(
              ayah: ayah,
              hideMode: mode,
            ),
          );
          await tester.pumpAndSettle();

          final cardFinder = find.byType(MemorizationAyahCard);
          expect(cardFinder, findsOneWidget);
          final renderObject = tester.renderObject(cardFinder);

          final List<SemanticsData> allCardSemantics = [];
          void collectSemantics(SemanticsNode node) {
            allCardSemantics.add(node.getSemanticsData());
            node.visitChildren((child) {
              collectSemantics(child);
              return true;
            });
          }
          collectSemantics(renderObject.debugSemantics!);

          for (int wIdx = 0; wIdx < words.length; wIdx++) {
            final isEligible = MemorizationMaskHelper.isWordMasked(
              wordIndex: wIdx,
              totalWords: words.length,
              mode: mode,
              isRevealed: false,
            );

            if (isEligible) {
              final rawWord = words[wIdx];
              final strippedWord = _stripArabicTashkeel(rawWord).trim();

              // 1. Verify masked pill label matches exact indexed template
              final expectedPillLabel = 'الكلمة ${wIdx + 1} مخفية، انقر للإظهار';
              final matchingPill = allCardSemantics.where((s) => s.label == expectedPillLabel).toList();
              expect(
                matchingPill.length,
                equals(1),
                reason: 'Ayah ${ayah.surahId}:${ayah.ayahNumber} word $wIdx must have indexed masked pill',
              );
              final pillData = matchingPill.first;

              // Must be a focusable button with tap action
              expect(pillData.hasAction(SemanticsAction.tap), isTrue);
              expect(pillData.hasFlag(SemanticsFlag.isButton), isTrue);

              // 2. Strict Privacy across entire hiddenSubtree and allfields
              SemanticsNode? pillNode;
              void findPillNode(SemanticsNode n) {
                if (n.getSemanticsData().label == expectedPillLabel) {
                  pillNode = n;
                  return;
                }
                n.visitChildren((c) {
                  findPillNode(c);
                  return pillNode == null;
                });
              }
              findPillNode(renderObject.debugSemantics!);
              expect(pillNode, isNotNull);

              void verifyNodeSubtreePrivacy(SemanticsNode n) {
                final d = n.getSemanticsData();
                for (final text in [
                  d.label,
                  d.attributedLabel.string,
                  d.value,
                  d.attributedValue.string,
                  d.hint,
                  d.attributedHint.string,
                  d.tooltip,
                ]) {
                  if (text.isNotEmpty) {
                    expect(
                      text.contains(rawWord),
                      isFalse,
                      reason: 'Corpus leak: raw word "$rawWord" leaked in semantics field "$text" for ${ayah.surahId}:${ayah.ayahNumber}',
                    );
                    if (strippedWord.length >= 3) {
                      expect(
                        text.contains(strippedWord),
                        isFalse,
                        reason: 'Corpus stem leak: stripped stem "$strippedWord" leaked in semantics field "$text"',
                      );
                    }
                  }
                }
                n.visitChildren((c) {
                  verifyNodeSubtreePrivacy(c);
                  return true;
                });
              }
              verifyNodeSubtreePrivacy(pillNode!);

              // 3. Strict Privacy in widget tree & TextSpan under this masked pill
              final pillFinder = find.bySemanticsLabel(expectedPillLabel);
              expect(pillFinder, findsOneWidget);

              final textWidgets = tester.widgetList<Text>(
                find.descendant(of: pillFinder, matching: find.byType(Text)),
              );
              for (final t in textWidgets) {
                final tStr = t.data ?? (t.textSpan?.toPlainText() ?? '');
                expect(
                  tStr.contains(rawWord),
                  isFalse,
                  reason: 'Corpus leak: raw word "$rawWord" leaked into Text widget under pill',
                );
                if (strippedWord.length >= 3) {
                  expect(
                    tStr.contains(strippedWord),
                    isFalse,
                    reason: 'Corpus stem leak: stripped stem "$strippedWord" leaked into Text widget under pill',
                  );
                }
              }

              final richTextWidgets = tester.widgetList<RichText>(
                find.descendant(of: pillFinder, matching: find.byType(RichText)),
              );
              for (final rt in richTextWidgets) {
                final spanStr = rt.text.toPlainText();
                expect(
                  spanStr.contains(rawWord),
                  isFalse,
                  reason: 'Corpus leak: raw word "$rawWord" leaked into RichText TextSpan under pill',
                );
                if (strippedWord.length >= 3) {
                  expect(
                    spanStr.contains(strippedWord),
                    isFalse,
                    reason: 'Corpus stem leak: stripped stem "$strippedWord" leaked into RichText TextSpan under pill',
                  );
                }
              }
            } else {
              // Naturally visible words must be plain text without button flags or tap action
              final rawWord = words[wIdx];
              final matchingVisible = allCardSemantics.where((s) => s.label.contains(rawWord)).toList();
              expect(
                matchingVisible.isNotEmpty,
                isTrue,
                reason: 'Ayah ${ayah.surahId}:${ayah.ayahNumber} word $wIdx ("$rawWord") must be naturally visible',
              );
              final visibleData = matchingVisible.first;
              expect(
                visibleData.hasAction(SemanticsAction.tap),
                isFalse,
                reason: 'Naturally visible word "$rawWord" must not have tap action',
              );
              expect(
                visibleData.hasFlag(SemanticsFlag.isButton),
                isFalse,
                reason: 'Naturally visible word "$rawWord" must not be button',
              );
            }
          }
        }
      }

      handle.dispose();
    });
  });
}
